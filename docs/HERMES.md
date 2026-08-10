# Hermes Agent (optional)

**Hermes Agent** (Nous Research, MIT License) is an **opt-in** CommunityOS app.
It is **not** part of the core install and is never installed by default.

| | |
|--|--|
| Upstream | https://github.com/NousResearch/hermes-agent |
| License | MIT |
| Image pin | `nousresearch/hermes-agent:v2026.8.3` (Hermes Agent v0.20.0) |
| Docs | https://hermes-agent.nousresearch.com/docs/ |

## Three-layer layout

```
Everyday users
  └─ Open WebUI          https://ai.community.home.arpa
         │  (optional connection)
         ▼
Administrators
  └─ Hermes Dashboard    https://hermes.community.home.arpa
         │                 (Hermes Basic Auth)
         ▼
     Hermes Agent container (isolated)
         ├─ API  :8642   ← Open WebUI (docker network only)
         ├─ Dash :9119   ← Caddy reverse proxy (docker network only)
         └─ Ollama       http://ollama:11434/v1  (shared models)
```

- **Open WebUI** remains the normal AI/chat interface (unchanged core).
- **Hermes Dashboard** is Hermes’s own admin UI (sessions, config, keys, optional Chat tab).
- CommunityOS does **not** fork or reimplement the dashboard.

## Ports (critical)

| Port | Role | Host/LAN publish? |
|------|------|-------------------|
| 8642 | OpenAI-compatible API | **No** |
| 9119 | Native dashboard | **No** |

Reachability:

- API: `http://hermes:8642/v1` from other containers only  
- Dashboard: `https://hermes.community.home.arpa` via Caddy → `hermes:9119`

## Authentication

Dashboard binds on `0.0.0.0:9119` inside the container so Caddy can reach it.
Upstream **requires** an auth provider on non-loopback binds.

CommunityOS configures **Hermes Basic Auth** (not CommunityOS SSO, not a Caddy bypass):

| Variable | Purpose |
|----------|---------|
| `HERMES_DASHBOARD_USER` | Dashboard username (default `admin`) |
| `HERMES_DASHBOARD_PASSWORD` | Dashboard password (seeded from `ADMIN_PASS` or random) |
| `HERMES_API_SERVER_KEY` | Separate key for Open WebUI → API |

`HERMES_DASHBOARD_INSECURE` is **not** used (deprecated upstream; must not disable auth).

Treat the dashboard as **admin-only**. It can surface API keys and drive agent
actions. Do **not** publish it to the public Internet.

## Install

```bash
sudo communityos app install hermes
```

Installer:

1. Prints capability warning  
2. Generates API key + dashboard credentials in `/opt/communityos/.env`  
3. Seeds local-first Ollama config under `data/hermes/`  
4. Starts gateway + dashboard in `communityos-hermes`  
5. Verifies `/health`, authenticated `/v1/models`, and dashboard HTTP response  

## Open WebUI → Hermes API

1. https://ai.community.home.arpa  
2. Admin → Settings → Connections → OpenAI → Add  
3. URL: `http://hermes:8642/v1`  
4. Key: `HERMES_API_SERVER_KEY`  
5. Keep Ollama for ordinary chat  

## Resources

Container soft limits (`mem_limit: 4g`, `cpus: 2.0`) bound the Hermes *process*.
**Model weights dominate** (see Ollama models). Dashboard TUI (`HERMES_DASHBOARD_TUI=1`)
adds modest overhead for the browser Chat tab.

## Offline bundles

`redistribute_offline: false` — Hermes image is **not** in CommunityOS offline
bundles. Online install pulls the pinned image; air-gapped admins `docker load`
it themselves. See `docs/OFFLINE.md`.

## Remove

```bash
sudo communityos app remove hermes
```

Removes the container (API + dashboard). Data under `data/hermes` is kept.
Ollama, Open WebUI, and Caddy remain healthy.

## Acceptance checklist

1. `sudo communityos app install hermes`  
2. API readiness (`/health` + `/v1/models`) succeeds  
3. Dashboard responds on container `:9119`  
4. No host publish of 8642 or 9119  
5. `https://hermes.community.home.arpa/` works on LAN (CommunityOS CA)  
6. Dashboard requires Hermes Basic Auth  
7. Open WebUI → `http://hermes:8642/v1` still works  
8. Ordinary Ollama chat still works  
9. `sudo communityos app remove hermes` cleans up without harming core AI  
10. Offline packager still omits the Hermes image  
