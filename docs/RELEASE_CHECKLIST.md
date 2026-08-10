# CommunityOS release checklist

## Before tagging

- [ ] Fresh Debian 13 install succeeds end-to-end (online path)
- [ ] `communityos doctor` reports healthy core services
- [ ] Website, Chat, Assistant reachable over HTTPS after CA install
- [ ] Optional apps install/remove cleanly (`nextcloud`, `peertube`, `hermes`, …)
- [ ] Hermes not present on clean install; core Ollama + Open WebUI unchanged when Hermes absent
- [ ] Hermes install warns about tools; remove leaves Ollama/Open WebUI intact
- [ ] `communityos backup` / restore smoke-tested
- [ ] Image pins in `compose.yaml` / app overlays reviewed
- [ ] No secrets, passwords, or host-specific `.env` in the tree
- [ ] `VERSION` and `CHANGELOG.md` updated

## Online release (normal)

```text
commit → push → git tag vX.Y.Z → push tag → GitHub Release
```

- [ ] Tag matches `VERSION`
- [ ] GitHub Release created from the tag
- [ ] **Only** GitHub auto Source Code archives are attached (no custom `communityos-vX.Y.Z.zip`)
- [ ] README install instructions still point at GitHub (clone / raw `install.sh`)

`./scripts/package-release.sh` documents this workflow and does **not** publish a custom source ZIP.

## Offline release (separate)

- [ ] On a networked builder: `sudo ./scripts/package-offline.sh X.Y.Z`
- [ ] Bundle verifies: `manifest.json`, packages, core + optional images
- [ ] Air-gapped install test: `sudo ./install.sh --offline /path/to/bundle`
- [ ] Offline bundle omits optional third-party images unless `redistribute_offline: true`
- [ ] Optional app install offline still works when admin-supplied images are present in `images/optional/`
- [ ] Publish/store the offline `.tar` **outside** the normal source release if needed

See `docs/OFFLINE.md`.

## Working tree rules

- `~/communityos` (or any clone) is the **Git working tree**. Never delete `.git`.
- Never extract any ZIP or offline bundle over the permanent Git tree.
- Internal test archives (if used) extract under `~/releases/` only.
