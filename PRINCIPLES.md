# CommunityOS Principles

1. **One-command installation.**  
   A clean Debian host becomes a community server with a single command.

2. **Debian remains the host OS.**  
   CommunityOS is an appliance layer, not a custom distribution.

3. **Docker is an implementation detail.**  
   Users interact with CommunityOS, not containers or Compose files.

4. **No manual configuration files for normal users.**  
   The installer asks questions; the system writes configuration.

5. **HTTPS by default.**  
   Local trust is established once; every service is secure afterward.

6. **Local-first and privacy-first.**  
   Data stays on hardware the community controls.

7. **Safe upgrades.**  
   Updates improve the platform without throwing away data or trust.

8. **Reliable backups.**  
   Backup and restore are first-class operations, not afterthoughts.

9. **Sensible defaults with optional customization.**  
   Works out of the box; advanced changes remain possible, not required.

10. **Keep it simple.**  
    Prefer fewer moving parts, clearer language, and calmer software.

11. **Configuration vs generated state.**  
    `.env` is configuration (source of truth). Files under `runtime/` are generated
    from that configuration and must not be hand-edited. After changing `.env`
    (for example `SERVER_IP`), run `sudo communityos restart` so generated state
    is rewritten. Core and optional service names stay in sync that way.

---

When proposing a change, ask: does this support these principles, or weaken them?

11. Offline is real offline — air-gapped install uses a self-contained bundle; no silent network fallback.

11. **Configuration vs generated state.** `.env` is the source of truth; files under `runtime/` are generated. Change `.env`, then `communityos restart`.

12. **Online vs offline artifacts.** Normal releases are Git tags and GitHub Source Code archives. Offline/air-gapped installs use a separate self-contained bundle (`package-offline.sh`). Do not publish custom source ZIPs as release assets.
