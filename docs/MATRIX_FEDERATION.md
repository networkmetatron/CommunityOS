# Matrix federation (optional)

CommunityOS Chat is **invite-only and non-federating by default** (`mode: off`).

Three modes:

| Mode | Command | Use case |
|------|---------|----------|
| **off** | (default) / `disable` | Local invite-only Chat |
| **private** | `enable --private` | Trusted CommunityOS-to-CommunityOS / LAN |
| **public** | `enable --public` | Global Matrix network |

```bash
communityos matrix federation status
sudo communityos matrix federation enable --private
sudo communityos matrix federation enable --public
sudo communityos matrix federation disable
```

## Mode: off (default)

- Local users only
- Registration via `communityos matrix invite`
- Synapse serves **client** resources only
- No federation endpoint

## Mode: private

Intended for **community network** communication between trusted CommunityOS hosts
(or other Matrix servers you control on the same LAN / VPN).

- Allows `*.home.arpa` and private DNS names
- Allows CommunityOS local CA / pinned certificates
- Does **not** require public DNS or Internet-trusted TLS
- Synapse serves client **and** federation resources

### Peer requirements (private)

1. Peers can resolve `DOMAIN_CHAT` (LAN DNS, `/etc/hosts`, or CommunityOS DNS)
2. Peers trust the CommunityOS CA **or** pin the server certificate
3. Reachable endpoint (typically HTTPS on port 443 via Caddy)

Distribute the CommunityOS CA to peer hosts so federation TLS succeeds.

## Mode: public

Global federation with the wider Matrix network.

- Requires public DNS for `DOMAIN_CHAT`
- Requires Internet-trusted HTTPS (not CommunityOS `local_certs`)
- Rejects `*.home.arpa` / `*.local` names
- Synapse serves client **and** federation resources

### Peer requirements (public)

1. Public DNS for `DOMAIN_CHAT`
2. Internet-trusted certificate
3. Reachable federation endpoint (typically TCP 443)
4. Operational responsibility (uptime, abuse handling, backups)

## Status

```bash
communityos matrix federation status
```

Reports **Mode** (`off` / `private` / `public`), whether federation is active in
Synapse, DNS visibility, and TLS guidance. Status is **read-only** and never
writes configuration.

## What enable does

- Sets `MATRIX_FEDERATION_MODE` (`private` or `public`) and derived `MATRIX_FEDERATION_ENABLED`
- Snapshots `.env`, Synapse `homeserver.yaml`, and `compose.yaml` under `backups/federation-*`
- Updates Synapse listeners to include the federation resource
- Restarts Synapse / reloads Caddy

Well-known (served by Caddy on the Chat vhost):

- `/.well-known/matrix/server`
- `/.well-known/matrix/client`

## Upgrades from earlier installs

If `.env` is missing federation keys, these commands migrate safely:

- `communityos start` / `restart` / `update` / `doctor`

Migration rules:

- No keys → `MODE=off`, `ENABLED=false`
- Legacy `ENABLED=true` only → `MODE=public` (previous enable meant public)
- Legacy `ENABLED=false` only → `MODE=off`

Federation stays off until an administrator explicitly enables a mode.

## Offline / air-gapped installs

- **Private** federation can be used between offline CommunityOS hosts that share
  DNS and CA trust on the same network.
- **Public** federation requires Internet-facing DNS and certificates; do not
  enable `--public` on a purely air-gapped host.
