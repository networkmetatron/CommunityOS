#!/usr/bin/env bash
# Build a CommunityOS offline installation bundle.
# Must be run on a networked machine with Docker and apt access.
#
# Usage:
#   ./scripts/package-offline.sh [version]
#
# Output:
#   dist/communityos-offline-<version>-<arch>/
#   dist/communityos-offline-<version>-<arch>.tar
#
# This is separate from GitHub source releases. Offline bundles include
# Debian packages and Docker images so air-gapped hosts can install without
# Internet access.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/lib/offline.sh"

VERSION="${1:-$(tr -d '[:space:]' < "${ROOT}/VERSION" 2>/dev/null || echo "0.0.0")}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
case "${ARCH}" in
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
esac

DEBIAN_ID="13"
if [[ -f /etc/os-release ]]; then
  # Read only VERSION_ID — do not source the file (it defines VERSION= and would
  # overwrite CommunityOS VERSION from the VERSION file / CLI argument).
  OS_VERSION_ID="$(grep -E '^VERSION_ID=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"')"
  if [[ -n "${OS_VERSION_ID}" ]]; then
    DEBIAN_ID="${OS_VERSION_ID%%.*}"
  fi
fi

COMMIT="unknown"
if command -v git >/dev/null 2>&1 && git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMIT="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

OUT_BASE="${ROOT}/dist"
BUNDLE_NAME="communityos-offline-v${VERSION}-${ARCH}"
STAGE="${OUT_BASE}/${BUNDLE_NAME}"

echo "==================================="
echo "  CommunityOS Offline Packager"
echo "==================================="
echo "Version:  ${VERSION}"
echo "Arch:     ${ARCH}"
echo "Debian:   ${DEBIAN_ID}"
echo "Commit:   ${COMMIT}"
echo "Output:   ${STAGE}"
echo

if [[ "${EUID}" -ne 0 ]]; then
  echo "[WARN] Not root — apt download of Docker packages may fail."
  echo "       Prefer: sudo ./scripts/package-offline.sh ${VERSION}"
fi

command -v docker >/dev/null 2>&1 || { echo "[FAIL] Docker is required to save images."; exit 1; }

rm -rf "${STAGE}"
mkdir -p "${STAGE}"/{communityos,packages,images/core,images/optional,docker}

# --- 1) CommunityOS source tree ---
echo "[INFO] Copying CommunityOS source..."
if command -v git >/dev/null 2>&1 && git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${ROOT}" archive --format=tar HEAD | tar -x -C "${STAGE}/communityos"
else
  tar -C "${ROOT}" \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='*.zip' \
    --exclude='*.tar' \
    --exclude='.env' \
    --exclude='runtime/dnsmasq.conf' \
    --exclude='runtime/services' \
    --exclude='runtime/services/*' \
    --exclude='runtime/apps' \
    --exclude='runtime/apps/*' \
    --exclude='runtime/offline.env' \
    --exclude='data/*/media' \
    --exclude='data/*/media/*' \
    -cf - . | tar -x -C "${STAGE}/communityos"
fi

# Never ship deployment/runtime state
rm -f "${STAGE}/communityos/.env"
rm -f "${STAGE}/communityos/runtime/dnsmasq.conf"
rm -f "${STAGE}/communityos/runtime/offline.env"
rm -rf "${STAGE}/communityos/runtime/services"
rm -rf "${STAGE}/communityos/runtime/apps"
mkdir -p "${STAGE}/communityos/runtime"

# Ensure offline helpers are present even if archive filtered oddly
cp -a "${ROOT}/lib/offline.sh" "${STAGE}/communityos/lib/offline.sh"
cp -a "${ROOT}/scripts/package-offline.sh" "${STAGE}/communityos/scripts/package-offline.sh" 2>/dev/null || true
# Top-level install entry that understands --offline
cp -a "${ROOT}/install.sh" "${STAGE}/install.sh"

echo "[ OK ] Source copied"

# --- 2) Docker images ---
# Policy: core compose images are always packaged.
# Optional third-party app images are NOT redistributed by default.
# Only apps with redistribute_offline: true in apps/<id>.manifest.yaml are saved.
mapfile -t CORE_IMAGES < <(offline_core_images "${ROOT}")
mapfile -t OPTIONAL_REDISTRIBUTABLE < <(offline_optional_images_redistributable "${ROOT}")
mapfile -t OPTIONAL_ALL < <(offline_optional_images_all "${ROOT}")

echo "[INFO] Pulling and saving core Docker images..."
for ref in "${CORE_IMAGES[@]}"; do
  echo "  pull ${ref}"
  docker pull "${ref}"
  fname="$(offline_image_to_filename "${ref}")"
  docker save -o "${STAGE}/images/core/${fname}" "${ref}"
  echo "  saved images/core/${fname}"
done

echo "[INFO] Optional-app images (redistribute_offline: true only)..."
OPTIONAL_SAVED=0
if [[ "${#OPTIONAL_REDISTRIBUTABLE[@]}" -eq 0 ]]; then
  echo "  (none — no optional app marked redistribute_offline: true)"
  echo "  Metadata/config for optional apps is still in communityos/apps/."
  echo "  Admins supply third-party images for air-gapped optional installs."
else
  for ref in "${OPTIONAL_REDISTRIBUTABLE[@]}"; do
    fname="$(offline_image_to_filename "${ref}")"
    if [[ -f "${STAGE}/images/core/${fname}" ]]; then
      continue
    fi
    echo "  pull ${ref}"
    docker pull "${ref}"
    docker save -o "${STAGE}/images/optional/${fname}" "${ref}"
    echo "  saved images/optional/${fname}"
    OPTIONAL_SAVED=$((OPTIONAL_SAVED + 1))
  done
fi
echo "[ OK ] Docker images saved (core + ${OPTIONAL_SAVED} approved optional)"

# Record which optional images exist upstream but were intentionally omitted
mkdir -p "${STAGE}/images/optional"
{
  echo "# Optional third-party images NOT included in this bundle by default."
  echo "# Online installs still pull these from upstream registries."
  echo "# Air-gapped optional-app install: docker load your own copies, then:"
  echo "#   sudo communityos app install <id>"
  echo "#"
  for ref in "${OPTIONAL_ALL[@]}"; do
    fname="$(offline_image_to_filename "${ref}")"
    if [[ -f "${STAGE}/images/core/${fname}" ]] || [[ -f "${STAGE}/images/optional/${fname}" ]]; then
      continue
    fi
    echo "${ref}"
  done
} > "${STAGE}/images/optional/ADMIN_SUPPLIED_IMAGES.txt"

# --- 3) Debian packages (Docker + bootstrap tools) ---
echo "[INFO] Downloading Debian packages for offline install..."
PKG_LIST=(
  ca-certificates
  curl
  openssl
  libnss3-tools
  dnsutils
  docker-ce
  docker-ce-cli
  containerd.io
  docker-compose-plugin
)

# Ensure Docker apt source exists so packages can be downloaded
if [[ ! -f /etc/apt/sources.list.d/docker.sources ]] && [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  echo "[INFO] Adding Docker apt repository for package download..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc" > /etc/apt/sources.list.d/docker.sources
fi

apt-get update -qq
# Download packages + dependencies into packages/
# Prefer apt-get install --download-only (reliable recursive deps).
# APT requires Archives/partial under Dir::Cache::Archives.
mkdir -p "${STAGE}/packages/partial"
set +e
DEBIAN_FRONTEND=noninteractive apt-get install --download-only --reinstall -y \
  -o Dir::Cache::Archives="${STAGE}/packages" \
  "${PKG_LIST[@]}"
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then
  echo "[WARN] apt-get --download-only reported errors; checking for any .deb files..."
fi
# Keep only .deb files (drop partial indexes, lists, etc.)
find "${STAGE}/packages" -type f ! -name '*.deb' -delete 2>/dev/null || true
# Remove empty partial dir noise if any remain
rmdir "${STAGE}/packages/partial" 2>/dev/null || true
DEB_COUNT="$(find "${STAGE}/packages" -name '*.deb' | wc -l | tr -d ' ')"
if [[ "${DEB_COUNT}" -lt 5 ]]; then
  echo "[WARN] Only ${DEB_COUNT} .deb packages downloaded — offline Docker install may fail."
  echo "       Run this script as root on Debian ${DEBIAN_ID} with Docker apt source enabled."
else
  echo "[ OK ] ${DEB_COUNT} Debian packages downloaded"
fi

# --- 4) Optional: note about maps datasets ---
mkdir -p "${STAGE}/datasets"
cat > "${STAGE}/datasets/README.txt" << 'NOTE'
Optional large datasets (not required for CommunityOS install)
==============================================================

Maps (.pmtiles / .mbtiles)
  Place into the offline host after install:
    /opt/communityos/data/maps/

  Then:
    sudo communityos app restart maps

Kiwix ZIM files
  Place into:
    /opt/communityos/data/kiwix/

Do not embed multi-gigabyte map/world datasets in the base offline
bundle unless you intentionally build a specialized geographic pack.
NOTE

# --- 5) manifest.json + checksums ---
echo "[INFO] Writing manifest.json and checksums..."
python3 - <<PY
import hashlib, json, os, pathlib

stage = pathlib.Path("${STAGE}")
version = "${VERSION}"
arch = "${ARCH}"
commit = "${COMMIT}"
debian = "${DEBIAN_ID}"

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

core_images = """$(printf '%s\n' "${CORE_IMAGES[@]}")""".strip().splitlines()
optional_images = """$(printf '%s\n' "${OPTIONAL_REDISTRIBUTABLE[@]}")""".strip().splitlines()
optional_omitted = """$(printf '%s\n' "${OPTIONAL_ALL[@]}")""".strip().splitlines()

checksums = {}
for path in stage.rglob("*"):
    if not path.is_file():
        continue
    if path.name == "manifest.json":
        continue
    rel = str(path.relative_to(stage)).replace("\\\\", "/")
    # Skip extremely large optional datasets if any
    if rel.startswith("datasets/") and path.suffix in {".pmtiles", ".mbtiles", ".zim"}:
        continue
    checksums[rel] = sha256(path)

packages = sorted(p.name for p in (stage / "packages").glob("*.deb"))

manifest = {
    "name": "CommunityOS Offline Bundle",
    "version": version,
    "communityos_commit": commit,
    "debian": debian,
    "architecture": arch,
    "docker_images": core_images,  # required for base install
    "docker_images_optional": [i for i in optional_images if i not in core_images],
    "docker_images_optional_admin_supplied": [
        i for i in optional_omitted
        if i not in core_images and i not in optional_images
    ],
    "optional_image_policy": "Optional third-party images are omitted unless apps/<id>.manifest.yaml sets redistribute_offline: true",
    "packages": packages,
    "checksums": checksums,
}

with open(stage / "manifest.json", "w") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
print(f"[ OK ] manifest.json ({len(checksums)} checksums, {len(core_images)} core images, {len(optional_images)} approved optional images, {len(packages)} packages)")
PY

# --- 6) Bundle README ---
cat > "${STAGE}/README.md" << README
# CommunityOS Offline Bundle v${VERSION}

Install CommunityOS on a **fresh Debian ${DEBIAN_ID}** machine **without Internet access**.

## Install

1. Copy this entire directory to the target server (USB drive, local share, etc.).
2. On the target:

\`\`\`bash
cd /path/to/${BUNDLE_NAME}
sudo ./install.sh --offline .
\`\`\`

Or:

\`\`\`bash
sudo ./install.sh --offline /path/to/${BUNDLE_NAME}
\`\`\`

## What this bundle contains

- \`communityos/\` — CommunityOS source and CLI
- \`packages/\` — Debian \`.deb\` packages (Docker + bootstrap tools)
- \`images/core/\` — Docker images required for the base install (from compose.yaml)
- \`images/optional/\` — only optional-app images with redistribute_offline: true
- \`images/optional/ADMIN_SUPPLIED_IMAGES.txt\` — upstream refs intentionally omitted
- \`communityos/apps/\` — optional app metadata and compose overlays (always included)
- \`manifest.json\` — version, architecture, image list, checksums

## Guarantees

In offline mode the installer will **not**:

- contact GitHub, Docker Hub, GHCR, or Debian mirrors
- run \`docker pull\`
- run \`apt update\` against remote repositories

If a required image or package is missing, installation **fails closed** with a clear error.

## Optional apps after install

Optional **third-party images are not redistributed by default**. Online hosts
still run \`communityos app install <id>\` and pull upstream images as today.

On air-gapped hosts, load any required images yourself (see
\`images/optional/ADMIN_SUPPLIED_IMAGES.txt\`), then:

\`\`\`bash
sudo communityos app install nextcloud
sudo communityos app install peertube
sudo communityos app install jellyfin
sudo communityos app install maps
sudo communityos app install kiwix
sudo communityos app install hermes
\`\`\`

Maps installs the application only. Map **datasets** are not included; place
\`.pmtiles\` / \`.mbtiles\` in \`/opt/communityos/data/maps/\` then restart Maps.

## Architecture / Debian

- Architecture: **${ARCH}**
- Target Debian: **${DEBIAN_ID}**
- CommunityOS commit: **${COMMIT}**
README

# Wrapper install.sh at bundle root (delegates into communityos/ with --offline)
cat > "${STAGE}/install.sh" << 'WRAP'
#!/usr/bin/env bash
# CommunityOS offline bundle entrypoint
set -euo pipefail
BUNDLE="$(cd "$(dirname "$0")" && pwd)"
export COMMUNITYOS_OFFLINE=1
export COMMUNITYOS_OFFLINE_BUNDLE="${BUNDLE}"
# Allow: sudo ./install.sh   OR   sudo ./install.sh --offline .
exec bash "${BUNDLE}/communityos/install.sh" --offline "${BUNDLE}" "$@"
WRAP
chmod 755 "${STAGE}/install.sh" "${STAGE}/communityos/install.sh"

# --- 7) Tar archive ---
mkdir -p "${OUT_BASE}"
TAR="${OUT_BASE}/${BUNDLE_NAME}.tar"
echo "[INFO] Creating ${TAR} ..."
tar -C "${OUT_BASE}" -cf "${TAR}" "${BUNDLE_NAME}"
SIZE="$(du -h "${TAR}" | awk '{print $1}')"
echo
echo "==================================="
echo "  Offline bundle ready"
echo "==================================="
echo "Directory: ${STAGE}"
echo "Archive:   ${TAR} (${SIZE})"
echo
echo "Copy the directory or the .tar to a USB drive, then on the air-gapped host:"
echo "  tar -xf ${BUNDLE_NAME}.tar"
echo "  cd ${BUNDLE_NAME}"
echo "  sudo ./install.sh"
echo
