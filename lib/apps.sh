#!/usr/bin/env bash
# shellcheck source=/dev/null
: "${COMMUNITYOS_ROOT:=/opt/communityos}"
[[ -f "${COMMUNITYOS_ROOT}/lib/domain.sh" ]] && source "${COMMUNITYOS_ROOT}/lib/domain.sh"
# Optional app helpers — metadata from apps/*.manifest.yaml / registry.json

APPS_DIR="${COMMUNITYOS_ROOT}/apps"
APPS_STATE="${COMMUNITYOS_ROOT}/runtime/apps"
REGISTRY="${APPS_DIR}/registry.json"

app_list_ids() {
  if [[ -f "${REGISTRY}" ]] && command -v python3 >/dev/null 2>&1; then
    python3 -c "import json; print('\\n'.join(json.load(open('${REGISTRY}'))))" 2>/dev/null && return
  fi
  printf '%s\n' kiwix maps jellyfin nextcloud peertube
}

app_is_enabled() {
  local id="$1"
  [[ -f "${APPS_STATE}/${id}.enabled" ]]
}

app_enable() {
  local id="$1"
  mkdir -p "${APPS_STATE}"
  touch "${APPS_STATE}/${id}.enabled"
}

app_disable_flag() {
  local id="$1"
  rm -f "${APPS_STATE}/${id}.enabled"
}

# Print a field from the registry for an app id: name|description|url|domain|container|data|compose
app_meta() {
  local id="$1" field="$2"
  # Domain/URL always follow DOMAIN_BASE (registry defaults are documentation-only)
  if [[ "${field}" == "domain" || "${field}" == "url" ]]; then
    if declare -F domain_for >/dev/null 2>&1; then
      case "${id}" in
        kiwix)
          [[ "${field}" == domain ]] && { echo "$(domain_for library)"; return; }
          echo "https://$(domain_for library)"; return
          ;;
        maps)
          [[ "${field}" == domain ]] && { echo "$(domain_for maps)"; return; }
          echo "https://$(domain_for maps)"; return
          ;;
        jellyfin)
          [[ "${field}" == domain ]] && { echo "$(domain_for media)"; return; }
          echo "https://$(domain_for media)"; return
          ;;
        nextcloud)
          [[ "${field}" == domain ]] && { echo "$(domain_for files)"; return; }
          echo "https://$(domain_for files)"; return
          ;;
        peertube)
          [[ "${field}" == domain ]] && { echo "$(domain_for stream)"; return; }
          echo "https://$(domain_for stream)"; return
          ;;
        hermes)
          [[ "${field}" == domain ]] && { echo "$(domain_for hermes)"; return; }
          echo "https://$(domain_for hermes)"; return
          ;;
      esac
    fi
  fi
  if [[ -f "${REGISTRY}" ]] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json,sys
r=json.load(open('${REGISTRY}'))
app=r.get('${id}') or {}
print(app.get('${field}','') or '')
" 2>/dev/null
    return
  fi
  # Fallback
  case "${id}:${field}" in
    kiwix:name) echo "Library" ;;
    kiwix:description) echo "Offline knowledge library" ;;
    kiwix:url) echo "https://$(domain_for library)" ;;
    kiwix:domain) echo "$(domain_for library)" ;;
    kiwix:container) echo "communityos-kiwix" ;;
    maps:name) echo "Maps" ;;
    maps:description) echo "Offline maps (Martin + MapLibre)" ;;
    maps:url) echo "https://$(domain_for maps)" ;;
    maps:domain) echo "$(domain_for maps)" ;;
    maps:container) echo "communityos-martin" ;;
    jellyfin:name) echo "Media" ;;
    jellyfin:description) echo "Local media server" ;;
    jellyfin:url) echo "https://$(domain_for media)" ;;
    jellyfin:domain) echo "$(domain_for media)" ;;
    jellyfin:container) echo "communityos-jellyfin" ;;
    nextcloud:name) echo "Files" ;;
    nextcloud:description) echo "Personal and shared file storage (Nextcloud)" ;;
    nextcloud:url) echo "https://$(domain_for files)" ;;
    nextcloud:domain) echo "$(domain_for files)" ;;
    nextcloud:container) echo "communityos-nextcloud" ;;
    peertube:name) echo "Streaming" ;;
    peertube:description) echo "Community video hosting and live streaming" ;;
    peertube:url) echo "https://$(domain_for stream)" ;;
    peertube:domain) echo "$(domain_for stream)" ;;
    peertube:container) echo "communityos-peertube" ;;
    hermes:name) echo "Agent" ;;
    hermes:description) echo "Hermes Agent — autonomous local agent with tools" ;;
    hermes:url) echo "https://$(domain_for hermes)" ;;
    hermes:domain) echo "$(domain_for hermes)" ;;
    hermes:container) echo "communityos-hermes" ;;
    *:data) echo "${COMMUNITYOS_ROOT}/data/${id}" ;;
    *:compose) echo "apps/${id}.yaml" ;;
    *) echo "" ;;
  esac
}

app_aliases_resolve() {
  # friendly names -> app ids
  case "$1" in
    library) echo kiwix ;;
    media) echo jellyfin ;;
    files) echo nextcloud ;;
    streaming|stream) echo peertube ;;
    agent|hermes-agent) echo hermes ;;
    *) echo "$1" ;;
  esac
}

compose_with_apps() {
local args=()
local id
args+=(-f "${COMMUNITYOS_ROOT}/compose.yaml")
for id in $(app_list_ids); do
if app_is_enabled "${id}"; then
local cf
cf="$(app_meta "${id}" compose)"
[[ -z "${cf}" ]] && cf="apps/${id}.yaml"
if [[ -f "${COMMUNITYOS_ROOT}/${cf}" ]]; then
args+=(-f "${COMMUNITYOS_ROOT}/${cf}")
elif [[ -f "${COMMUNITYOS_ROOT}/apps/${id}.yaml" ]]; then
args+=(-f "${COMMUNITYOS_ROOT}/apps/${id}.yaml")
fi
fi
done

# Offline mode: never pull from registries

local extra=()
if [[ "${COMMUNITYOS_OFFLINE:-0}" == "1" ]]; then
local a has_up=0
for a in "$@"; do
if [[ "${a}" == "up" ]]; then
has_up=1
break
fi
done
if [[ "${has_up}" -eq 1 ]]; then
extra+=(--pull never)
fi
fi

docker compose "${args[@]}" --env-file "${COMMUNITYOS_ROOT}/.env" "$@" "${extra[@]}"
}

app_update_dns() {
  # Regenerate runtime/dnsmasq.conf from .env SERVER_IP + DOMAIN_BASE.
  local conf="${COMMUNITYOS_ROOT}/runtime/dnsmasq.conf"
  local ip=""

  if [[ -f "${COMMUNITYOS_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${COMMUNITYOS_ROOT}/.env" 2>/dev/null || true
    set +a
    ip="${SERVER_IP:-}"
  fi
  ip="${ip%\'}"; ip="${ip#\'}"
  ip="${ip%\"}"; ip="${ip#\"}"

  if [[ -z "${ip}" ]]; then
    return 0
  fi

  if declare -F domain_load >/dev/null 2>&1; then
    domain_load
  elif declare -F domain_derive >/dev/null 2>&1; then
    domain_derive
  else
    DOMAIN_BASE="${DOMAIN_BASE:-community.home.arpa}"
    DOMAIN_CHAT="${DOMAIN_CHAT:-chat.${DOMAIN_BASE}}"
    DOMAIN_AI="${DOMAIN_AI:-ai.${DOMAIN_BASE}}"
  fi

  mkdir -p "${COMMUNITYOS_ROOT}/runtime"
  {
    echo "# CommunityOS LAN DNS — SERVER_IP=${ip} DOMAIN_BASE=${DOMAIN_BASE}"
    echo "# Do not edit by hand; regenerated on start/restart and app install."
    echo "domain-needed"
    echo "bogus-priv"
    echo "no-resolv"
    echo "server=1.1.1.1"
    echo "server=8.8.8.8"
    if declare -F domain_dnsmasq_addresses >/dev/null 2>&1; then
      domain_dnsmasq_addresses "${ip}"
    else
      echo "address=/${DOMAIN_BASE}/${ip}"
      echo "address=/${DOMAIN_CHAT}/${ip}"
      echo "address=/${DOMAIN_AI}/${ip}"
    fi
  } > "${conf}"

  # Validate: every address= line must use current SERVER_IP
  if grep -E '^address=/' "${conf}" | grep -vq "/${ip}$"; then
    if declare -F log_warn >/dev/null 2>&1; then
      log_warn "dnsmasq.conf still has records not pointing at ${ip}"
    fi
  fi

  # Reload DNS container if running (and DNS mode enabled)
  if [[ "${provide_dns}" == "1" ]] && docker exec communityos-dns true >/dev/null 2>&1; then
    docker restart communityos-dns >/dev/null 2>&1 || true
  fi
}

# Pinned go-pmtiles CLI (Maps only). Not part of the base install.
PMTILES_VERSION="${PMTILES_VERSION:-1.30.3}"

install_pmtiles_cli() {
  local dest_dir="${COMMUNITYOS_ROOT}/bin"
  local dest="${dest_dir}/pmtiles"
  local arch asset url tmp
  mkdir -p "${dest_dir}"

  if [[ -x "${dest}" ]]; then
    # Already present — keep pinned binary unless missing
    return 0
  fi

  case "$(uname -m)" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      log_warn "pmtiles: unsupported architecture $(uname -m); install manually from https://github.com/protomaps/go-pmtiles/releases"
      return 0
      ;;
  esac

  asset="go-pmtiles_${PMTILES_VERSION}_Linux_${arch}.tar.gz"
  # Goreleaser asset names vary slightly across versions; try common patterns
  url="https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/${asset}"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" RETURN

  log_info "Installing pmtiles CLI v${PMTILES_VERSION} (Maps tooling)..."
  if ! curl -fsSL --connect-timeout 30 --retry 3 -o "${tmp}/pmtiles.tgz" "${url}"; then
    # Alternate asset naming used by some releases
    asset="pmtiles_${PMTILES_VERSION}_Linux_${arch}.tar.gz"
    url="https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/${asset}"
    if ! curl -fsSL --connect-timeout 30 --retry 3 -o "${tmp}/pmtiles.tgz" "${url}"; then
      log_warn "Could not download pmtiles CLI. Maps will still run; add .pmtiles/.mbtiles manually."
      log_warn "See: https://github.com/protomaps/go-pmtiles/releases"
      return 0
    fi
  fi

  tar -xzf "${tmp}/pmtiles.tgz" -C "${tmp}"
  if [[ -f "${tmp}/pmtiles" ]]; then
    install -m 755 "${tmp}/pmtiles" "${dest}"
  elif [[ -f "${tmp}/go-pmtiles" ]]; then
    install -m 755 "${tmp}/go-pmtiles" "${dest}"
  else
    # tarball may nest
    local found
    found="$(find "${tmp}" -type f -name pmtiles -o -name go-pmtiles 2>/dev/null | head -1 || true)"
    if [[ -n "${found}" ]]; then
      install -m 755 "${found}" "${dest}"
    else
      log_warn "pmtiles binary not found in archive."
      return 0
    fi
  fi
  log_ok "pmtiles CLI installed at ${dest}"
}

# Ensure Maps overlay + API are present under COMMUNITYOS_ROOT before compose up.
# Users may run `app install maps` after a partial update; do not rely on a stale apps/maps.yaml.
app_deploy_maps_files() {
  local root="${COMMUNITYOS_ROOT}"
  mkdir -p "${root}/apps" "${root}/scripts" "${root}/config" "${root}/bin" "${root}/data/maps" "${root}/static/maps"

  # Always write canonical overlay so maps-api is never missing from a stale file
  cat > "${root}/apps/maps.yaml" <<'YAML'
# CommunityOS optional app: Martin (tiles) + MapLibre UI + download API
services:
  martin:
    image: ghcr.io/maplibre/martin:v0.14.2
    container_name: communityos-martin
    restart: unless-stopped
    volumes:
      - ./data/maps:/data:ro
    command: ["/data"]

  maps-api:
    image: python:3.12-alpine
    container_name: communityos-maps-api
    restart: unless-stopped
    environment:
      MAPS_DATA: /data
      PMTILES_BIN: /usr/local/bin/pmtiles
      PMTILES_SOURCE_URL: ${PMTILES_SOURCE_URL:-https://build.protomaps.com/20260807.pmtiles}
      MARTIN_CONTAINER: communityos-martin
    volumes:
      - ./data/maps:/data
      - ./bin/pmtiles:/usr/local/bin/pmtiles:ro
      - ./scripts/maps-api.py:/app/maps-api.py:ro
      - ./config/maps-source.env:/config/maps-source.env:ro
      - /var/run/docker.sock:/var/run/docker.sock
    command: ["python3", "/app/maps-api.py"]
    depends_on:
      - martin
YAML

  # maps-api.py — always refresh from packaged copy when install runs via app_deploy
  cat > "${root}/scripts/maps-api.py" <<'MAPSAPI'
"""Minimal Maps download API for CommunityOS (Maps app only)."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

DATA = Path(os.environ.get("MAPS_DATA", "/data"))
PMTILES = os.environ.get("PMTILES_BIN", "/usr/local/bin/pmtiles")
def _load_source_url() -> str:
    # Precedence: env → mounted/packaged config → last-resort pin
    env = (os.environ.get("PMTILES_SOURCE_URL") or "").strip()
    if env:
        return env
    for candidate in (
        Path("/config/maps-source.env"),
        Path("/opt/communityos/config/maps-source.env"),
        Path(__file__).resolve().parent.parent / "config" / "maps-source.env",
    ):
        try:
            if candidate.is_file():
                for line in candidate.read_text().splitlines():
                    line = line.strip()
                    if line.startswith("PMTILES_SOURCE_URL="):
                        val = line.split("=", 1)[1].strip()
                        if val.startswith("'") and val.endswith("'"):
                            val = val[1:-1]
                        if val.startswith('"') and val.endswith('"'):
                            val = val[1:-1]
                        if val:
                            return val
        except Exception:
            pass
    # Last-resort pin (prefer updating config/maps-source.env)
    return "https://build.protomaps.com/20260807.pmtiles"


SOURCE = _load_source_url()
MARTIN = os.environ.get("MARTIN_CONTAINER", "communityos-martin")
HOST = os.environ.get("MAPS_API_HOST", "0.0.0.0")
PORT = int(os.environ.get("MAPS_API_PORT", "8099"))

JOBS: dict[str, dict] = {}
LOCK = threading.Lock()

PRESETS = [
    {
        "id": "los-angeles",
        "name": "Los Angeles",
        "bbox": [-118.95, 33.55, -117.55, 34.85],
        "maxzoom": 14,
    },
    {
        "id": "california",
        "name": "California",
        "bbox": [-124.5, 32.5, -114.1, 42.1],
        "maxzoom": 12,
    },
    {
        "id": "united-states",
        "name": "United States (lower 48)",
        "bbox": [-125.0, 24.0, -66.5, 49.5],
        "maxzoom": 10,
    },
    {
        "id": "new-york",
        "name": "New York City",
        "bbox": [-74.3, 40.45, -73.65, 41.0],
        "maxzoom": 14,
    },
]


def safe_name(name: str) -> str:
    name = (name or "map").strip().lower()
    name = re.sub(r"[^a-z0-9._-]+", "-", name)
    name = re.sub(r"-+", "-", name).strip("-")
    return name[:64] or "map"


def estimate_mb(bbox: list[float], maxzoom: int) -> float:
    """Rough heuristic for planning — not exact."""
    min_lon, min_lat, max_lon, max_lat = bbox
    # degrees² → crude area factor
    area = max(0.01, abs(max_lon - min_lon) * abs(max_lat - min_lat))
    # zoom growth is aggressive; tuned near ~88MB for LA @ z14
    zoom_factor = 2 ** max(0, maxzoom - 8)
    return round(max(1.0, area * 0.35 * zoom_factor), 1)


def list_datasets() -> list[dict]:
    DATA.mkdir(parents=True, exist_ok=True)
    out = []
    for p in sorted(DATA.glob("*.pmtiles")) + sorted(DATA.glob("*.mbtiles")):
        out.append(
            {
                "name": p.stem,
                "file": p.name,
                "size_mb": round(p.stat().st_size / (1024 * 1024), 1),
            }
        )
    return out


def restart_martin() -> bool:
    """Restart Martin via Docker Engine API (no docker CLI required)."""
    import http.client
    import socket

    class DockerSock(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.connect("/var/run/docker.sock")

    try:
        conn = DockerSock("localhost")
        conn.request("POST", f"/containers/{MARTIN}/restart?t=30")
        resp = conn.getresponse()
        ok = resp.status in (204, 200, 304)
        resp.read()
        conn.close()
        return ok
    except Exception:
        return False


def run_job(job_id: str, name: str, bbox: list[float], maxzoom: int, source: str) -> None:
    dest = DATA / f"{name}.pmtiles"
    partial = DATA / f".{name}.pmtiles.partial"
    with LOCK:
        JOBS[job_id].update(status="running", progress=5, message="Starting extract…")
    try:
        DATA.mkdir(parents=True, exist_ok=True)
        if not Path(PMTILES).exists():
            raise RuntimeError(f"pmtiles CLI not found at {PMTILES}")
        bbox_s = ",".join(str(x) for x in bbox)
        cmd = [
            PMTILES,
            "extract",
            source,
            str(partial),
            f"--bbox={bbox_s}",
            f"--maxzoom={int(maxzoom)}",
        ]
        with LOCK:
            JOBS[job_id].update(progress=15, message="Downloading / extracting tiles (internet required)…")
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=3600 * 6)
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "extract failed").strip()
            raise RuntimeError(err[:500])
        with LOCK:
            JOBS[job_id].update(progress=80, message="Verifying archive…")
        verify = subprocess.run(
            [PMTILES, "verify", str(partial)],
            capture_output=True,
            text=True,
            timeout=300,
        )
        if verify.returncode != 0:
            raise RuntimeError((verify.stderr or verify.stdout or "verify failed").strip()[:500])
        partial.replace(dest)
        with LOCK:
            JOBS[job_id].update(progress=90, message="Refreshing tile server…")
        restarted = restart_martin()
        with LOCK:
            JOBS[job_id].update(
                status="done",
                progress=100,
                message="Dataset ready" + ("" if restarted else " — run: sudo communityos app restart maps"),
                file=dest.name,
                martin_restarted=restarted,
            )
    except Exception as e:
        try:
            if partial.exists():
                partial.unlink()
        except Exception:
            pass
        with LOCK:
            JOBS[job_id].update(status="error", progress=100, message=str(e))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        return

    def _json(self, code: int, obj: dict | list) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self._json(204, {})

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in ("/health", "/maps-api/health"):
            self._json(200, {"ok": True})
            return
        if path in ("/presets", "/maps-api/presets"):
            presets = []
            for p in PRESETS:
                presets.append(
                    {
                        **p,
                        "estimated_mb": estimate_mb(p["bbox"], p["maxzoom"]),
                    }
                )
            self._json(200, {"presets": presets, "source_default": SOURCE})
            return
        if path in ("/datasets", "/maps-api/datasets"):
            self._json(200, {"datasets": list_datasets()})
            return
        if path.startswith("/jobs/") or path.startswith("/maps-api/jobs/"):
            job_id = path.rstrip("/").split("/")[-1]
            with LOCK:
                job = JOBS.get(job_id)
            if not job:
                self._json(404, {"error": "job not found"})
                return
            self._json(200, job)
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path not in ("/download", "/maps-api/download"):
            self._json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid JSON"})
            return

        name = safe_name(str(data.get("name") or data.get("id") or "map"))
        bbox = data.get("bbox")
        maxzoom = int(data.get("maxzoom") or 14)
        source = str(data.get("source") or SOURCE).strip()

        if not isinstance(bbox, list) or len(bbox) != 4:
            self._json(400, {"error": "bbox must be [minLon,minLat,maxLon,maxLat]"})
            return
        try:
            bbox = [float(x) for x in bbox]
        except (TypeError, ValueError):
            self._json(400, {"error": "bbox values must be numbers"})
            return
        if maxzoom < 0 or maxzoom > 18:
            self._json(400, {"error": "maxzoom must be 0–18"})
            return
        if (DATA / f"{name}.pmtiles").exists() and not data.get("overwrite"):
            self._json(409, {"error": f"dataset '{name}' already exists", "hint": "choose another name or set overwrite"})
            return
        # Guardrail: refuse enormous world-like downloads by default
        area = abs(bbox[2] - bbox[0]) * abs(bbox[3] - bbox[1])
        if area > 4000 and maxzoom > 8 and not data.get("confirm_large"):
            self._json(
                400,
                {
                    "error": "region/zoom looks very large",
                    "estimated_mb": estimate_mb(bbox, maxzoom),
                    "hint": "lower maxzoom or set confirm_large=true",
                },
            )
            return

        job_id = uuid.uuid4().hex[:12]
        with LOCK:
            JOBS[job_id] = {
                "id": job_id,
                "name": name,
                "bbox": bbox,
                "maxzoom": maxzoom,
                "estimated_mb": estimate_mb(bbox, maxzoom),
                "status": "queued",
                "progress": 0,
                "message": "Queued",
            }
        threading.Thread(
            target=run_job, args=(job_id, name, bbox, maxzoom, source), daemon=True
        ).start()
        self._json(202, {"job_id": job_id, **JOBS[job_id]})


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"maps-api listening on {HOST}:{PORT}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()

MAPSAPI

  if [[ ! -f "${root}/config/maps-source.env" ]]; then
    cat > "${root}/config/maps-source.env" <<'MAPSRC'
# Protomaps daily build used for region extracts. Update without editing Python.
# See https://build.protomaps.com/
PMTILES_SOURCE_URL=https://build.protomaps.com/20260807.pmtiles
MAPSRC
  fi
  if [[ -f "${root}/.env" ]] && ! grep -q '^PMTILES_SOURCE_URL=' "${root}/.env" 2>/dev/null; then
    echo "PMTILES_SOURCE_URL=https://build.protomaps.com/20260807.pmtiles" >> "${root}/.env"
  fi

  # Caddy: ensure /maps-api/* is proxied
  local caddy="${root}/Caddyfile"
  if [[ -f "${caddy}" ]] && ! grep -q 'maps-api:8099' "${caddy}" 2>/dev/null; then
    if grep -q 'handle /tiles/\*' "${caddy}" 2>/dev/null; then
      python3 -c '
from pathlib import Path
p = Path("'"${caddy}"'")
t = p.read_text()
needle = "\thandle /tiles/* {\n\t\turi strip_prefix /tiles\n\t\treverse_proxy martin:3000\n\t}\n"
insert = needle + "\thandle /maps-api/* {\n\t\turi strip_prefix /maps-api\n\t\treverse_proxy maps-api:8099\n\t}\n"
if needle in t and "maps-api:8099" not in t:
    p.write_text(t.replace(needle, insert, 1))
'
    fi
  fi
}
