#!/usr/bin/env bash
# CommunityOS offline-mode helpers.
# Sourced by install-engine.sh and package-offline.sh when COMMUNITYOS_OFFLINE=1
# or when verifying/building an offline bundle.

# Sanitize a Docker image reference into a filesystem-safe archive name.
# Example: ghcr.io/open-webui/open-webui:v0.6.26 → ghcr.io_open-webui_open-webui_v0.6.26.tar
offline_image_to_filename() {
  local ref="${1:?}"
  local name
  name="${ref//\//_}"
  name="${name//:/_}"
  printf '%s.tar\n' "${name}"
}

# List core + optional images from compose.yaml and apps/*.yaml under $1 (package root)
offline_list_images() {
  local root="${1:?}"
  local f
  {
    [[ -f "${root}/compose.yaml" ]] && grep -E '^\s+image:\s+' "${root}/compose.yaml"
    for f in "${root}/apps/"*.yaml; do
      [[ -f "${f}" ]] || continue
      grep -E '^\s+image:\s+' "${f}" || true
    done
  } | sed -E 's/^[[:space:]]*image:[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//' \
    | grep -v '^$' | sort -u
}

offline_core_images() {
  local root="${1:?}"
  # Core stack only (compose.yaml) — required for base install
  grep -E '^\s+image:\s+' "${root}/compose.yaml" \
    | sed -E 's/^[[:space:]]*image:[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//' \
    | grep -v '^$' | sort -u
}

offline_optional_images_for_app() {
  local root="${1:?}"
  local app="${2:?}"
  local f="${root}/apps/${app}.yaml"
  [[ -f "${f}" ]] || return 0
  grep -E '^\s+image:\s+' "${f}" \
    | sed -E 's/^[[:space:]]*image:[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//' \
    | grep -v '^$' | sort -u
}

# True if apps/<id>.manifest.yaml sets redistribute_offline: true
# Default (missing or false) = do NOT put upstream images in CommunityOS offline bundles.
offline_app_redistribute_offline() {
  local root="${1:?}"
  local app="${2:?}"
  local mf="${root}/apps/${app}.manifest.yaml"
  [[ -f "${mf}" ]] || return 1
  local v
  v="$(grep -E '^redistribute_offline:' "${mf}" 2>/dev/null | head -1 | sed -E 's/^redistribute_offline:[[:space:]]*//;s/[[:space:]]*$//;s/^["'\'']//;s/["'\'']$//' | tr '[:upper:]' '[:lower:]')"
  case "${v}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Optional-app images that may be saved into offline bundles (manifest opt-in only)
offline_optional_images_redistributable() {
  local root="${1:?}"
  local app mf
  for mf in "${root}"/apps/*.manifest.yaml; do
    [[ -f "${mf}" ]] || continue
    app="$(basename "${mf}" .manifest.yaml)"
    if offline_app_redistribute_offline "${root}" "${app}"; then
      offline_optional_images_for_app "${root}" "${app}"
    fi
  done | grep -v '^$' | sort -u
}

# All optional-app image refs (for documentation / admin-supplied lists) — not for default packaging
offline_optional_images_all() {
  local root="${1:?}"
  local f
  for f in "${root}"/apps/*.yaml; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *manifest* ]] && continue
    grep -E '^\s+image:\s+' "${f}" \
      | sed -E 's/^[[:space:]]*image:[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//' \
      || true
  done | grep -v '^$' | sort -u
}


# Require offline mode not to touch the network
offline_forbid_network() {
  if [[ "${COMMUNITYOS_OFFLINE:-0}" == "1" ]]; then
    return 0
  fi
  return 1
}

offline_die() {
  echo "[FAIL] $*" >&2
  exit 1
}

offline_ok() {
  echo "[ OK ] $*"
}

offline_info() {
  echo "[INFO] $*"
}

# Verify bundle layout + manifest + checksums
# Usage: offline_verify_bundle /path/to/bundle
offline_verify_bundle() {
  local bundle="${1:?}"
  local manifest="${bundle}/manifest.json"
  local missing=0
  local arch host_arch

  offline_info "Verifying CommunityOS offline bundle..."

  [[ -d "${bundle}" ]] || offline_die "Offline bundle directory not found: ${bundle}"
  [[ -f "${manifest}" ]] || offline_die "manifest.json missing in offline bundle"
  [[ -d "${bundle}/communityos" ]] || offline_die "communityos/ source tree missing in offline bundle"
  [[ -d "${bundle}/images" ]] || offline_die "images/ directory missing in offline bundle"
  [[ -d "${bundle}/packages" ]] || offline_die "packages/ directory missing in offline bundle"
  [[ -f "${bundle}/communityos/compose.yaml" ]] || offline_die "communityos/compose.yaml missing"
  [[ -f "${bundle}/communityos/VERSION" ]] || offline_die "communityos/VERSION missing"

  host_arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "${host_arch}" in
    x86_64) host_arch=amd64 ;;
    aarch64) host_arch=arm64 ;;
  esac

  if command -v python3 >/dev/null 2>&1; then
    python3 - "${manifest}" "${host_arch}" <<'PY' || exit 1
import json, sys, os, hashlib
manifest_path, host_arch = sys.argv[1], sys.argv[2]
bundle = os.path.dirname(manifest_path)
with open(manifest_path) as f:
    m = json.load(f)
print(f"[ OK ] Bundle version: {m.get('version','?')}")
print(f"[ OK ] Debian target: {m.get('debian','?')}")
print(f"[ OK ] Architecture: {m.get('architecture','?')}")
if m.get("architecture") and m["architecture"] != host_arch:
    print(f"[FAIL] Bundle architecture {m['architecture']} does not match host {host_arch}")
    sys.exit(1)
# Verify checksums if present
checksums = m.get("checksums") or {}
failed = []
for rel, expected in checksums.items():
    path = os.path.join(bundle, rel)
    if not os.path.isfile(path):
        failed.append(f"missing {rel}")
        continue
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    got = h.hexdigest()
    if got != expected:
        failed.append(f"checksum mismatch: {rel}")
if failed:
    print("[FAIL] Offline bundle verification failed.")
    for x in failed[:20]:
        print(f"       {x}")
    sys.exit(1)
if checksums:
    print("[ OK ] Package/image checksums")
# Verify required docker images listed in manifest exist as files
images = m.get("docker_images") or []
missing = []
for ref in images:
    # filename convention
    name = ref.replace("/", "_").replace(":", "_") + ".tar"
    path = os.path.join(bundle, "images", name)
    if not os.path.isfile(path):
        # also allow images/core/ and images/optional/
        alt1 = os.path.join(bundle, "images", "core", name)
        alt2 = os.path.join(bundle, "images", "optional", name)
        if not (os.path.isfile(alt1) or os.path.isfile(alt2)):
            missing.append(ref)
if missing:
    print("[FAIL] Offline bundle is missing required image file(s):")
    for ref in missing:
        print(f"       {ref}")
    sys.exit(1)
print("[ OK ] Required Docker image archives present")
print("[ OK ] CommunityOS source present")
PY
  else
    offline_ok "Bundle layout (python3 not available for deep checksum verify)"
  fi
}

# Install .deb packages from bundle/packages without network
offline_install_debs() {
  local bundle="${1:?}"
  local pkgdir="${bundle}/packages"
  [[ -d "${pkgdir}" ]] || offline_die "packages/ missing"

  local debs=()
  while IFS= read -r -d '' f; do
    debs+=("$f")
  done < <(find "${pkgdir}" -type f -name '*.deb' -print0 | sort -z)

  if [[ "${#debs[@]}" -eq 0 ]]; then
    offline_die "No .deb packages found in ${pkgdir}"
  fi

  offline_info "Installing ${#debs[@]} local Debian packages (no network)..."
  # dpkg may return non-zero when dependencies are ordered suboptimally; retry once
  set +e
  DEBIAN_FRONTEND=noninteractive dpkg -i "${debs[@]}" 2>&1 | tail -20
  local rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>&1 | tail -10
    DEBIAN_FRONTEND=noninteractive dpkg -i "${debs[@]}" 2>&1 | tail -20
    rc=$?
  fi
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    offline_die "Local package installation failed. Bundle may be incomplete for this Debian release."
  fi
  offline_ok "Local Debian packages installed"
}

# Load all docker image tarballs from bundle/images (core + optional)
offline_load_images() {
  local bundle="${1:?}"
  local imgdir="${bundle}/images"
  [[ -d "${imgdir}" ]] || offline_die "images/ missing"

  local tars=()
  while IFS= read -r -d '' f; do
    tars+=("$f")
  done < <(find "${imgdir}" -type f -name '*.tar' -print0 | sort -z)

  if [[ "${#tars[@]}" -eq 0 ]]; then
    offline_die "No Docker image archives (*.tar) found under images/"
  fi

  offline_info "Loading ${#tars[@]} Docker image archive(s)..."
  local f
  for f in "${tars[@]}"; do
    offline_info "  docker load -i $(basename "${f}")"
    if ! docker load -i "${f}"; then
      offline_die "docker load failed for $(basename "${f}")"
    fi
  done
  offline_ok "Docker images loaded from offline bundle"
}

# Verify a list of image refs exist locally (docker image inspect)
offline_assert_images_present() {
  local ref
  for ref in "$@"; do
    if ! docker image inspect "${ref}" >/dev/null 2>&1; then
      offline_die "Required Docker image not loaded: ${ref}"
    fi
  done
  offline_ok "All required Docker images present locally"
}

# Compose must never pull in offline mode
offline_compose_up() {
  local args=("$@")
  if [[ "${COMMUNITYOS_OFFLINE:-0}" == "1" ]]; then
    # Compose V2 supports --pull never
    docker compose "${args[@]}" up -d --pull never
  else
    docker compose "${args[@]}" up -d
  fi
}
