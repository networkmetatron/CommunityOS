# CommunityOS TLS modes

**Status:** Implemented in 1.1.5  
**Default:** CommunityOS local CA (`tls internal` via Caddy)

## Modes

| `TLS_MODE` | CA | Challenge | Client trust |
|---|---|---|---|
| `local` (default) | CommunityOS local CA | none | install `ca.crt` once |
| `acme_dns01` | **Let's Encrypt** | ACME **DNS-01** | public browsers (no CA install) |

ACME is the protocol; **Let's Encrypt** is the public certificate authority.

## Local CA

```bash
sudo communityos tls set local
```

- Caddy image: `caddy:2.9.1-alpine`
- Caddyfile: `tls internal` + `local_certs`
- Serve `http://DOMAIN_BASE/ca.crt` for device trust
- Works offline / private LAN / `.home.arpa`

## Public ACME DNS-01 (Let's Encrypt)

```bash
# 1. Secrets (root-only)
sudo cp /opt/communityos/secrets/acme.env.example /opt/communityos/secrets/acme.env
sudo chmod 600 /opt/communityos/secrets/acme.env
# edit: ACME_EMAIL, ACME_DNS_PROVIDER=cloudflare, CLOUDFLARE_API_TOKEN=...

# 2. Enable mode (switches Caddy image + Caddyfile, recreates gateway)
sudo communityos tls set acme_dns01
```

Requirements:

1. Custom / public `DOMAIN_BASE` (not `.home.arpa`)
2. DNS zone at a provider with a Caddy DNS plugin image (Cloudflare supported by default)
3. API token that can create `_acme-challenge` TXT records
4. Host can reach the DNS provider API and Let's Encrypt (outbound HTTPS)

LAN-only inbound is fine: DNS-01 does not require ports 80/443 from the Internet.

ACME zone discovery uses explicit public resolvers (`1.1.1.1`, `1.0.0.1`, `8.8.8.8`)
so Docker's internal resolver cannot SERVFAIL `_acme-challenge` lookups.

Production Let's Encrypt is the default. Staging is only used when `ACME_STAGING=1`.
Persisted staging ACME state is cleared when switching to production mode.


### Certificate shape

With `ACME_WILDCARD=1` (default) and `auto_https prefer_wildcard`, Caddy prefers:

```text
DOMAIN_BASE
*.DOMAIN_BASE
```

Optional apps under the same base are covered without re-issuing when the wildcard is active.

### Caddy image

| Mode | Image |
|---|---|
| local | `caddy:2.9.1-alpine` |
| acme_dns01 + cloudflare | `iarekylew00t/caddy-cloudflare:2.9.1` |

Override with `CADDY_IMAGE=...` in `secrets/acme.env` for other DNS plugins.

### Fallback

If ACME is misconfigured or fails, Caddy keeps serving any prior certificates in `caddy_data`. The site stays reachable; `communityos doctor` reports ACME/secret problems.

## CLI

```text
communityos tls status
sudo communityos tls set local|acme_dns01
sudo communityos tls prewarm
```

## Doctor

Reports: TLS mode, CA/issuer, secrets presence, certificate notAfter/issuer, CommunityOS DNS verification for enabled hosts only.

## Security

- Store tokens only in `/opt/communityos/secrets/acme.env` (mode 0600, root-only)
- Scope DNS tokens to TXT on `_acme-challenge` / Zone DNS Edit for one zone
- Public cert ≠ public service; firewall and Caddy still control reachability
