# CommunityOS Offline Installation

Install CommunityOS on a **fresh Debian 13** server **without Internet access**, using a self-contained offline bundle (USB drive, local share, or mounted directory).

This is **not** the same as a GitHub source ZIP. An offline bundle includes:

- CommunityOS source and CLI
- Debian `.deb` packages (Docker Engine, Compose plugin, bootstrap tools)
- Docker images for the core stack and optional apps
- `manifest.json` with version, architecture, image list, and checksums

## Two different artifacts

| Artifact | Purpose | Contains |
|----------|---------|----------|
| **GitHub release / source** | Normal online install | Source only |
| **Offline bundle** | Air-gapped install | Source + packages + images |

Do not treat a GitHub source archive as an offline installer.

## Build an offline bundle (connected machine)

On a networked Debian 13 host with Docker:

```bash
cd /path/to/CommunityOS
sudo ./scripts/package-offline.sh 1.1.1
```

Output:

```text
dist/communityos-offline-v1.1.1-amd64/
dist/communityos-offline-v1.1.1-amd64.tar
```

Copy the directory or the `.tar` to a USB drive.

## Install on an air-gapped host

```bash
tar -xf communityos-offline-v1.1.1-amd64.tar
cd communityos-offline-v1.1.1-amd64
sudo ./install.sh
```

Or explicitly:

```bash
sudo ./install.sh --offline /media/usb/communityos-offline-v1.1.1-amd64
```

The installer will:

1. Verify `manifest.json`, architecture, and checksums
2. Install Docker and tools from local `.deb` packages (no `apt update` against mirrors)
3. `docker load` every required image archive (no `docker pull`)
4. Run the normal CommunityOS configuration prompts
5. Start services with `docker compose up -d --pull never`

If anything required is missing or corrupted, installation **fails closed** with a clear error. It will not fall back to the Internet.

## What must not happen in offline mode

When `COMMUNITYOS_OFFLINE=1`:

- No GitHub, Docker Hub, GHCR, or Debian mirror access
- No `docker pull`
- No remote `apt update` / `apt install` from the network
- No silent download of map datasets or AI models

## Optional apps offline

After the base install:

```bash
sudo communityos app install nextcloud
sudo communityos app install peertube
sudo communityos app install jellyfin
sudo communityos app install maps
sudo communityos app install kiwix
```

Optional-app images are loaded from `images/optional/` in the bundle when needed.

### Maps datasets

Maps **application** install is offline-capable. **Map tiles** are not bundled by default (large files).

```text
[ OK ] Maps application installed
[INFO] Add .pmtiles or .mbtiles to /opt/communityos/data/maps
       then: sudo communityos app restart maps
```

### Ollama models

Ollama runtime is included. Model weights are still user-selected and are **not** downloaded by the offline installer.

## Persistence and repair

Offline install uses the same data paths and repair logic as online install:

- Existing Nextcloud / PeerTube / other app data is preserved
- Re-running the offline installer is intended to be idempotent
- Credentials continue to come from `/opt/communityos/.env`

## Negative tests (definition of done)

| Test | Expected |
|------|----------|
| Bundle missing one core image | `[FAIL] Required Docker image…` |
| Corrupted checksum | `[FAIL] Offline bundle verification failed` |
| Network fully disconnected | Install still succeeds |
| Optional app image missing | App install fails closed; base install unaffected |

## Environment variables

| Variable | Meaning |
|----------|---------|
| `COMMUNITYOS_OFFLINE=1` | Offline mode active |
| `COMMUNITYOS_OFFLINE_BUNDLE=/path` | Path to verified offline bundle root |

These are set automatically by `install.sh --offline`.


## Optional third-party images (redistribution policy)

CommunityOS offline bundles are **not** a redistribution channel for arbitrary
upstream software.

| Kind | In offline bundle? |
|------|--------------------|
| **Core** images from `compose.yaml` (Website, Chat/Synapse, Assistant/Ollama/Open WebUI, DNS, databases, …) | **Yes** — required for air-gapped base install |
| **Optional app metadata** (`apps/*.yaml`, `apps/*.manifest.yaml`, registry) | **Yes** — installers and config always ship |
| **Optional third-party images** (PeerTube, Nextcloud, Jellyfin, Kiwix, Maps, Hermes, …) | **No by default** |

### Manifest field: `redistribute_offline`

In `apps/<id>.manifest.yaml`:

```yaml
# false or absent = package-offline.sh will NOT pull/save this app's images
redistribute_offline: false

# true = only when redistribution of the upstream image is verified/approved
# for inclusion in CommunityOS offline bundles
redistribute_offline: true
```

`scripts/package-offline.sh` **enforces** this:

- Always saves **core** images under `images/core/`
- Saves optional images under `images/optional/` **only** when `redistribute_offline: true`
- Writes `images/optional/ADMIN_SUPPLIED_IMAGES.txt` listing omitted upstream refs

### Online vs air-gapped optional apps

- **Online:** `communityos app install <id>` behaves as today — Compose pulls the
  upstream image referenced in `apps/<id>.yaml`.
- **Air-gapped:** administrator supplies and `docker load`s the required image(s),
  then runs `communityos app install <id>`. Missing images fail closed (no pull).

This policy applies uniformly to current and future optional apps (Hermes,
PeerTube, Jellyfin, Nextcloud, Kiwix, Maps, …). Core services such as WordPress
and Synapse remain part of the core offline image set because they ship with
the base platform, not as optional apps.
