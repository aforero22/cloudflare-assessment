#!/usr/bin/env bash
# Idempotent provisioning of the cf-assessment origin VM (Ubuntu 24.04).
#
# Usage (run on the VM from the repo root, as a sudo-capable user):
#   sudo ./infra/origin/provision.sh [--admin-ip <your.ip/32>] [--tunnel-token-file <path>]
#
# Prerequisites copied to the VM beforehand (never committed to git):
#   /etc/ssl/cf-assessment/fullchain.pem  Let's Encrypt chain (origin + tunnel SAN)
#   /etc/ssl/cf-assessment/privkey.pem    its private key (mode 600)
#   /etc/ssl/cf-assessment/aop-ca.pem     private CA that signed the AOP client cert
#
# The tunnel token is read from a file (or $CF_TUNNEL_TOKEN) so it is not typed on the
# command line or kept in shell history. Note: `cloudflared service install <token>` receives it
# as an argument, so it is briefly visible in the process list while that command runs; run this
# on a single-admin VM (as here) or pass the token via a root-only file. Get it with:
#   GET /accounts/{account_id}/cfd_tunnel/{tunnel_id}/token
#
# What it does:
#   1. Installs nginx + ufw, deploys the echo-headers app as a systemd service
#      (127.0.0.1:8080) and the nginx site (443 public with mTLS, 8443 loopback).
#   2. Firewall: 443 only from Cloudflare IP ranges (fetched live from
#      https://www.cloudflare.com/ips-v4 and ips-v6), SSH only from the admin IP.
#      (The Azure NSG enforces the same at the network edge.)
#   3. Installs cloudflared from Cloudflare's official apt repo and, if a token
#      is provided, registers it as a systemd service (remotely-managed tunnel).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ADMIN_IP=""
TOKEN_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-ip) ADMIN_IP="$2"; shift 2 ;;
    --tunnel-token-file) TOKEN_FILE="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx ufw curl python3 >/dev/null

echo "== app"
install -d -m 755 /opt/headers-app
install -m 644 "$REPO_ROOT/origin/app/headers_app.py" /opt/headers-app/headers_app.py
install -m 644 "$REPO_ROOT/origin/systemd/headers-app.service" /etc/systemd/system/headers-app.service
systemctl daemon-reload
systemctl enable --now headers-app.service
systemctl restart headers-app.service

echo "== TLS material check"
for f in fullchain.pem privkey.pem aop-ca.pem; do
  [[ -s /etc/ssl/cf-assessment/$f ]] || { echo "missing /etc/ssl/cf-assessment/$f" >&2; exit 1; }
done
chown root:root /etc/ssl/cf-assessment/*
chmod 700 /etc/ssl/cf-assessment
chmod 600 /etc/ssl/cf-assessment/privkey.pem
chmod 644 /etc/ssl/cf-assessment/fullchain.pem /etc/ssl/cf-assessment/aop-ca.pem

echo "== nginx"
install -m 644 "$REPO_ROOT/origin/nginx/cf-assessment.conf" /etc/nginx/sites-available/cf-assessment
ln -sf /etc/nginx/sites-available/cf-assessment /etc/nginx/sites-enabled/cf-assessment
rm -f /etc/nginx/sites-enabled/default   # no plain-HTTP default site on :80
sed -i 's/^\s*#\?\s*server_tokens .*/\tserver_tokens off;/' /etc/nginx/nginx.conf
nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx

echo "== firewall (ufw)"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
if [[ -n "$ADMIN_IP" ]]; then ufw allow from "$ADMIN_IP" to any port 22 proto tcp comment 'admin ssh' >/dev/null; fi
for net in $(curl -fsS https://www.cloudflare.com/ips-v4) $(curl -fsS https://www.cloudflare.com/ips-v6); do
  ufw allow from "$net" to any port 443 proto tcp comment 'cloudflare' >/dev/null
done
ufw --force enable >/dev/null
ufw status | head -5

echo "== cloudflared (official apt repo)"
if ! command -v cloudflared >/dev/null; then
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
    > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -qq && apt-get install -y -qq cloudflared >/dev/null
fi
cloudflared --version

TOKEN="${CF_TUNNEL_TOKEN:-}"
[[ -n "$TOKEN_FILE" ]] && TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
if [[ -n "$TOKEN" ]]; then
  if systemctl list-unit-files cloudflared.service >/dev/null 2>&1 && systemctl is-enabled cloudflared >/dev/null 2>&1; then
    echo "cloudflared service already installed; skipping (cloudflared service uninstall to reset)"
  else
    cloudflared service install "$TOKEN" >/dev/null
  fi
  systemctl enable --now cloudflared
  systemctl --no-pager status cloudflared | head -5
else
  echo "no tunnel token given: cloudflared installed but not registered"
fi
echo "== done"
