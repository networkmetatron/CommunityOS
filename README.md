# CommunityOS

**Current release:** see `VERSION`

> A private, self-hosted community server built on Debian 13.

CommunityOS provides local-first Website, Chat, AI, and optional apps from one server.

## Install

1. Install Debian 13.
2. Copy or clone CommunityOS onto the server.
3. Run:

```bash
sudo ./install.sh
```

4. Answer the setup questions.
5. If you enable CommunityOS LAN DNS, set your router's DHCP DNS server to the CommunityOS server.
6. Reconnect client devices to Wi-Fi/Ethernet so they receive the new DNS settings.
7. Open:

```text
http://community.home.arpa
```

CommunityOS normally uses `community.home.arpa` for local networks. During installation, you can optionally provide your own domain if you already have one.


8. Install the CommunityOS certificate from the welcome page.

If `community.home.arpa` does not resolve, reconnect the client to the network or renew its DHCP lease.

## Certificate

CommunityOS uses one local CA for all CommunityOS hostnames.

Install the certificate once on each device:

```text
http://community.home.arpa/ca.crt
```

After the certificate is trusted, Website, Chat, Assistant, and installed optional apps can use HTTPS without browser certificate warnings.

## AI / Ollama

CommunityOS installs Ollama but does not download model weights automatically.

List installed models:

```bash
sudo docker exec communityos-ollama ollama list
```

Install a model:

```bash
sudo docker exec -it communityos-ollama ollama pull llama3.2
```

Then open:

```text
https://ai.community.home.arpa
```

and select the model.

CPU-only systems are supported. A GPU is optional.

### Hermes Agent

Hermes is an optional tool-using agent:

```bash
sudo communityos app install hermes
```

Hermes reuses the existing CommunityOS Ollama service, so model weights are not duplicated.

The default Hermes model is:

```text
llama3.2:3b
```

This provides lightweight local Hermes inference and is suitable for modest hardware, but it does not provide reliable structured tool calling for the full agent experience.

For full terminal, file, browser, and multi-step tool workflows, use a tool-capable model appropriate for the server's hardware.

Hermes is never installed by default.

See `docs/HERMES.md` for Hermes-specific configuration and security details.

## Optional apps

List available apps:

```bash
communityos apps
```

Install an app:

```bash
sudo communityos app install kiwix
sudo communityos app install maps
sudo communityos app install jellyfin
sudo communityos app install nextcloud
sudo communityos app install peertube
sudo communityos app install hermes
```

Remove an app:

```bash
sudo communityos app remove <app>
```

Installing an app updates DNS, when CommunityOS DNS is enabled, and reloads Caddy. The same CommunityOS CA is used for optional apps.

| App | Address |
|---|---|
| Website | https://community.home.arpa |
| Chat | https://chat.community.home.arpa |
| Assistant | https://ai.community.home.arpa |
| Library | https://library.community.home.arpa |
| Maps | https://maps.community.home.arpa |
| Media | https://media.community.home.arpa |
| Files | https://files.community.home.arpa |
| Streaming | https://stream.community.home.arpa |
| Hermes | https://hermes.community.home.arpa |

## Maps

Maps uses a pinned Protomaps build.

The source can be configured in:

```text
/opt/communityos/.env
```

or:

```text
/opt/communityos/config/maps-source.env
```

Example:

```bash
PMTILES_SOURCE_URL=https://build.protomaps.com/20260807.pmtiles
```

Restart Maps after changing the source:

```bash
sudo communityos app restart maps
```

Additional `.pmtiles` or `.mbtiles` files can be placed in:

```text
/opt/communityos/data/maps/
```

See the Maps data directory README for import details.

## Offline installation

CommunityOS can be packaged for an air-gapped server.

Build the offline bundle on a connected Debian 13 machine:

```bash
sudo ./scripts/package-offline.sh
```

The packager automatically uses the version in `VERSION`.

You can also provide a version explicitly:

```bash
sudo ./scripts/package-offline.sh <version>
```

The bundle is created under:

```text
dist/
```

Copy the resulting bundle to the air-gapped server by USB or other offline media.

On the air-gapped server:

```bash
tar -xf communityos-offline-v<version>-<arch>.tar
cd communityos-offline-v<version>-<arch>
sudo ./install.sh
```

The offline bundle includes the required Debian packages and Docker images.

The offline installer does not contact Docker Hub, GHCR, or Debian mirrors.

See `docs/OFFLINE.md` for the full offline format and validation checklist.

## Everyday commands

Show the current version:

```bash
communityos version
```

Show connection information:

```bash
communityos info
```

Show platform status:

```bash
communityos status
```

Run health checks:

```bash
communityos doctor
```

View logs:

```bash
communityos logs
```

Update CommunityOS:

```bash
sudo communityos update
```

Start services:

```bash
sudo communityos start
```

Stop services:

```bash
sudo communityos stop
```

Restart services:

```bash
sudo communityos restart
```

Back up CommunityOS:

```bash
sudo communityos backup
```

## Matrix Chat

Chat registration is invitation-only.

Create an invitation:

```bash
communityos matrix invite
```

Share the registration link and token with the person joining the community.

Matrix federation is off by default.

Check federation status:

```bash
communityos matrix federation status
```

Enable private CommunityOS-to-CommunityOS federation:

```bash
sudo communityos matrix federation enable --private
```

Enable public Matrix federation:

```bash
sudo communityos matrix federation enable --public
```

See `docs/MATRIX_FEDERATION.md` for federation details.

## Local-first behavior

CommunityOS is designed to keep core services working on the LAN when the Internet is unavailable.

With the router WAN disconnected, verify:

- Website
- Chat
- Assistant
- Installed optional apps
- LAN DNS, when enabled
- HTTPS using the CommunityOS CA
- Local content and LAN chat

The following require Internet access:

- Docker image downloads
- Internet-backed AI models
- Public Matrix federation
- External package updates

## Services

Everything is managed under:

```text
/opt/communityos
```

The primary local Ollama API is:

```text
127.0.0.1:11434
```

Docker is an implementation detail of the platform.

See `PRINCIPLES.md` for the project design principles.

## Updating

For a normal connected server:

```bash
sudo communityos update
```

The `VERSION` file is the single source of truth for the CommunityOS release version.

The CLI, README, and offline packager should not contain manually maintained copies of the current release number.

## Development

The development repository should remain a Git clone, for example:

```text
~/communityos
```

The installed CommunityOS system lives at:

```text
/opt/communityos
```

Do not extract release archives over the Git working tree.

See:

- `docs/DEVELOPMENT.md`
- `docs/OFFLINE.md`
- `docs/HERMES.md`
- `docs/MATRIX_FEDERATION.md`

## Uninstall

To remove CommunityOS:

```bash
sudo communityos uninstall
```

Back up any persistent community data before uninstalling.
