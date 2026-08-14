#!/usr/bin/env bash
# CommunityOS release helper — normal releases do NOT produce a custom source ZIP.
#
# Normal release workflow (publish to GitHub):
#   1. Commit and push to main
#   2. Tag the release
#   3. Create a GitHub Release from the tag
#
# GitHub automatically attaches Source Code (zip/tar.gz) archives to the release.
# Those archives are sufficient for online installs.
#
# Do NOT upload a hand-built communityos-vX.Y.Z.zip as a GitHub Release asset.
#
# Offline air-gapped installs use a separate artifact:
#   sudo ./scripts/package-offline.sh [version]
#   → dist/communityos-offline-vX.Y.Z-ARCH.tar
#
# Optional: internal developer test archive (never publish to GitHub):
#   ./scripts/package-release.sh --internal-test-archive
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo "0.0.0")"

usage() {
  cat <<USAGE
CommunityOS release helper

Normal release (no custom ZIP):
  1. git status && git commit && git push
  2. git tag -a v${VERSION} -m "CommunityOS ${VERSION}"
  3. git push origin v${VERSION}
  4. Create a GitHub Release from the tag
     (GitHub attaches Source Code zip/tar.gz automatically)

Offline bundle (separate from GitHub source releases):
  sudo ./scripts/package-offline.sh ${VERSION}

Internal test archive only (do not publish to GitHub):
  ./scripts/package-release.sh --internal-test-archive

USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" != "--internal-test-archive" ]]; then
  usage
  echo "Current VERSION file: ${VERSION}"
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Git HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "Branch:   $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  fi
  echo
  echo "No custom source ZIP was created (by design)."
  exit 0
fi

# --- Internal-only test archive (not a release deliverable) ---
NAME="communityos-v${VERSION}"
OUT_DIR="${HOME}/releases"
mkdir -p "${OUT_DIR}" 2>/dev/null || OUT_DIR="${ROOT}/dist"
mkdir -p "${OUT_DIR}"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

mkdir -p "${STAGE}/communityos"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git archive --format=tar HEAD | tar -x -C "${STAGE}/communityos"
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
    --exclude='secrets/acme.env' \
    -cf - . | tar -x -C "${STAGE}/communityos"
fi

# Never ship deployment/runtime state (even if git archive or tree had it)
rm -f "${STAGE}/communityos/.env"
rm -f "${STAGE}/communityos/runtime/dnsmasq.conf"
rm -f "${STAGE}/communityos/runtime/offline.env"
rm -rf "${STAGE}/communityos/runtime/services"
rm -rf "${STAGE}/communityos/runtime/apps"
# SECURITY: never ship real or placeholder ACME secrets — only the example file
rm -f "${STAGE}/communityos/secrets/acme.env" 2>/dev/null || true
find "${STAGE}/communityos/secrets" -type f ! -name '*.example' -delete 2>/dev/null || true
mkdir -p "${STAGE}/communityos/secrets"
mkdir -p "${STAGE}/communityos/runtime"
# Keep an empty runtime dir; installer creates services/, acme.env placeholder, and configs
# Verify example is present (required for operators)
if [[ ! -f "${STAGE}/communityos/secrets/acme.env.example" ]]; then
  echo "ERROR: secrets/acme.env.example missing from release tree" >&2
  exit 1
fi

chmod 755 "${STAGE}/communityos/install.sh" 2>/dev/null || true
chmod 755 "${STAGE}/communityos/bin/communityos" 2>/dev/null || true
chmod 755 "${STAGE}/communityos/scripts/"*.sh 2>/dev/null || true
chmod 755 "${STAGE}/communityos/update.sh" 2>/dev/null || true
chmod 755 "${STAGE}/communityos/lib/"*.sh 2>/dev/null || true

ZIP="${OUT_DIR}/${NAME}.zip"
rm -f "${ZIP}"
(cd "${STAGE}" && zip -qr "${ZIP}" communityos)

# SECURITY CHECK: refuse to ship any non-example secrets
if unzip -l "${ZIP}" | grep -E 'secrets/acme\.env$' >/dev/null 2>&1; then
  echo "ERROR: release ZIP contains secrets/acme.env — aborting" >&2
  rm -f "${ZIP}"
  exit 1
fi
echo "Created INTERNAL test archive: ${ZIP}"
echo
echo "WARNING: This archive is for local transfer/testing only."
echo "Do NOT upload it as a GitHub Release asset."
echo "Do NOT extract it over a permanent Git working tree (e.g. ~/communityos)."
echo "Extract under ~/releases/ if you need to inspect or test the package."
echo
echo "Normal releases: git tag + GitHub Release (auto source archives only)."
echo "Offline installs: ./scripts/package-offline.sh ${VERSION}"
