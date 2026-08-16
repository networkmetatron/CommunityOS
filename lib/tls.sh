#!/usr/bin/env bash
# CommunityOS TLS helpers
#   TLS_MODE=local       → Caddy tls internal (CommunityOS local CA)
#   TLS_MODE=acme_dns01  → Let's Encrypt production via ACME DNS-01
#
# shellcheck source=/dev/null
: "${COMMUNITYOS_ROOT:=/opt/communityos}"

TLS_CADDY_IMAGE_LOCAL="${TLS_CADDY_IMAGE_LOCAL:-caddy:2.9.1-alpine}"
TLS_CADDY_IMAGE_ACME_DEFAULT="${TLS_CADDY_IMAGE_ACME_DEFAULT:-iarekylew00t/caddy-cloudflare:2.9.1}"
TLS_ACME_CA_LETSENCRYPT="${TLS_ACME_CA_LETSENCRYPT:-https://acme-v02.api.letsencrypt.org/directory}"
TLS_ACME_CA_LETSENCRYPT_STAGING="${TLS_ACME_CA_LETSENCRYPT_STAGING:-https://acme-staging-v02.api.letsencrypt.org/directory}"

tls_mode_get() {
  local m
  m="${TLS_MODE:-}"
  if [[ -z "${m}" && -f "${COMMUNITYOS_ROOT}/.env" ]]; then
    m="$(grep -E '^TLS_MODE=' "${COMMUNITYOS_ROOT}/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
  fi
  m="$(echo "${m:-local}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${m}" in
    acme|acme_dns|acme_dns01|letsencrypt|public|le) echo "acme_dns01" ;;
    *) echo "local" ;;
  esac
}

tls_mode_set() {
  local mode="$1"
  local envf="${COMMUNITYOS_ROOT}/.env"
  case "${mode}" in
    local) ;;
    acme|acme_dns|acme_dns01|letsencrypt|public|le) mode="acme_dns01" ;;
    *)
      echo "Usage: communityos tls set <local|acme_dns01>"
      return 1
      ;;
  esac
  [[ -f "${envf}" ]] || { echo "Not installed (.env missing)"; return 1; }
  if grep -q '^TLS_MODE=' "${envf}" 2>/dev/null; then
    sed -i "s|^TLS_MODE=.*|TLS_MODE=${mode}|" "${envf}"
  else
    echo "TLS_MODE=${mode}" >> "${envf}"
  fi
  export TLS_MODE="${mode}"
  if declare -F log_ok >/dev/null 2>&1; then
    log_ok "TLS_MODE=${mode}"
  else
    echo "TLS_MODE=${mode}"
  fi
}

tls_load_secrets() {
  local f="${COMMUNITYOS_ROOT}/secrets/acme.env"
  [[ -f "${f}" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  source "${f}" 2>/dev/null || true
  set +a
  return 0
}

tls_secrets_ok() {
  local mode
  mode="$(tls_mode_get)"
  [[ "${mode}" == "local" ]] && return 0
  local f="${COMMUNITYOS_ROOT}/secrets/acme.env"
  [[ -f "${f}" ]] || return 1
  tls_load_secrets || true
  [[ -n "${ACME_EMAIL:-${ADMIN_EMAIL:-}}" ]] || return 1
  [[ -n "${ACME_DNS_PROVIDER:-}" ]] || return 1
  case "${ACME_DNS_PROVIDER}" in
    cloudflare)
      [[ -n "${CLOUDFLARE_API_TOKEN:-${CF_API_TOKEN:-}}" ]] || return 1
      ;;
  esac
  return 0
}

tls_caddy_image_for_mode() {
  local mode
  mode="$(tls_mode_get)"
  if [[ "${mode}" == "local" ]]; then
    echo "${TLS_CADDY_IMAGE_LOCAL}"
    return
  fi
  tls_load_secrets 2>/dev/null || true
  if [[ -n "${CADDY_IMAGE:-}" ]]; then
    echo "${CADDY_IMAGE}"
    return
  fi
  case "${ACME_DNS_PROVIDER:-cloudflare}" in
    cloudflare) echo "${TLS_CADDY_IMAGE_ACME_DEFAULT}" ;;
    *) echo "${CADDY_IMAGE:-${TLS_CADDY_IMAGE_ACME_DEFAULT}}" ;;
  esac
}

tls_enabled_hosts() {
  local hosts=() base
  base="${DOMAIN_BASE:-community.home.arpa}"
  if [[ -d "${COMMUNITYOS_ROOT}/runtime/services" ]] \
     && compgen -G "${COMMUNITYOS_ROOT}/runtime/services/*.enabled" >/dev/null 2>&1; then
    [[ -f "${COMMUNITYOS_ROOT}/runtime/services/website.enabled" ]] && hosts+=("${base}")
    [[ -f "${COMMUNITYOS_ROOT}/runtime/services/chat.enabled" ]] && hosts+=("chat.${base}")
    [[ -f "${COMMUNITYOS_ROOT}/runtime/services/ai.enabled" ]] && hosts+=("ai.${base}")
  else
    hosts+=("${base}" "chat.${base}" "ai.${base}")
  fi
  [[ -f "${COMMUNITYOS_ROOT}/runtime/apps/kiwix.enabled" ]] && hosts+=("library.${base}")
  [[ -f "${COMMUNITYOS_ROOT}/runtime/apps/maps.enabled" ]] && hosts+=("maps.${base}")
  [[ -f "${COMMUNITYOS_ROOT}/runtime/apps/jellyfin.enabled" ]] && hosts+=("media.${base}")
  [[ -f "${COMMUNITYOS_ROOT}/runtime/apps/nextcloud.enabled" ]] && hosts+=("files.${base}")
  [[ -f "${COMMUNITYOS_ROOT}/runtime/apps/peertube.enabled" ]] && hosts+=("stream.${base}")
  [[ -f "${COMMUNITYOS_ROOT}/runtime/apps/hermes.enabled" ]] && hosts+=("hermes.${base}")
  [[ -f "${COMMUNITYOS_ROOT}/runtime/apps/search.enabled" ]] && hosts+=("search.${base}")
  if [[ "${#hosts[@]}" -eq 0 ]]; then
    hosts+=("${base}")
  fi
  printf '%s\n' "${hosts[@]}"
}

tls_sync_caddy_image_env() {
  local img envf
  img="$(tls_caddy_image_for_mode)"
  envf="${COMMUNITYOS_ROOT}/.env"
  [[ -f "${envf}" ]] || return 0
  if grep -q '^CADDY_IMAGE=' "${envf}" 2>/dev/null; then
    sed -i "s|^CADDY_IMAGE=.*|CADDY_IMAGE=${img}|" "${envf}"
  else
    echo "CADDY_IMAGE=${img}" >> "${envf}"
  fi
  export CADDY_IMAGE="${img}"
}

# Operator-facing Cloudflare requirements (never prints tokens)
tls_print_cloudflare_guide() {
  local base="${DOMAIN_BASE:-your-domain.example}"
  cat <<GUIDE

Public certificate — Let's Encrypt (ACME DNS-01)
------------------------------------------------
  DNS provider:  Cloudflare (must be authoritative for ${base})
  Validation:    DNS-01 (LAN-only OK; no public port 80/443 required)
  Client trust:  ordinary browsers — no CommunityOS ca.crt install

Cloudflare setup:
  1. Domain can stay registered at any registrar.
  2. Authoritative NS must be Cloudflare (e.g. *.ns.cloudflare.com).
  3. API token: Zone → DNS → Edit, restricted to the ${base} zone only.
  4. CommunityOS A/AAAA records may be DNS-only (grey cloud); proxy optional.

Secrets (root-only):
  /opt/communityos/secrets/acme.env
    chmod 600 && chown root:root

  ACME_EMAIL=you@example.com
  ACME_DNS_PROVIDER=cloudflare
  CLOUDFLARE_API_TOKEN=<token>
  ACME_WILDCARD=1

Then:
  sudo communityos tls set acme_dns01
  sudo communityos tls prewarm

GUIDE
}

tls_apply_caddyfile() {
  local mode template out email provider acme_ca wildcard
  mode="$(tls_mode_get)"
  template="${COMMUNITYOS_ROOT}/config/Caddyfile.local.template"
  [[ -f "${template}" ]] || template="${COMMUNITYOS_ROOT}/Caddyfile"
  out="${COMMUNITYOS_ROOT}/Caddyfile"
  [[ -f "${template}" ]] || return 1

  if [[ "${mode}" == "local" ]]; then
    cp -a "${template}" "${out}"
    tls_sync_caddy_image_env
    return 0
  fi

  tls_load_secrets 2>/dev/null || true
  email="${ACME_EMAIL:-${ADMIN_EMAIL:-admin@localhost}}"
  provider="${ACME_DNS_PROVIDER:-cloudflare}"
  acme_ca="${ACME_CA:-${TLS_ACME_CA_LETSENCRYPT}}"
  case "${ACME_STAGING:-0}" in 1|true|TRUE|yes|Y|y)
    acme_ca="${TLS_ACME_CA_LETSENCRYPT_STAGING}"
    ;;
  esac
  wildcard="${ACME_WILDCARD:-1}"

  local body tmp
  body="$(mktemp)"
  tmp="$(mktemp)"
  # Strip local_certs global, http:// ca.crt onboarding, and tls internal lines
  awk '
    BEGIN { mode="norm"; depth=0 }
    mode=="norm" && /^\{[[:space:]]*$/ {
      buf=$0 ORS; depth=1; mode="buf_global"; next
    }
    mode=="buf_global" {
      buf=buf $0 ORS
      if ($0 ~ /\{/) depth++
      if ($0 ~ /\}/) {
        depth--
        if (depth<=0) {
          if (buf !~ /local_certs/) printf "%s", buf
          mode="norm"
        }
      }
      next
    }
    mode=="norm" && /^http:\/\// { mode="skip_http"; depth=0; next }
    mode=="skip_http" {
      if ($0 ~ /\{/) depth++
      if ($0 ~ /\}/) {
        if (depth<=0) mode="norm"
        else depth--
      }
      next
    }
    mode=="norm" && /^[[:space:]]*tls internal/ { next }
    mode=="norm" { print }
  ' "${template}" > "${body}"

  {
    echo "{"
    echo "	email ${email}"
    echo "	# Let's Encrypt production unless ACME_STAGING=1."
    echo "	# Explicit public resolvers — Docker 127.0.0.11 often SERVFAILs zone discovery."
    echo "	cert_issuer acme {"
    echo "		dir ${acme_ca}"
    if [[ "${provider}" == "cloudflare" ]]; then
      echo "		dns cloudflare {env.CLOUDFLARE_API_TOKEN}"
    elif [[ -n "${provider}" ]]; then
      echo "		dns ${provider}"
    fi
    echo "		resolvers 1.1.1.1 1.0.0.1 8.8.8.8"
    echo "		propagation_timeout 5m"
    echo "	}"
    case "${wildcard}" in 1|true|TRUE|yes|Y|y)
      echo "	auto_https prefer_wildcard"
      ;;
    esac
    echo "}"
    echo
    cat "${body}"
  } > "${tmp}"
  mv "${tmp}" "${out}"
  rm -f "${body}"
  tls_sync_caddy_image_env
}

# Drop persisted staging ACME issuer state so production LE is authoritative
tls_clear_staging_issuer_state() {
  if docker exec communityos-caddy true >/dev/null 2>&1; then
    docker exec communityos-caddy sh -c '
      rm -rf /data/caddy/acme/acme-staging-v02.api.letsencrypt.org-directory \
             /data/caddy/acme/acme-staging-v02.api.letsencrypt.org \
             /config/caddy/autosave.json 2>/dev/null || true
    ' 2>/dev/null || true
  fi
  return 0
}

tls_prepare_caddy_runtime() {
  local mode secrets
  mode="$(tls_mode_get)"
  secrets="${COMMUNITYOS_ROOT}/secrets/acme.env"
  mkdir -p "${COMMUNITYOS_ROOT}/secrets"
  if [[ ! -f "${secrets}" ]]; then
    : > "${secrets}"
    chmod 600 "${secrets}" 2>/dev/null || true
  fi
  tls_sync_caddy_image_env
  tls_apply_caddyfile

  if [[ "${mode}" == "acme_dns01" ]]; then
    if [[ -f "${secrets}" ]]; then
      chmod 600 "${secrets}" 2>/dev/null || true
      chown root:root "${secrets}" 2>/dev/null || true
      tls_load_secrets || true
      if [[ -n "${CF_API_TOKEN:-}" && -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        if ! grep -q '^CLOUDFLARE_API_TOKEN=' "${secrets}" 2>/dev/null; then
          echo "CLOUDFLARE_API_TOKEN=${CF_API_TOKEN}" >> "${secrets}"
        fi
      fi
    fi
    case "${ACME_STAGING:-0}" in 1|true|TRUE|yes|Y|y) ;; *)
      tls_clear_staging_issuer_state || true
      ;;
    esac
  fi
}

# Pre-warm enabled hosts only. Public mode verifies Let's Encrypt issuer.
# Quiet during retries — only the final per-host and summary lines are printed.
# TLS_PREWARM_QUIET=1 suppresses all status lines (used by cmd_start).
tls_prewarm() {
  local host mode ok=0 pending=0 fail=0 issuer quiet="${TLS_PREWARM_QUIET:-0}"
  mode="$(tls_mode_get)"
  if ! docker exec communityos-caddy true >/dev/null 2>&1; then
    if [[ "${quiet}" != "1" ]] && declare -F log_warn >/dev/null 2>&1; then
      log_warn "Caddy is not running — cannot pre-warm certificates"
    fi
    return 1
  fi
  while IFS= read -r host; do
    [[ -z "${host}" ]] && continue
    if [[ "${mode}" == "local" ]]; then
      if curl -sk --connect-timeout 2 --max-time 10 "https://${host}/" -o /dev/null 2>/dev/null; then
        ok=$((ok + 1))
      else
        pending=$((pending + 1))
      fi
    else
      # DNS-01 can take 30–90s; poll quietly, report only the final state
      local i
      issuer=""
      for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        curl -sk --connect-timeout 3 --max-time 20 "https://${host}/" -o /dev/null 2>/dev/null || true
        issuer="$(echo | openssl s_client -connect "${host}:443" -servername "${host}" 2>/dev/null \
          | openssl x509 -noout -issuer 2>/dev/null || true)"
        if echo "${issuer}" | grep -qiE "Let's Encrypt|ISRG"; then
          break
        fi
        sleep 5
      done
      if echo "${issuer}" | grep -qiE "Let's Encrypt|ISRG"; then
        ok=$((ok + 1))
        if [[ "${quiet}" != "1" ]] && declare -F log_ok >/dev/null 2>&1; then
          log_ok "${host}: Let's Encrypt certificate active"
        fi
      else
        # Still local CA or empty = pending issuance, not a hard failure
        pending=$((pending + 1))
        if [[ "${quiet}" != "1" ]] && declare -F log_info >/dev/null 2>&1; then
          log_info "${host}: certificate still provisioning (not Let's Encrypt yet)"
          [[ -n "${issuer}" ]] && echo "         current issuer: ${issuer}"
        fi
      fi
    fi
  done < <(tls_enabled_hosts)
  if [[ "${mode}" != "local" && "${pending}" -gt 0 ]]; then
    if [[ "${quiet}" != "1" ]] && declare -F log_warn >/dev/null 2>&1; then
      log_warn "Pre-warm pending (${ok} active, ${pending} still provisioning). Re-run: sudo communityos tls prewarm"
      echo "  Logs: docker logs communityos-caddy --tail 80"
    fi
    return 1
  fi
  return 0
}

tls_cert_info() {
  local host="$1"
  echo | openssl s_client -connect "${host}:443" -servername "${host}" 2>/dev/null \
    | openssl x509 -noout -issuer -enddate 2>/dev/null || true
}

tls_status() {
  local mode img base info issuer enddate
  mode="$(tls_mode_get)"
  img="$(tls_caddy_image_for_mode)"
  tls_load_secrets 2>/dev/null || true
  echo "TLS mode: ${mode}"
  if [[ "${mode}" == "local" ]]; then
    echo "  Configured issuer: CommunityOS local CA (tls internal)"
    echo "  Client trust: install ca.crt from http://${DOMAIN_BASE:-community.home.arpa}/ca.crt"
    echo "  Caddy image: ${img}"
  else
    echo "  Configured issuer: Let's Encrypt (ACME DNS-01)"
    echo "  ACME directory: ${ACME_CA:-${TLS_ACME_CA_LETSENCRYPT}}"
    case "${ACME_STAGING:-0}" in 1|true|TRUE|yes|Y|y)
      echo "  WARNING: ACME_STAGING=1 — browsers will NOT trust issued certs"
      ;;
    esac
    echo "  DNS provider: ${ACME_DNS_PROVIDER:-cloudflare}"
    echo "  Caddy image: ${img}"
    if tls_secrets_ok; then
      echo "  Secrets: ${COMMUNITYOS_ROOT}/secrets/acme.env (present)"
      echo "  ACME email: ${ACME_EMAIL:-${ADMIN_EMAIL:-}}"
    else
      echo "  Secrets: MISSING or incomplete"
      echo "    File:  ${COMMUNITYOS_ROOT}/secrets/acme.env"
      echo "    Need:  ACME_EMAIL, ACME_DNS_PROVIDER=cloudflare, CLOUDFLARE_API_TOKEN"
      echo "    Perm:  chmod 600 && chown root:root"
    fi
  fi
  echo "  Hosts managed (enabled services / installed apps only):"
  tls_enabled_hosts | sed 's/^/    - /'
  base="${DOMAIN_BASE:-}"
  if [[ -n "${base}" ]] && docker exec communityos-caddy true >/dev/null 2>&1; then
    info="$(tls_cert_info "${base}" 2>/dev/null || true)"
    issuer="$(echo "${info}" | awk -F'issuer=' '/issuer=/ {print $2; exit}')"
    enddate="$(echo "${info}" | awk -F'notAfter=' '/notAfter=/ {print $2; exit}')"
    echo "  Live certificate for ${base}:"
    if [[ -n "${issuer}" ]]; then
      echo "    issuer: ${issuer}"
      echo "    notAfter: ${enddate:-unknown}"
      if echo "${issuer}" | grep -qiE "Let's Encrypt|ISRG"; then
        echo "    status: active (public Let's Encrypt)"
        echo "  Client trust: public CA — no CommunityOS ca.crt install"
      else
        echo "    status: not public yet (see issuer above)"
        if [[ "${mode}" == "acme_dns01" ]]; then
          echo "  Client trust: still local/pending — run: sudo communityos tls prewarm"
          echo "  Logs: docker logs communityos-caddy --tail 80"
        fi
      fi
    else
      echo "    status: pending or unavailable"
    fi
  fi
}
