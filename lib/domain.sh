# CommunityOS domain helpers — single source of truth: DOMAIN_BASE
# shellcheck shell=bash

# Default when unset (existing installs + local-first path)
COMMUNITYOS_DEFAULT_DOMAIN_BASE="community.home.arpa"

# Known service prefixes: hostname = "${prefix}.${DOMAIN_BASE}" except base itself
# Website uses DOMAIN_BASE as-is.

domain_normalize() {
  # lowercase, strip trailing dots and whitespace
  local d="${1:-}"
  d="$(printf '%s' "${d}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//;s/\.+$//')"
  printf '%s' "${d}"
}

# Validate a hostname / domain suitable for DNS + Caddy
# Returns 0 if valid.
domain_validate() {
  local d
  d="$(domain_normalize "${1:-}")"
  [[ -z "${d}" ]] && return 1
  # Reject spaces, path-ish, protocol, and pure IPs
  if printf '%s' "${d}" | grep -qE '[[:space:]/\\]|:|^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    return 1
  fi
  # Labels: alnum and hyphen, not starting/ending with hyphen; at least one dot preferred for custom
  # Allow single-label only for known specials (not expected); require 1–253 chars
  [[ ${#d} -gt 253 ]] && return 1
  if ! printf '%s' "${d}" | grep -qE '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'; then
    return 1
  fi
  # TLD label must not be all-numeric
  local tld="${d##*.}"
  if printf '%s' "${tld}" | grep -qE '^[0-9]+$'; then
    return 1
  fi
  return 0
}

domain_is_home_arpa() {
  local d
  d="$(domain_normalize "${1:-${DOMAIN_BASE:-$COMMUNITYOS_DEFAULT_DOMAIN_BASE}}")"
  [[ "${d}" == *.home.arpa ]] || [[ "${d}" == "home.arpa" ]]
}

# Load DOMAIN_* from .env if not already in environment
domain_load() {
  local envf="${COMMUNITYOS_ROOT:-/opt/communityos}/.env"
  if [[ -f "${envf}" ]]; then
    # shellcheck disable=SC1090
    set -a
    # Prefer existing shell values; only fill missing from file
    local line key val
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ "${line}" =~ ^[[:space:]]*# ]] && continue
      [[ "${line}" != *=* ]] && continue
      key="${line%%=*}"
      val="${line#*=}"
      key="$(printf '%s' "${key}" | tr -d '[:space:]')"
      val="${val%\"}"; val="${val#\"}"
      val="${val%\'}"; val="${val#\'}"
      case "${key}" in
        DOMAIN_BASE|DOMAIN_CHAT|DOMAIN_AI|DOMAIN_LIBRARY|DOMAIN_MAPS|DOMAIN_MEDIA|DOMAIN_FILES|DOMAIN_STREAM|DOMAIN_HERMES)
          if [[ -z "${!key:-}" ]]; then
            printf -v "${key}" '%s' "${val}"
            export "${key?}"
          fi
          ;;
      esac
    done < "${envf}"
    set +a
  fi
  DOMAIN_BASE="$(domain_normalize "${DOMAIN_BASE:-$COMMUNITYOS_DEFAULT_DOMAIN_BASE}")"
  export DOMAIN_BASE
  domain_derive
}

# Derive all service hostnames from DOMAIN_BASE
domain_derive() {
  DOMAIN_BASE="$(domain_normalize "${DOMAIN_BASE:-$COMMUNITYOS_DEFAULT_DOMAIN_BASE}")"
  DOMAIN_CHAT="${DOMAIN_CHAT:-chat.${DOMAIN_BASE}}"
  DOMAIN_AI="${DOMAIN_AI:-ai.${DOMAIN_BASE}}"
  DOMAIN_LIBRARY="${DOMAIN_LIBRARY:-library.${DOMAIN_BASE}}"
  DOMAIN_MAPS="${DOMAIN_MAPS:-maps.${DOMAIN_BASE}}"
  DOMAIN_MEDIA="${DOMAIN_MEDIA:-media.${DOMAIN_BASE}}"
  DOMAIN_FILES="${DOMAIN_FILES:-files.${DOMAIN_BASE}}"
  DOMAIN_STREAM="${DOMAIN_STREAM:-stream.${DOMAIN_BASE}}"
  DOMAIN_HERMES="${DOMAIN_HERMES:-hermes.${DOMAIN_BASE}}"
  # Always re-derive secondary names from base so a single DOMAIN_BASE change wins
  DOMAIN_CHAT="chat.${DOMAIN_BASE}"
  DOMAIN_AI="ai.${DOMAIN_BASE}"
  DOMAIN_LIBRARY="library.${DOMAIN_BASE}"
  DOMAIN_MAPS="maps.${DOMAIN_BASE}"
  DOMAIN_MEDIA="media.${DOMAIN_BASE}"
  DOMAIN_FILES="files.${DOMAIN_BASE}"
  DOMAIN_STREAM="stream.${DOMAIN_BASE}"
  DOMAIN_HERMES="hermes.${DOMAIN_BASE}"
  DOMAIN_SEARCH="search.${DOMAIN_BASE}"
  export DOMAIN_BASE DOMAIN_CHAT DOMAIN_AI
  export DOMAIN_LIBRARY DOMAIN_MAPS DOMAIN_MEDIA DOMAIN_FILES DOMAIN_STREAM DOMAIN_HERMES DOMAIN_SEARCH
}

# Hostname for a known service key
domain_for() {
  domain_load 2>/dev/null || domain_derive
  case "${1:-}" in
    base|website|site) printf '%s' "${DOMAIN_BASE}" ;;
    chat|matrix) printf '%s' "${DOMAIN_CHAT}" ;;
    ai|assistant|open-webui) printf '%s' "${DOMAIN_AI}" ;;
    library|kiwix) printf '%s' "${DOMAIN_LIBRARY}" ;;
    maps) printf '%s' "${DOMAIN_MAPS}" ;;
    media|jellyfin) printf '%s' "${DOMAIN_MEDIA}" ;;
    files|nextcloud) printf '%s' "${DOMAIN_FILES}" ;;
    stream|peertube) printf '%s' "${DOMAIN_STREAM}" ;;
    hermes|agent) printf '%s' "${DOMAIN_HERMES}" ;;
    search|searxng) printf '%s' "${DOMAIN_SEARCH}" ;;
    *) printf '%s.%s' "${1}" "${DOMAIN_BASE}" ;;
  esac
}

# Write DOMAIN_* lines into an .env file (replace or append)
domain_write_env() {
  local envf="${1:?}"
  domain_derive
  local keys=(DOMAIN_BASE DOMAIN_CHAT DOMAIN_AI DOMAIN_LIBRARY DOMAIN_MAPS DOMAIN_MEDIA DOMAIN_FILES DOMAIN_STREAM DOMAIN_HERMES DOMAIN_SEARCH)
  local k v
  touch "${envf}"
  for k in "${keys[@]}"; do
    v="${!k}"
    if grep -q "^${k}=" "${envf}" 2>/dev/null; then
      sed -i "s|^${k}=.*|${k}=${v}|" "${envf}"
    else
      echo "${k}=${v}" >> "${envf}"
    fi
  done
}

# Emit dnsmasq address= lines for all CommunityOS names
domain_dnsmasq_addresses() {
  local ip="${1:?}"
  domain_derive
  local h
  for h in "${DOMAIN_BASE}" "${DOMAIN_CHAT}" "${DOMAIN_AI}" \
           "${DOMAIN_LIBRARY}" "${DOMAIN_MAPS}" "${DOMAIN_MEDIA}" \
           "${DOMAIN_FILES}" "${DOMAIN_STREAM}" "${DOMAIN_HERMES}" "${DOMAIN_SEARCH}"; do
    echo "address=/${h}/${ip}"
  done
}


# Emit dnsmasq address= lines only for currently enabled core services / apps.
# Callers pass the list of hostnames (one per argument or via domain helpers).
domain_dnsmasq_hosts() {
  local ip="${1:?}"
  shift
  local h
  for h in "$@"; do
    [[ -n "${h}" ]] || continue
    echo "address=/${h}/${ip}"
  done
}
