# CommunityOS

**Version 1.1.0**

> Take a clean Debian installation and turn it into a private, self-hosted community server with one command.

## Install

1. Install Debian 13.
2. On the server:

```bash
sudo ./install.sh
```

3. Answer a few questions.
4. DNS option during install:
   - **Y** — CommunityOS provides LAN DNS (`*.home.arpa`); set router DHCP DNS to this server.
   - **n** — You manage DNS yourself (Pi-hole, router, `/etc/hosts`, etc.).
5. **Reconnect clients** (Wi‑Fi off/on, Ethernet replug, or renew DHCP lease) so they pick up the new DNS.
6. Open **http://community.home.arpa**, install the **CommunityOS certificate once** (covers all services), then use HTTPS.

If `community.home.arpa` does not resolve:

- Disconnect and reconnect Wi‑Fi  
- **OR** unplug/reconnect Ethernet  
- **OR** renew the DHCP lease  

The device may still be using its previous DNS configuration.

## Certificate

CommunityOS uses one local CA for every hostname. Install `http://community.home.arpa/ca.crt` once on each device. After that, Website, Chat, Assistant, and optional apps should not show browser trust warnings.

## Assistant / Ollama

Ollama is installed with CommunityOS but **no model weights are downloaded**. Pull a model when ready:

```bash
sudo docker exec -it communityos-ollama ollama pull llama3.2
```

Then open https://ai.community.home.arpa and select the model. CPU-only hosts are supported; a GPU is optional.

Optional **Hermes Agent** (`communityos app install hermes`) adds a tool-using
agent backend that reuses the same Ollama models. Open WebUI remains the
user-facing UI. Hermes is never installed by default — see [docs/HERMES.md](docs/HERMES.md).

## Optional apps

```bash
communityos apps
sudo communityos app install kiwix      # Library
sudo communityos app install maps       # Maps
sudo communityos app install jellyfin   # Media
sudo communityos app install nextcloud  # Files
sudo communityos app install peertube   # Streaming
sudo communityos app install hermes     # Agent + dashboard (opt-in; see docs/HERMES.md)
```

Installing an app updates DNS (when CommunityOS DNS is enabled) and reloads Caddy so certificates stay consistent. The same CommunityOS CA is used.

| App | URL |
|-----|-----|
| Library (Kiwix) | https://library.community.home.arpa |
| Maps | https://maps.community.home.arpa |

Maps installs the pinned `pmtiles` CLI under `/opt/communityos/bin/pmtiles`

Region downloads use a **pinned Protomaps daily build** (not an old year-stale default). Configure without code changes:

```bash
# /opt/communityos/.env  OR  /opt/communityos/config/maps-source.env
PMTILES_SOURCE_URL=https://build.protomaps.com/20260807.pmtiles
```

Then `sudo communityos app restart maps`. Current CommunityOS default is the **2026-08-07** build. (not via apt). Place `.pmtiles` / `.mbtiles` in `/opt/communityos/data/maps/` and run `sudo communityos app restart maps`. See that directory’s README for import examples.
| Media (Jellyfin) | https://media.community.home.arpa |
| Files (Nextcloud) | https://files.community.home.arpa |
| Streaming (PeerTube) | https://stream.community.home.arpa |


## Offline installation (air-gapped)

For servers **without Internet access**, build an offline bundle on a connected machine, copy it by USB, then install:

```bash
# On a connected Debian 13 builder:
sudo ./scripts/package-offline.sh 1.1.1

# On the air-gapped server:
tar -xf communityos-offline-v1.1.1-amd64.tar
cd communityos-offline-v1.1.1-amd64
sudo ./install.sh
```

The offline bundle includes Debian packages and Docker images. The installer will not contact Docker Hub, GHCR, or Debian mirrors.

See [docs/OFFLINE.md](docs/OFFLINE.md) for the full format, guarantees, and test checklist.

Normal (online) GitHub releases use **git tags** and GitHub's automatic Source Code archives only — do not publish a custom `communityos-vX.Y.Z.zip` as a release asset. Offline bundles are produced separately with `scripts/package-offline.sh`.

## Everyday commands

```bash
communityos info
communityos status
communityos doctor
communityos logs
communityos update
communityos backup
communityos start
communityos stop
communityos uninstall
communityos matrix invite                       # single-use Chat registration invitation
communityos matrix federation status            # mode: off | private | public
communityos matrix federation enable --private  # CommunityOS / LAN peers
communityos matrix federation enable --public   # global Matrix network
```

Chat registration is **invitation-only**: generate a token with `communityos matrix invite`, share the registration link and token, and the person creates their own Matrix account. Open registration without a token stays disabled.

Matrix **federation** is off by default. Use `--private` for trusted CommunityOS-to-CommunityOS networks, or `--public` for the global Matrix network. See [docs/MATRIX_FEDERATION.md](docs/MATRIX_FEDERATION.md).

## Services

| Address | Purpose |
|---------|---------|
| community.home.arpa | Website |
| chat.community.home.arpa | Chat |
| ai.community.home.arpa | Assistant (Open WebUI)
| 127.0.0.1:11434 (server only) | Ollama API |

Everything lives under `/opt/communityos`. Docker is an implementation detail. Images are pinned for reproducibility.

See [PRINCIPLES.md](PRINCIPLES.md).

## Offline / local-first check

With the router WAN disconnected (or WAN cable unplugged), verify local services still load:

- Website, Chat, Assistant  
- Any installed optional apps (Library, Maps, Media, Files, Streaming)

**Expected to fail offline:** Docker image pulls, internet-backed AI models, Matrix federation to the public network, external package updates.

**Expected to keep working:** LAN DNS (if enabled), HTTPS with the CommunityOS CA, local content and chat between devices on the LAN.

## Release validation (maintainers)

Before tagging a release:

- [ ] Fresh Debian 13 install  
- [ ] DNS enabled (Y) and DNS disabled (n)  
- [ ] Android + Windows clients; Firefox + Chrome  
- [ ] Certificate install from welcome page  
- [ ] Client reconnect / DHCP renewal guidance verified  
- [ ] WAN disconnected: core services still reachable on LAN  
- [ ] Optional app install/remove; Caddy reload; same CA trusted  
- [ ] `communityos doctor` healthy; no stale `/etc/hosts` surprises  

## Future install path

```bash
curl -fsSL https://raw.githubusercontent.com/networkmetatron/CommunityOS/main/install.sh | sudo bash
```

Until then, copy the release onto the server and run `sudo ./install.sh`.

## Development

The install path is `/opt/communityos`. Developers keep source in a **Git clone** (e.g. `~/communityos`) and must not extract release ZIPs over that tree.

- Workflow: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- Package a release: `./scripts/package-release.sh` → `~/releases/communityos-v*.zip`
- Test a ZIP under `~/releases/`, never by replacing the Git working tree
