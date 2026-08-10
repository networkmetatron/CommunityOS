## Unreleased (target 1.1.4)

- Hermes optional app: native **web dashboard** via Caddy
  - `HERMES_DASHBOARD=1` in the same isolated container (no second service)
  - `https://hermes.community.home.arpa` → `hermes:9119` (no host/LAN ports)
  - Hermes Basic Auth required (`HERMES_DASHBOARD_USER` / `HERMES_DASHBOARD_PASSWORD`)
  - API key remains separate from dashboard auth; Open WebUI path unchanged
  - Install verifies API and dashboard readiness
- Offline packaging: optional third-party images are **not** redistributed by default
  - `apps/<id>.manifest.yaml` field `redistribute_offline` (default false)
  - `package-offline.sh` only saves optional images when the flag is true
  - Core `compose.yaml` images still packaged; optional app metadata always included
  - See `docs/OFFLINE.md`
- Optional **Hermes Agent** app (`communityos app install hermes`)
  - Nous Research Hermes Agent (MIT); opt-in only — never part of core install
  - Image pinned: `nousresearch/hermes-agent:v2026.8.3` (not `:latest`)
  - Isolated container; no host/LAN ports; no docker.sock; terminal local to container
  - Explicit API server config (`API_SERVER_ENABLED`, `API_SERVER_KEY`, port 8642)
  - Install verifies `/health` and `/v1/models` before success
  - Reuses existing Ollama for local inference (no duplicate model weights)
  - Open WebUI remains the user-facing AI UI (OpenAI-compatible API on :8642)
  - Container soft limits bound the agent process; **model RAM/disk dominate**
  - Clear admin warning about tool/terminal capabilities vs ordinary chat
  - See `docs/HERMES.md`

## v1.1.1

- Optional Matrix federation support (default **off**)
  - Modes: `off` | `private` | `public` via `MATRIX_FEDERATION_MODE`
  - `communityos matrix federation status`
  - `communityos matrix federation enable --private` (CommunityOS / LAN, allows `.home.arpa` + local CA)
  - `communityos matrix federation enable --public` (global Matrix; requires public DNS + trusted TLS)
  - `communityos matrix federation disable`
  - Synapse serves federation only when mode is `private` or `public`
  - Well-known matrix server/client on the Chat vhost
  - Pre-change backups under `backups/federation-*`
  - Status is read-only (never writes `.env`); reports mode
  - `start` / `restart` / `update` / `doctor` migrate missing federation keys into existing `.env`
  - `matrix_apply_synapse_federation` force-recreates Synapse so listeners pick up mode from `.env` (entrypoint source of truth)
  - See `docs/MATRIX_FEDERATION.md`
- Offline installation mode (`install.sh --offline`, `lib/offline.sh`, `scripts/package-offline.sh`)
- Offline bundle format: Debian packages + Docker images + `manifest.json` (checksums)
- Offline mode never runs `docker pull` or remote `apt update`; missing assets fail closed
- Optional apps load images from `images/optional/` when present in the bundle
- Maps app installs offline; map datasets remain operator-supplied
- `runtime/offline.env` records offline mode after install (see `runtime/offline.env.example`)
- Release policy: normal GitHub releases use **git tag + auto Source Code archives only**
  — do not publish custom `communityos-vX.Y.Z.zip` artifacts
- Offline bundles remain a separate artifact via `package-offline.sh`
- PeerTube: rename built-in root administrator to ADMIN_USER (usually admin) and set password from ADMIN_PASS
- See `docs/OFFLINE.md` and `docs/DEVELOPMENT.md`


## v1.1.0

- Maps: region download UI + `communityos maps download` (pmtiles extract, verify, Martin refresh).
- Default install includes Ollama (no models). Open WebUI uses `OLLAMA_BASE_URL=http://ollama:11434`. API on `127.0.0.1:11434`.
- One CommunityOS CA for all hostnames; app install reloads Caddy and refreshes DNS.
- Stronger DHCP/DNS lease renewal guidance (installer, welcome page, doctor, README).
- Welcome page troubleshooting + certificate-covers-all messaging.
- Offline / local-first validation notes and release checklist.
- After install (when CommunityOS DNS is enabled), restore host `/etc/resolv.conf` to `nameserver 127.0.0.1` so the server resolves `*.home.arpa`.
- Jellyfin first-run admin seeded from CommunityOS admin credentials.
- Maps empty state is fully local (no CDN); clear “add tiles” guidance.
- Nextcloud data directory permissions fixed (www-data / uid 33).
- Optional **Streaming** app (PeerTube) → https://stream.community.home.arpa
  (`communityos app install peertube`); resource note for transcoding.
- Optional **Files** app (Nextcloud) → https://files.community.home.arpa
  (`communityos app install nextcloud`); files/sharing/WebDAV focused.
- App manifests (`apps/*.manifest.yaml` + `registry.json`) as single metadata source for CLI.
- Friendly pages when optional apps are not installed (instead of bare 502).
- `communityos apps` shows installed/running/available status.
- Optional apps framework: `communityos apps` / `communityos app install|remove|restart`
- **Kiwix** offline library → https://library.community.home.arpa
- **Maps** (Martin + MapLibre) → https://maps.community.home.arpa
- **Jellyfin** media → https://media.community.home.arpa
- DNS records for library / maps / media when CommunityOS DNS is enabled
- Caddy routes for optional apps (active when app containers are running)

## v1.0.2

- Improved first-run onboarding and DNS = n guidance
- Stronger IPv4 DNS setup for image pulls
- Interactive uninstall with y/yes and accurate summary
- Preserve DB passwords on reinstall
- Hardened health checks and doctor DNS diagnostics
