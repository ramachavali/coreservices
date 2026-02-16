from flask import Flask, render_template
import os


app = Flask(__name__)


@app.get("/")
def home():
    links = [
        {
            "name": "Vault UI",
            "url": os.getenv("VAULT_UI_URL", "https://vault.local"),
            "description": "Secrets management and policy administration",
        },
        {
            "name": "Logto UI",
            "url": os.getenv("LOGTO_UI_URL", "https://auth.local"),
            "description": "Authentication and identity management",
        },
        {
            "name": "Traefik Dashboard",
            "url": os.getenv("TRAEFIK_UI_URL", "https://traefik.local"),
            "description": "Routing and reverse-proxy status",
        },
    ]
    return render_template(
        "index.html",
        title=os.getenv("PORTAL_TITLE", "Core Services Portal"),
        links=links,
    )


@app.get("/health")
def health():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
