#!/usr/bin/env bash
# Hardens the origin VM: patches, nginx, ufw (SSH from admin IP, HTTPS from
# Cloudflare only), unattended upgrades. Idempotent; run as root:
#   sudo bash harden.sh <ADMIN_IP>
set -euo pipefail

# Everything lives in main() so bash parses the whole script before running it;
# this keeps it safe when piped over ssh (child processes cannot eat the script).
main() {
  local admin_ip="${1:?usage: harden.sh <ADMIN_IP>}"

  if [[ $EUID -ne 0 ]]; then
    echo "must run as root" >&2
    exit 1
  fi
  if [[ ! $admin_ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    echo "invalid admin IPv4 address: $admin_ip" >&2
    exit 1
  fi

  # --- Packages ---
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y </dev/null
  apt-get upgrade -y -o Dpkg::Options::=--force-confold </dev/null
  apt-get install -y nginx ufw unattended-upgrades curl </dev/null

  # --- Cloudflare ranges (fetched before touching the firewall) ---
  local cf_v4 cf_v6
  cf_v4="$(curl -fsS https://www.cloudflare.com/ips-v4)"
  cf_v6="$(curl -fsS https://www.cloudflare.com/ips-v6)"
  if [[ -z $cf_v4 || -z $cf_v6 ]]; then
    echo "could not fetch Cloudflare IP ranges" >&2
    exit 1
  fi

  # --- Firewall: reset and re-add so reruns pick up the current ranges ---
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$admin_ip" to any port 22 proto tcp
  local range
  for range in $cf_v4 $cf_v6; do
    ufw allow from "$range" to any port 443 proto tcp
  done
  ufw --force enable

  # --- Unattended upgrades ---
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable --now unattended-upgrades

  # --- SSH: password logins must be disabled ---
  if ! sshd -T | grep -qix 'passwordauthentication no'; then
    echo "PasswordAuthentication is not disabled" >&2
    exit 1
  fi
  echo "sshd: passwordauthentication no"

  ufw status verbose
}

main "$@"
