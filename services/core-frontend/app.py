import os
import threading
import time

import requests
from flask import Flask, jsonify, render_template

app = Flask(__name__)

TRAEFIK_API = os.getenv("TRAEFIK_API_URL", "http://traefik:8080/api")
POLL_INTERVAL = int(os.getenv("STATUS_POLL_INTERVAL", "30"))

_cache = {"services": [], "error": None, "updated_at": None}
_lock = threading.Lock()


def _probe(url):
    try:
        r = requests.get(url, timeout=3, allow_redirects=True)
        return "up", r.status_code
    except requests.ConnectionError:
        return "down", None
    except Exception:
        return "unknown", None


def _poll():
    while True:
        try:
            routers_raw = requests.get(f"{TRAEFIK_API}/http/routers", timeout=5).json()
            services_raw = requests.get(f"{TRAEFIK_API}/http/services", timeout=5).json()

            # service name -> first backend URL
            svc_backends = {}
            for svc in services_raw:
                servers = svc.get("loadBalancer", {}).get("servers", [])
                if servers:
                    svc_backends[svc["name"]] = servers[0]["url"]

            # service name -> host rule (from routers)
            svc_rule = {}
            for r in routers_raw:
                svc = r.get("service", "")
                if "@" not in svc:
                    svc += "@docker"
                svc_rule[svc] = r.get("rule", "")

            results = []
            for svc in services_raw:
                name = svc["name"]
                display = name.replace("@docker", "").replace("@internal", "")
                backend = svc_backends.get(name)
                health, code = _probe(backend) if backend else ("internal", None)
                results.append({
                    "name": display,
                    "rule": svc_rule.get(name, ""),
                    "health": health,
                    "http_status": code,
                })

            results.sort(key=lambda x: x["name"])
            with _lock:
                _cache.update(services=results, error=None, updated_at=time.time())

        except Exception as e:
            with _lock:
                _cache["error"] = str(e)

        time.sleep(POLL_INTERVAL)


threading.Thread(target=_poll, daemon=True).start()


@app.get("/")
def home():
    links = [
        {
            "name": "Vault UI",
            "url": os.getenv("VAULT_UI_URL", "https://vault.local"),
            "description": "Secrets management and policy administration",
        },
        {
            "name": "Traefik Dashboard",
            "url": os.getenv("TRAEFIK_UI_URL", "https://traefik.local"),
            "description": "Routing and reverse-proxy status",
        },
        {
            "name": "Grafana",
            "url": os.getenv("GRAFANA_UI_URL", "https://grafana.local"),
            "description": "Metrics visualization and operational dashboards",
        },
        {
            "name": "Alloy",
            "url": os.getenv("ALLOY_UI_URL", "https://alloy.local"),
            "description": "Grafana Alloy telemetry pipeline and agent UI",
        },
    ]
    return render_template(
        "index.html",
        title=os.getenv("PORTAL_TITLE", "Core Services Portal"),
        links=links,
    )


@app.get("/api/status")
def api_status():
    with _lock:
        return jsonify(dict(_cache))


@app.get("/health")
def health():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
