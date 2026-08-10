#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${COMMUNITYOS_ROOT:-/opt/communityos}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run:  sudo communityos install"
  exit 1
fi

# Deploy package files into /opt/communityos
mkdir -p "${TARGET}"/{lib,bin,scripts,static/welcome,runtime,backups}
if [[ "${PKG_DIR}" != "${TARGET}" ]]; then
  for item in compose.yaml Caddyfile config.json VERSION PRINCIPLES.md README.md CHANGELOG.md \
              bin lib scripts static apps data; do
    if [[ -e "${PKG_DIR}/${item}" ]]; then
      cp -a "${PKG_DIR}/${item}" "${TARGET}/"
    fi
  done
fi
install -m 755 "${TARGET}/bin/communityos" /usr/local/bin/communityos

BASE_DIR="${TARGET}"
cd "${BASE_DIR}"

# ---------------------------------------------------------------------------
# Offline mode (air-gapped install from a local bundle)
# ---------------------------------------------------------------------------

COMMUNITYOS_OFFLINE="${COMMUNITYOS_OFFLINE:-0}"
COMMUNITYOS_OFFLINE_BUNDLE="${COMMUNITYOS_OFFLINE_BUNDLE:-}"

if [[ "${COMMUNITYOS_OFFLINE}" == "1" ]]; then
  # shellcheck source=/dev/null
  if [[ -f "${PKG_DIR}/lib/offline.sh" ]]; then
    source "${PKG_DIR}/lib/offline.sh"
  elif [[ -f "${TARGET}/lib/offline.sh" ]]; then
    source "${TARGET}/lib/offline.sh"
  else
    echo "[FAIL] Offline mode requested but lib/offline.sh is missing."
    exit 1
  fi

  if [[ -z "${COMMUNITYOS_OFFLINE_BUNDLE}" || ! -d "${COMMUNITYOS_OFFLINE_BUNDLE}" ]]; then
    echo "[FAIL] COMMUNITYOS_OFFLINE_BUNDLE is not set to a valid directory."
    echo "       Usage: sudo ./install.sh --offline /path/to/communityos-offline-vX.Y.Z"
    exit 1
  fi

  offline_verify_bundle "${COMMUNITYOS_OFFLINE_BUNDLE}"
fi

# Minimal tools needed before requirements / Docker (fresh Debian often lacks curl)
ensure_bootstrap_tools() {
  local need=()
  command -v curl >/dev/null 2>&1 || need+=(curl)
  command -v openssl >/dev/null 2>&1 || need+=(openssl)
  dpkg -s ca-certificates >/dev/null 2>&1 || need+=(ca-certificates)

  if [[ "${#need[@]}" -gt 0 ]]; then
    if [[ "${COMMUNITYOS_OFFLINE}" == "1" ]]; then
      echo "Installing bootstrap tools from offline bundle: ${need[*]}"
      offline_install_debs "${COMMUNITYOS_OFFLINE_BUNDLE}"
    else
      echo "Installing bootstrap tools: ${need[*]}"
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need[@]}"
    fi
  fi

  if [[ "${COMMUNITYOS_OFFLINE}" == "1" ]]; then
    # libnss3-tools should already be in the offline package set.
    true
  else
    # Certificate helper for local trust tooling (Caddy / browsers)
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libnss3-tools 2>/dev/null || true
  fi
}
ensure_bootstrap_tools

# ---------------------------------------------------------------------------
# System requirements
# ---------------------------------------------------------------------------
check_requirements() {
  local fail=0
  echo "Checking system requirements..."

  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "debian" ]]; then
      echo "[FAIL] Debian is required (found: ${ID:-unknown})."
      fail=1
    else
      ver="${VERSION_ID%%.*}"
      if [[ -n "${ver}" && "${ver}" -lt 12 ]]; then
        echo "[FAIL] Debian 12 or 13 required (found: ${VERSION_ID})."
        fail=1
      else
        echo "[ OK ] Debian ${VERSION_ID}"
      fi
    fi
  else
    echo "[FAIL] Cannot detect OS (/etc/os-release missing)."
    fail=1
  fi

  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64|aarch64|arm64)
      echo "[ OK ] CPU architecture: ${arch}"
      ;;
    *)
      echo "[FAIL] 64-bit CPU required (found: ${arch})."
      fail=1
      ;;
  esac

  if [[ -r /proc/meminfo ]]; then
    mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
    mem_gb=$((mem_kb / 1024 / 1024))
    if [[ "${mem_kb}" -lt $((3 * 1024 * 1024)) ]]; then
      echo "[FAIL] At least 4 GB RAM recommended (found: ~${mem_gb} GB)."
      fail=1
    else
      echo "[ OK ] Memory: ~${mem_gb} GB"
    fi
  fi

  avail_kb="$(df -Pk "${BASE_DIR}" | awk 'NR==2 {print $4}')"
  avail_gb=$((avail_kb / 1024 / 1024))
  if [[ "${avail_kb}" -lt $((15 * 1024 * 1024)) ]]; then
    echo "[FAIL] At least 15 GB free disk required (found: ~${avail_gb} GB)."
    fail=1
  else
    echo "[ OK ] Free disk: ~${avail_gb} GB"
  fi

  net_ok=0
  if command -v curl >/dev/null 2>&1; then
    for url in "https://deb.debian.org/" "https://cloudflare.com/" "http://detectportal.firefox.com/"; do
      if curl -4 -fsS --connect-timeout 5 --max-time 8 -o /dev/null "${url}" 2>/dev/null; then
        net_ok=1
        break
      fi
    done
  fi
  if [[ "${net_ok}" -eq 0 ]] && command -v ping >/dev/null 2>&1; then
    if ping -4 -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 || ping -4 -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
      net_ok=1
    fi
  fi
  if [[ "${net_ok}" -eq 1 ]]; then
    echo "[ OK ] Internet connectivity"
  else
    echo "[FAIL] No internet connectivity (needed to download platform components)."
    echo "       Check DNS, cable/Wi‑Fi, and that outbound HTTPS is allowed."
    fail=1
  fi

  if [[ "${fail}" -ne 0 ]]; then
    echo
    echo "Fix the issues above, then run install again."
    exit 1
  fi
  echo
}

check_requirements

echo
echo "==================================="
echo "  CommunityOS Installation"
echo "==================================="
echo

# --- prompts ---
while true; do
  read -rp "Community name [My Community]: " COMMUNITY_NAME
  COMMUNITY_NAME="${COMMUNITY_NAME:-My Community}"
  [[ -n "${COMMUNITY_NAME}" ]] && break
done

while true; do
  read -rp "Administrator username [admin]: " ADMIN_USER
  ADMIN_USER="${ADMIN_USER:-admin}"
  [[ -n "${ADMIN_USER}" ]] && break
done

while true; do
  read -srp "Administrator password: " ADMIN_PASS
  echo
  read -srp "Confirm password: " ADMIN_PASS2
  echo
  if [[ -z "${ADMIN_PASS}" ]]; then
    echo "Password cannot be empty."
    continue
  fi
  if [[ "${ADMIN_PASS}" != "${ADMIN_PASS2}" ]]; then
    echo "Passwords do not match."
    continue
  fi
  break
done

detect_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

# True if $1 looks like an IPv4 address (not a dig error line)
is_ipv4() {
  [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}


DEFAULT_IP="$(detect_ip)"
read -rp "Server LAN IP [${DEFAULT_IP}]: " SERVER_IP
SERVER_IP="${SERVER_IP:-$DEFAULT_IP}"
if [[ -z "${SERVER_IP}" ]]; then
  echo "Could not detect LAN IP. Enter it manually."
  exit 1
fi

echo
read -rp "Should this server provide DNS for your network? [Y/n]: " PROVIDE_DNS
PROVIDE_DNS="${PROVIDE_DNS:-Y}"
case "${PROVIDE_DNS}" in
  [Nn]*) PROVIDE_DNS=0 ;;
  *)     PROVIDE_DNS=1 ;;
esac

DOMAIN_BASE="community.home.arpa"
DOMAIN_CHAT="chat.community.home.arpa"
DOMAIN_AI="ai.community.home.arpa"
ADMIN_EMAIL="admin@${DOMAIN_BASE}"

# Reuse secrets from an existing install when present (avoids WP/DB password drift).
# Never let the old .env overwrite answers from this run (SERVER_IP, PROVIDE_DNS, admin, domains).
if [[ -f "${BASE_DIR}/.env" ]]; then
  _keep_server_ip="${SERVER_IP}"
  _keep_provide_dns="${PROVIDE_DNS}"
  _keep_community_name="${COMMUNITY_NAME}"
  _keep_admin_user="${ADMIN_USER}"
  _keep_admin_pass="${ADMIN_PASS}"
  _keep_domain_base="${DOMAIN_BASE}"
  _keep_domain_chat="${DOMAIN_CHAT}"
  _keep_domain_ai="${DOMAIN_AI}"
  set -a
  # shellcheck disable=SC1090
  source "${BASE_DIR}/.env" 2>/dev/null || true
  set +a
  SERVER_IP="${_keep_server_ip}"
  PROVIDE_DNS="${_keep_provide_dns}"
  COMMUNITY_NAME="${_keep_community_name}"
  ADMIN_USER="${_keep_admin_user}"
  ADMIN_PASS="${_keep_admin_pass}"
  DOMAIN_BASE="${_keep_domain_base}"
  DOMAIN_CHAT="${_keep_domain_chat}"
  DOMAIN_AI="${_keep_domain_ai}"
  unset _keep_server_ip _keep_provide_dns _keep_community_name _keep_admin_user _keep_admin_pass
  unset _keep_domain_base _keep_domain_chat _keep_domain_ai
fi
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-$(python3 -c 'import base64,os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())' 2>/dev/null || openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(openssl rand -hex 12)}"
WORDPRESS_DB_PASSWORD="${WORDPRESS_DB_PASSWORD:-$(openssl rand -hex 12)}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 12)}"
SYNAPSE_REGISTRATION_SHARED_SECRET="${SYNAPSE_REGISTRATION_SHARED_SECRET:-$(openssl rand -hex 24)}"
WORDPRESS_DB_NAME="${WORDPRESS_DB_NAME:-wordpress}"
WORDPRESS_DB_USER="${WORDPRESS_DB_USER:-wp_user}"
POSTGRES_USER="${POSTGRES_USER:-synapse}"
POSTGRES_DB="${POSTGRES_DB:-synapse}"



# Finalize host DNS after install:
#  - PROVIDE_DNS=Y and dnsmasq healthy → nameserver 127.0.0.1 (resolve *.home.arpa)
#  - PROVIDE_DNS=n → restore pre-install resolver (or conventional public DNS)

# Warn if /etc/hosts hard-codes CommunityOS names (overrides DNS — common while testing)
warn_stale_hosts_overrides() {
  local hits
  if [[ ! -f /etc/hosts ]]; then
    return 0
  fi
  hits="$(grep -E '[[:space:]](community\.home\.arpa|chat\.community\.home\.arpa|ai\.community\.home\.arpa|library\.community\.home\.arpa|maps\.community\.home\.arpa|media\.community\.home\.arpa|files\.community\.home\.arpa|stream\.community\.home\.arpa)([[:space:]]|$)' /etc/hosts 2>/dev/null || true)"
  if [[ -z "${hits}" ]]; then
    return 0
  fi
  echo
  echo "Checking for stale CommunityOS host overrides..."
  echo
  echo "[WARN] Found CommunityOS names in /etc/hosts."
  echo "       These override CommunityOS DNS and can cause confusion while testing."
  echo
  echo "Offending lines:"
  echo "${hits}" | sed 's/^/  /'
  echo
  echo "Remove them with:"
  echo "  sudo nano /etc/hosts"
  echo "or:"
  echo "  sudo sed -i -E '/[[:space:]](community|chat\\.community|ai\\.community|library\\.community|maps\\.community|media\\.community|files\\.community|stream\\.community)\\.home\\.arpa([[:space:]]|$)/d' /etc/hosts"
  echo
}

restore_host_resolver() {
  local IFACE ans
  IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"

  if [[ "${PROVIDE_DNS}" -eq 1 ]]; then
    if ! docker exec communityos-dns true >/dev/null 2>&1; then
      echo "[WARN] Local DNS container not running; not switching host to 127.0.0.1."
      echo "       Leaving temporary public DNS so the host can still reach the internet."
      return 0
    fi
    # Functional check: dnsmasq must actually answer community.home.arpa
    ans=""
    if command -v dig >/dev/null 2>&1; then
      ans="$(dig +time=2 +tries=1 +short @127.0.0.1 community.home.arpa A 2>/dev/null | head -1 || true)"
    fi
    if [[ -z "${ans}" ]]; then
      ans="$(getent hosts community.home.arpa 2>/dev/null | awk '{print $1; exit}' || true)"
    fi
    # dig @127.0.0.1 may fail if host still uses public DNS; query the published LAN port via dig @SERVER_IP
    if [[ -z "${ans}" ]] && command -v dig >/dev/null 2>&1 && [[ -n "${SERVER_IP:-}" ]]; then
      ans="$(dig +time=2 +tries=1 +short @"${SERVER_IP}" community.home.arpa A 2>/dev/null | head -1 || true)"
    fi
    if [[ -z "${ans}" ]]; then
      # Last resort: docker exec dig/nslookup not available; use dockerized query via getent from a temp container is heavy —
      # try connecting to UDP 53 and parsing dnsmasq via host command
      if command -v host >/dev/null 2>&1 && [[ -n "${SERVER_IP:-}" ]]; then
        ans="$(host -W 2 community.home.arpa "${SERVER_IP}" 2>/dev/null | awk '/has address/{print $4; exit}' || true)"
      fi
    fi
    if [[ -z "${ans}" ]]; then
      echo "[WARN] CommunityOS DNS is running but did not answer community.home.arpa yet."
      echo "       Not rewriting host resolver to 127.0.0.1 (avoids breaking outbound DNS)."
      return 0
    fi

    echo "Pointing host DNS at CommunityOS (127.0.0.1)..."
    if command -v resolvectl >/dev/null 2>&1 && [[ -n "${IFACE}" ]]; then
      resolvectl dns "${IFACE}" 127.0.0.1 2>/dev/null || true
      resolvectl domain "${IFACE}" home.arpa "~home.arpa" 2>/dev/null || true
    fi
    if [[ -L /etc/resolv.conf ]]; then
      rm -f /etc/resolv.conf
    fi
    printf '%s\n' \
      "# CommunityOS: local DNS (dnsmasq) for *.home.arpa + upstream" \
      "nameserver 127.0.0.1" \
      > /etc/resolv.conf

    if getent hosts community.home.arpa >/dev/null 2>&1; then
      echo "[ OK ] Host resolver configured to use CommunityOS DNS (127.0.0.1)"
      echo "       community.home.arpa → $(getent hosts community.home.arpa | awk '{print $1; exit}')"
    else
      echo "[WARN] Wrote nameserver 127.0.0.1 but host still cannot resolve community.home.arpa"
    fi
    return 0
  fi

  # DNS provider mode was declined — restore conventional resolver
  echo "Restoring host DNS (CommunityOS is not the network DNS server)..."
  if [[ -f /etc/resolv.conf.communityos.bak ]]; then
    if [[ -L /etc/resolv.conf ]]; then
      rm -f /etc/resolv.conf
    fi
    cp -a /etc/resolv.conf.communityos.bak /etc/resolv.conf 2>/dev/null || true
    if command -v resolvectl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
      ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true
      if [[ -n "${IFACE}" ]]; then
        resolvectl revert "${IFACE}" 2>/dev/null || \
          resolvectl dns "${IFACE}" 1.1.1.1 8.8.8.8 2>/dev/null || true
      fi
    fi
    echo "[ OK ] Host resolver restored to original configuration"
  else
    if [[ ! -L /etc/resolv.conf ]]; then
      printf '%s\n' \
        "# CommunityOS: conventional public DNS (DNS provider mode was not enabled)" \
        "nameserver 1.1.1.1" \
        "nameserver 8.8.8.8" \
        > /etc/resolv.conf
    fi
    if command -v resolvectl >/dev/null 2>&1 && [[ -n "${IFACE}" ]]; then
      resolvectl revert "${IFACE}" 2>/dev/null || \
        resolvectl dns "${IFACE}" 1.1.1.1 8.8.8.8 2>/dev/null || true
    fi
    echo "[ OK ] Host resolver restored to conventional public DNS"
  fi
}

ensure_ipv4_dns() {
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
  if [[ -f /etc/gai.conf ]] && ! grep -q "precedence :ffff:0:0/96" /etc/gai.conf 2>/dev/null; then
    echo "precedence :ffff:0:0/96  100" >> /etc/gai.conf
  fi
  # Preserve original resolver once so we can restore when DNS mode is n
  if [[ ! -f /etc/resolv.conf.communityos.bak ]]; then
    cp -a /etc/resolv.conf /etc/resolv.conf.communityos.bak 2>/dev/null || true
  fi
  IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
  if command -v resolvectl >/dev/null 2>&1 && [[ -n "${IFACE}" ]]; then
    resolvectl dns "${IFACE}" 1.1.1.1 8.8.8.8 2>/dev/null || true
  fi
  if [[ ! -L /etc/resolv.conf ]]; then
    printf '%s\n' "# CommunityOS: IPv4 DNS" "nameserver 1.1.1.1" "nameserver 8.8.8.8" > /etc/resolv.conf
  elif command -v resolvectl >/dev/null 2>&1; then
    true
  else
    # break symlink only if resolution is broken
    if ! getent hosts deb.debian.org >/dev/null 2>&1; then
      rm -f /etc/resolv.conf
      printf '%s\n' "# CommunityOS: IPv4 DNS" "nameserver 1.1.1.1" "nameserver 8.8.8.8" > /etc/resolv.conf
    fi
  fi
}


echo
echo "Preparing CommunityOS..."
echo
ensure_ipv4_dns

# Docker if missing

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing required system components..."

  if [[ "${COMMUNITYOS_OFFLINE}" == "1" ]]; then
    offline_install_debs "${COMMUNITYOS_OFFLINE_BUNDLE}"
    systemctl enable --now docker 2>/dev/null || true

    if ! command -v docker >/dev/null 2>&1; then
      echo "[FAIL] Docker was not installed from the offline bundle packages."
      echo "       Rebuild the bundle on a matching Debian ${VERSION_ID:-13} host."
      exit 1
    fi
  else
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl libnss3-tools

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg       -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc"       > /etc/apt/sources.list.d/docker.sources

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
  fi
fi

# Offline: load Docker images from the bundle (never docker pull)

if [[ "${COMMUNITYOS_OFFLINE}" == "1" ]]; then
  offline_load_images "${COMMUNITYOS_OFFLINE_BUNDLE}"

  # Assert core images from compose.yaml are present
  mapfile -t _core_imgs < <(offline_core_images "${BASE_DIR}")
  offline_assert_images_present "${_core_imgs[@]}"
fi

# Prefer IPv4 for outbound connections (broken IPv6 is common on home LANs)
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
# Prefer IPv4 addresses when both A and AAAA exist
if [[ -f /etc/gai.conf ]] && ! grep -q 'precedence :ffff:0:0/96' /etc/gai.conf 2>/dev/null; then
  echo "precedence :ffff:0:0/96  100" >> /etc/gai.conf
fi
# Force IPv4 DNS resolvers so apt/Docker are not stuck on dead IPv6 DNS
echo "Configuring IPv4 DNS for reliable downloads..."
IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
if command -v resolvectl >/dev/null 2>&1 && [[ -n "${IFACE}" ]]; then
  resolvectl dns "${IFACE}" 1.1.1.1 8.8.8.8 2>/dev/null || true
  resolvectl domain "${IFACE}" "~." 2>/dev/null || true
fi
# Always ensure /etc/resolv.conf has working IPv4 nameservers
cp -a /etc/resolv.conf /etc/resolv.conf.communityos.bak 2>/dev/null || true
if [[ -L /etc/resolv.conf ]]; then
  # systemd-resolved stub — also write fallback file used when stub fails
  true
else
  printf '%s\n'     "# CommunityOS: IPv4 DNS"     "nameserver 1.1.1.1"     "nameserver 8.8.8.8" > /etc/resolv.conf
fi
# Verify resolution before pulling images
if ! getent hosts deb.debian.org >/dev/null 2>&1 && ! ping -4 -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
  echo "[WARN] DNS still looks unreliable; image downloads may fail."
fi
systemctl restart docker >/dev/null 2>&1 || true
sleep 2

# Write .env
# Quote values so "My Community" etc. are safe to source
_q() { printf '%s' "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/"; }
cat > "${BASE_DIR}/.env" <<ENV
COMMUNITY_NAME=$(_q "${COMMUNITY_NAME}")
DOMAIN_BASE=$(_q "${DOMAIN_BASE}")
DOMAIN_CHAT=$(_q "${DOMAIN_CHAT}")
DOMAIN_AI=$(_q "${DOMAIN_AI}")
ADMIN_USER=$(_q "${ADMIN_USER}")
ADMIN_PASS=$(_q "${ADMIN_PASS}")
ADMIN_EMAIL=$(_q "${ADMIN_EMAIL}")
SERVER_IP=$(_q "${SERVER_IP}")
PROVIDE_DNS=${PROVIDE_DNS}
MYSQL_ROOT_PASSWORD=$(_q "${MYSQL_ROOT_PASSWORD}")
WORDPRESS_DB_NAME=$(_q "${WORDPRESS_DB_NAME:-wordpress}")
WORDPRESS_DB_USER=$(_q "${WORDPRESS_DB_USER:-wp_user}")
WORDPRESS_DB_PASSWORD=$(_q "${WORDPRESS_DB_PASSWORD}")
POSTGRES_USER=$(_q "${POSTGRES_USER:-synapse}")
POSTGRES_PASSWORD=$(_q "${POSTGRES_PASSWORD}")
POSTGRES_DB=$(_q "${POSTGRES_DB:-synapse}")
SYNAPSE_SERVER_NAME=$(_q "${DOMAIN_CHAT}")
SYNAPSE_REPORT_STATS=no
SYNAPSE_REGISTRATION_SHARED_SECRET=$(_q "${SYNAPSE_REGISTRATION_SHARED_SECRET}")
MATRIX_FEDERATION_MODE=off
MATRIX_FEDERATION_ENABLED=false
WEBUI_SECRET_KEY=$(_q "${WEBUI_SECRET_KEY}")
ENV
unset -f _q
chmod 640 "${BASE_DIR}/.env"
# Allow the installing user to use the CLI without sudo after re-login
if getent group docker >/dev/null 2>&1; then
  chgrp docker "${BASE_DIR}/.env" 2>/dev/null || true
fi

# Element config
cat > "${BASE_DIR}/config.json" <<JSON
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "https://${DOMAIN_CHAT}",
      "server_name": "${DOMAIN_CHAT}"
    }
  },
  "brand": "${COMMUNITY_NAME}",
  "default_theme": "light",
  "disable_custom_urls": true,
  "disable_guests": true
}
JSON

# DNS
mkdir -p "${BASE_DIR}/runtime"
cat > "${BASE_DIR}/runtime/dnsmasq.conf" <<DNS
# CommunityOS LAN DNS
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8
address=/community.home.arpa/${SERVER_IP}
address=/library.community.home.arpa/${SERVER_IP}
address=/maps.community.home.arpa/${SERVER_IP}
address=/media.community.home.arpa/${SERVER_IP}
address=/files.community.home.arpa/${SERVER_IP}
address=/stream.community.home.arpa/${SERVER_IP}
address=/hermes.community.home.arpa/${SERVER_IP}
DNS

echo "Starting CommunityOS (this may take several minutes)..."

if [[ "${COMMUNITYOS_OFFLINE}" == "1" ]]; then
  COMPOSE_PULL_FLAG=(--pull never)
else
  COMPOSE_PULL_FLAG=()
fi

if [[ "${PROVIDE_DNS}" -eq 1 ]]; then
  docker compose -f "${BASE_DIR}/compose.yaml" --env-file "${BASE_DIR}/.env" up -d "${COMPOSE_PULL_FLAG[@]}"
else
  docker compose -f "${BASE_DIR}/compose.yaml" --env-file "${BASE_DIR}/.env" up -d --scale dns=0 "${COMPOSE_PULL_FLAG[@]}"
fi

# Wait for Caddy CA
echo "Finishing setup..."
for i in $(seq 1 36); do
  if docker exec communityos-caddy test -f /data/caddy/pki/authorities/local/root.crt 2>/dev/null; then
    break
  fi
  sleep 5
done

INVOKER="${SUDO_USER:-}"
if [[ -n "${INVOKER}" ]] && id "${INVOKER}" >/dev/null 2>&1; then
  usermod -aG docker "${INVOKER}" 2>/dev/null || true
  echo
  echo "Note: log out and back in (or reboot) so ${INVOKER} can use Docker without sudo."
fi
# Ensure .env group is docker after docker is installed
if getent group docker >/dev/null 2>&1; then
  chgrp docker "${BASE_DIR}/.env" 2>/dev/null || true
  chmod 640 "${BASE_DIR}/.env" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Post-install health check
# ---------------------------------------------------------------------------
echo "Verifying services..."
# WordPress and Matrix can take a bit longer on first boot
for _ in $(seq 1 18); do
  if docker exec communityos-caddy wget -q -O /dev/null http://wordpress:80/ >/dev/null 2>&1 \
     && docker exec communityos-caddy wget -q -O /dev/null http://synapse:8008/health >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; HEALTH_FAIL=1; }
HEALTH_FAIL=0

if docker exec communityos-dns true >/dev/null 2>&1; then pass "DNS"
elif [[ "${PROVIDE_DNS}" -eq 0 ]]; then pass "DNS (disabled by choice)"
else fail "DNS"; fi

if docker exec communityos-wordpress bash -c 'exec 3<>/dev/tcp/127.0.0.1/80' >/dev/null 2>&1 \
   || curl -fsS --connect-timeout 3 -H "Host: community.home.arpa" http://127.0.0.1/ >/dev/null 2>&1; then
  pass "Website"
else
  fail "Website"
fi

if docker exec communityos-synapse curl -fsS --connect-timeout 3 http://127.0.0.1:8008/health >/dev/null 2>&1; then
  pass "Chat"
else
  fail "Chat"
fi

if docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' communityos-open-webui 2>/dev/null | grep -qiE 'healthy|running'; then
  pass "Assistant"
else
  fail "Assistant"
fi

if docker exec communityos-caddy true >/dev/null 2>&1; then
  pass "Gateway"
else
  fail "Gateway"
fi

echo
if [[ "${HEALTH_FAIL}" -eq 0 ]]; then
  echo "All core services are up."
else
  echo "Some services are still starting. Wait a minute, then open the welcome page."
fi
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "CommunityOS is installed!"
echo
echo "CommunityOS LAN"
echo
echo "  ${SERVER_IP}"
echo
echo "Use this address as your router's DNS server (if DNS was enabled)."
echo
echo "Next steps"
echo
if [[ "${PROVIDE_DNS}" -eq 1 ]]; then
  echo "1. Configure your router's DHCP DNS server:"
  echo
  echo "      ${SERVER_IP}"
  echo
  echo "2. Reconnect your devices so they pick up the new DNS."
  echo
  echo "   If community.home.arpa does not resolve:"
  echo
  echo "      • Disconnect and reconnect Wi-Fi"
  echo "      • OR unplug/reconnect the Ethernet cable"
  echo "      • OR renew the DHCP lease"
  echo
  echo "   The device may still be using its previous DNS configuration."
  echo
  echo "3. Visit:"
  _step_cert=4
  _step_https=5
else
  echo "1. Make names resolve to this server (${SERVER_IP})."
  echo "   DNS was not enabled on this host. Choose one:"
  echo
  echo "      • Add to each client /etc/hosts (or equivalent):"
  echo
  echo "          ${SERVER_IP}  community.home.arpa"
  echo "          ${SERVER_IP}  chat.community.home.arpa"
  echo "          ${SERVER_IP}  ai.community.home.arpa"
  echo
  echo "      • Or create the same records in Pi-hole / AdGuard / router DNS."
  echo
  echo "2. Visit:"
  _step_cert=3
  _step_https=4
fi
echo
echo "      http://community.home.arpa"
echo
echo "${_step_cert}. Install the CommunityOS certificate (one CA for all services)."
echo "   Download it from the welcome page, or:"
echo "      http://community.home.arpa/ca.crt"
echo
echo "${_step_https}. Then use HTTPS (same certificate covers every CommunityOS name):"
echo
echo "      https://community.home.arpa"
echo "      https://chat.community.home.arpa"
echo "      https://ai.community.home.arpa"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# DNS verification
echo "DNS Verification"
echo "----------------"
if [[ "${PROVIDE_DNS}" -eq 0 ]]; then
  echo "  · CommunityOS DNS was not enabled (your choice)."
  echo "  · Resolve names via /etc/hosts, Pi-hole, or your router."
  echo "  · Target IP: ${SERVER_IP}"
else
  dns_verify_ok=0
  if docker exec communityos-dns true >/dev/null 2>&1; then
    if ! command -v dig >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dnsutils 2>/dev/null || true
    fi
    if command -v dig >/dev/null 2>&1; then
      ans="$(dig +time=2 +tries=1 +short @"${SERVER_IP}" community.home.arpa A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
      if is_ipv4 "${ans}"; then
        echo "  ✓ community.home.arpa → ${ans}"
        for name in chat.community.home.arpa ai.community.home.arpa; do
          a2="$(dig +time=2 +tries=1 +short @"${SERVER_IP}" "${name}" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
          if is_ipv4 "${a2}"; then
            echo "  ✓ ${name} → ${a2}"
          else
            echo "  ✗ ${name} (no valid A record)"
          fi
        done
        dns_verify_ok=1
      else
        echo "  ✗ community.home.arpa did not resolve via ${SERVER_IP}"
        if [[ -n "${ans}" ]]; then
          echo "      dig returned: ${ans}"
        fi
      fi
    else
      echo "  · dnsmasq is running (install dnsutils for a local dig check)"
      dns_verify_ok=1
    fi
  else
    echo "  ✗ DNS service is not running"
  fi
  echo
  if [[ "${dns_verify_ok}" -eq 1 ]]; then
    echo "Server-side DNS looks good."
    echo
    echo "If another device cannot resolve community.home.arpa:"
    echo "  • Disconnect and reconnect Wi-Fi"
    echo "  • OR unplug/reconnect Ethernet"
    echo "  • OR renew the DHCP lease"
    echo
    echo "  The client may still be using its previous DNS server."
    echo "  Verify your router advertises DNS ${SERVER_IP}."
  else
    echo "Server-side DNS needs attention before clients will resolve names."
    echo
    echo "If this test fails on another device:"
    echo "  • Disconnect and reconnect Wi-Fi or Ethernet."
    echo "  • Renew the DHCP lease."
    echo "  • Verify your router advertises DNS ${SERVER_IP}."
  fi
  echo
  echo "From another device run:"
  echo
  echo "  dig community.home.arpa"
  echo
  echo "Expected answer:"
  echo
  echo "  ${SERVER_IP}"
fi
echo
# Finalize host DNS for this install mode (local vs conventional)
restore_host_resolver
warn_stale_hosts_overrides
echo

# Persist offline mode so later app installs still avoid network pulls

if [[ "${COMMUNITYOS_OFFLINE}" == "1" ]]; then
  mkdir -p "${BASE_DIR}/runtime"
  cat > "${BASE_DIR}/runtime/offline.env" <<OFF
# Generated by CommunityOS offline installer — do not edit unless you know why
COMMUNITYOS_OFFLINE=1
COMMUNITYOS_OFFLINE_BUNDLE=${COMMUNITYOS_OFFLINE_BUNDLE}
OFF
  echo "[ OK ] Offline mode recorded in runtime/offline.env"
fi

echo "Administrator: ${ADMIN_USER}"
echo
