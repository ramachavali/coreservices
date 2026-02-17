#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

usage() {
  cat <<'EOF'
Usage:
  foolsm4-pki-build.sh \
    --out-dir <dir> \
    --ca-name "<CA Display Name>" \
    --hostname <primary-hostname> \
    [--san <dns-name>]... \
    [--days-ca <days>] \
    [--days-leaf <days>]

Examples:
  ./scripts/pki-build.sh --out-dir ./pki --ca-name "Foolsbook Local Root CA" --hostname foolsm4.home.arpa

  ./scripts/pki-build.sh --out-dir ./pki --ca-name "Foolsbook Local Root CA" \
    --hostname foolsm4.home.arpa --san foolsm4.home.arpa --san foolsm4.local

Outputs:
  <out-dir>/ca/rootCA.key
  <out-dir>/ca/rootCA.crt
  <out-dir>/nginx/<hostname>/privkey.pem
  <out-dir>/nginx/<hostname>/cert.pem
  <out-dir>/nginx/<hostname>/fullchain.pem
  <out-dir>/traefik/key.pem
  <out-dir>/traefik/cert.pem
  <out-dir>/client/ca_bundle.crt

Notes:
  - Avoid .local if you can (mDNS can be flaky). Prefer home.arpa with Pi-hole.
EOF
}

OUT_DIR=""
CA_NAME=""
HOSTNAME=""
DAYS_CA="3650"
DAYS_LEAF="825"
SANS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --ca-name) CA_NAME="$2"; shift 2 ;;
    --hostname) HOSTNAME="$2"; shift 2 ;;
    --san) SANS+=("$2"); shift 2 ;;
    --days-ca) DAYS_CA="$2"; shift 2 ;;
    --days-leaf) DAYS_LEAF="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$OUT_DIR" && -n "$CA_NAME" && -n "$HOSTNAME" ]] || { usage; exit 1; }

# Ensure primary hostname is always included as SAN
found=0
for s in "${SANS[@]:-}"; do [[ "$s" == "$HOSTNAME" ]] && found=1; done
[[ "${#SANS[@]}" -eq 0 || "$found" -eq 0 ]] && SANS+=("$HOSTNAME")

mkdir -p "$OUT_DIR"/{ca,nginx,client,tmp}
NGINX_DIR="$OUT_DIR/nginx/$HOSTNAME"
mkdir -p "$NGINX_DIR"

ROOT_KEY="$OUT_DIR/ca/rootCA.key"
ROOT_CRT="$OUT_DIR/ca/rootCA.crt"
CLIENT_BUNDLE="$OUT_DIR/client/ca_bundle.crt"

# 1) Root CA
if [[ -f "$ROOT_KEY" || -f "$ROOT_CRT" ]]; then
  echo "[i] Root CA already exists in $OUT_DIR/ca — reusing."
else
  echo "[+] Generating Root CA key"
  openssl genrsa -out "$ROOT_KEY" 4096
  chmod 600 "$ROOT_KEY"

  echo "[+] Generating Root CA certificate ($DAYS_CA days)"
  # Subject is generic + CA display name
  openssl req -x509 -new -nodes \
    -key "$ROOT_KEY" \
    -sha256 -days "$DAYS_CA" \
    -out "$ROOT_CRT" \
    -subj "/C=US/ST=MN/L=Home/O=Foolsbook/OU=Homelab/CN=${CA_NAME}"
fi

# 2) Leaf key + CSR with SANs
LEAF_KEY="$NGINX_DIR/privkey.pem"
CSR="$OUT_DIR/tmp/$HOSTNAME.csr"
LEAF_CRT="$NGINX_DIR/cert.pem"
FULLCHAIN="$NGINX_DIR/fullchain.pem"
TRAEFIK_DIR="$OUT_DIR/traefik"
mkdir -p "$TRAEFIK_DIR"

echo "[+] Generating leaf key for $HOSTNAME"
openssl genrsa -out "$LEAF_KEY" 2048
chmod 600 "$LEAF_KEY"

CONF="$OUT_DIR/tmp/$HOSTNAME.openssl.cnf"
{
  cat <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
C  = US
ST = MN
L  = Home
O  = FoolsNetwork
OU = FoolsLab
CN = $HOSTNAME

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
EOF
  i=1
  for d in "${SANS[@]}"; do
    echo "DNS.${i} = ${d}"
    i=$((i+1))
  done
} > "$CONF"

echo "[+] Generating CSR"
openssl req -new -key "$LEAF_KEY" -out "$CSR" -config "$CONF"

# 3) Sign leaf
V3="$OUT_DIR/tmp/v3-server.ext"
{
  cat <<'EOF'
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = @alt_names

[alt_names]
EOF
  i=1
  for d in "${SANS[@]}"; do
    echo "DNS.${i} = ${d}"
    i=$((i+1))
  done
} > "$V3"

echo "[+] Signing leaf certificate ($DAYS_LEAF days)"
openssl x509 -req \
  -in "$CSR" \
  -CA "$ROOT_CRT" \
  -CAkey "$ROOT_KEY" \
  -CAcreateserial \
  -out "$LEAF_CRT" \
  -days "$DAYS_LEAF" -sha256 \
  -extfile "$V3"

chmod 644 "$LEAF_CRT"

# 4) Create fullchain.pem (leaf + root)
cat "$LEAF_CRT" "$ROOT_CRT" > "$FULLCHAIN"
chmod 644 "$FULLCHAIN"

# 5) Traefik-friendly output names
cp "$LEAF_KEY" "$TRAEFIK_DIR/key.pem"
cp "$FULLCHAIN" "$TRAEFIK_DIR/cert.pem"
chmod 600 "$TRAEFIK_DIR/key.pem"
chmod 644 "$TRAEFIK_DIR/cert.pem"

# 6) Client CA bundle
cp "$ROOT_CRT" "$CLIENT_BUNDLE"
chmod 644 "$CLIENT_BUNDLE"

echo
echo "✅ Done."
echo "Root CA:"
echo "  $ROOT_CRT"
echo "Leaf (nginx) for $HOSTNAME:"
echo "  $LEAF_KEY"
echo "  $LEAF_CRT"
echo "  $FULLCHAIN"
echo "Traefik cert/key:"
echo "  $TRAEFIK_DIR/key.pem"
echo "  $TRAEFIK_DIR/cert.pem"
echo "Client CA bundle (install on laptop):"
echo "  $CLIENT_BUNDLE"
echo
echo "SANs:"
openssl x509 -in "$LEAF_CRT" -noout -text | awk '/Subject Alternative Name/{getline; print "  " $0}'
