#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export COMMUNITYOS_ROOT="${COMMUNITYOS_ROOT:-/opt/communityos}"

OFFLINE_BUNDLE=""
PASS_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --offline)
      shift
      OFFLINE_BUNDLE="${1:-}"
      if [[ -z "${OFFLINE_BUNDLE}" ]]; then
        echo "Usage: sudo ./install.sh --offline /path/to/offline-bundle"
        exit 1
      fi
      shift || true
      ;;
    --offline=*)
      OFFLINE_BUNDLE="${1#--offline=}"
      shift
      ;;
    *)
      PASS_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -n "${OFFLINE_BUNDLE}" ]]; then
  if [[ ! -d "${OFFLINE_BUNDLE}" ]]; then
    echo "[FAIL] Offline bundle path not found: ${OFFLINE_BUNDLE}"
    exit 1
  fi

  OFFLINE_BUNDLE="$(cd "${OFFLINE_BUNDLE}" && pwd)"

  if [[ ! -f "${OFFLINE_BUNDLE}/manifest.json" &&
        -f "${OFFLINE_BUNDLE}/../manifest.json" ]]; then
    OFFLINE_BUNDLE="$(cd "${OFFLINE_BUNDLE}/.." && pwd)"
  fi

  export COMMUNITYOS_OFFLINE=1
  export COMMUNITYOS_OFFLINE_BUNDLE="${OFFLINE_BUNDLE}"

  if [[ -d "${OFFLINE_BUNDLE}/communityos" ]]; then
    ROOT="${OFFLINE_BUNDLE}/communityos"
  fi

  echo "[INFO] Offline mode: ${OFFLINE_BUNDLE}"
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run:  sudo ./install.sh"
  exit 1
fi

# Bootstrap tools on minimal Debian (curl often missing)
need=()
command -v curl >/dev/null 2>&1 || need+=(curl)
command -v openssl >/dev/null 2>&1 || need+=(openssl)
dpkg -s ca-certificates >/dev/null 2>&1 || need+=(ca-certificates)
if [[ "${#need[@]}" -gt 0 ]]; then
  if [[ "${COMMUNITYOS_OFFLINE:-0}" == "1" ]]; then
    echo "Installing bootstrap tools from offline bundle: ${need[*]}"
    # shellcheck source=/dev/null
    source "${ROOT}/lib/offline.sh"
    offline_install_debs "${COMMUNITYOS_OFFLINE_BUNDLE}"
  else
    echo "Installing bootstrap tools: ${need[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need[@]}"
  fi
fi

# Copy package into /opt/communityos without requiring rsync
mkdir -p /opt/communityos/{lib,bin,scripts,static/welcome,runtime,backups,apps,data,config,docs}
if [[ "${ROOT}" != "/opt/communityos" ]]; then
  for item in compose.yaml Caddyfile config.json VERSION PRINCIPLES.md README.md CHANGELOG.md \
              bin lib scripts static apps data config docs; do
    if [[ -e "${ROOT}/${item}" ]]; then
      cp -a "${ROOT}/${item}" /opt/communityos/
    fi
  done
fi
install -m 755 /opt/communityos/bin/communityos /usr/local/bin/communityos
# Ensure install-engine from this package tree is used (not a stale /opt copy alone)
export COMMUNITYOS_PKG="${ROOT}"
export COMMUNITYOS_ROOT=/opt/communityos

if [[ "${COMMUNITYOS_OFFLINE:-0}" == "1" ]]; then
  export COMMUNITYOS_OFFLINE=1
  export COMMUNITYOS_OFFLINE_BUNDLE
fi

exec communityos install "${PASS_ARGS[@]}"
