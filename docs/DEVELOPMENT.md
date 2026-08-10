# CommunityOS development workflow

## Permanent Git working tree

`~/communityos` (or any clone of the repository) is the **permanent Git working tree**.

- Keep the `.git` directory.
- Commit and push from this tree.
- Deploy local changes by copying into `/opt/communityos` or by using the installed CLI paths.

**Never** replace this directory by extracting a release or test archive over it.

## Normal releases (online)

```text
Git repository  →  git tag  →  GitHub Release
                     ↓
            GitHub auto Source Code archives
```

Workflow:

```bash
cd ~/communityos
# commit your work
git push origin main

# when ready to release
git tag -a v1.1.1 -m "CommunityOS 1.1.1"
git push origin v1.1.1
# Create a GitHub Release from the tag in the web UI (or gh release create)
```

GitHub attaches **Source Code** zip/tar.gz automatically. Those archives are enough for a normal (online) install:

```bash
git clone --branch v1.1.1 https://github.com/networkmetatron/CommunityOS.git
cd CommunityOS
sudo ./install.sh
```

Or:

```bash
curl -fsSL https://raw.githubusercontent.com/networkmetatron/CommunityOS/main/install.sh | sudo bash
```

### Do not publish custom source ZIPs

Do **not** generate or upload `communityos-vX.Y.Z.zip` as a normal GitHub Release asset.

`./scripts/package-release.sh` prints the tag workflow and, by default, creates **no** archive.

An optional internal test archive exists only for developer transfer:

```bash
./scripts/package-release.sh --internal-test-archive
```

That file must stay local (for example under `~/releases/`). It is not a release deliverable.

## Offline bundles (air-gapped)

Offline installation is a **separate** product path:

```bash
sudo ./scripts/package-offline.sh 1.1.1
# → dist/communityos-offline-v1.1.1-amd64.tar
```

The offline bundle includes Debian packages and Docker images. See `docs/OFFLINE.md`.

Do not replace GitHub source releases with offline bundles. Do not expect a GitHub Source Code archive to work offline.

## Paths

| Path | Role |
|------|------|
| `~/communityos` | Permanent Git working tree |
| `~/releases/` | Optional local test extracts / internal archives only |
| `/opt/communityos` | Installed runtime (production data + config) |
| `dist/` | Output of `package-offline.sh` (offline bundles) |

## Deploying local changes without packaging

```bash
sudo cp ~/communityos/bin/communityos /opt/communityos/bin/communityos
sudo cp ~/communityos/bin/communityos /usr/local/bin/communityos
sudo cp ~/communityos/lib/*.sh /opt/communityos/lib/
sudo cp ~/communityos/scripts/*.sh /opt/communityos/scripts/ 2>/dev/null || true
# copy other changed paths as needed
sudo communityos restart
```

## Forbidden workflow

```text
ZIP  →  rm -rf ~/communityos  →  unzip into ~/communityos
```

That destroys `.git` and forces `git init` / recommit / force-push. Do not do this.

## Summary

| Goal | How |
|------|-----|
| Share source online | `git push` + tag + GitHub Release (auto archives) |
| Install online | Clone/tag source or `install.sh` from GitHub raw |
| Install offline | `package-offline.sh` → USB → `sudo ./install.sh --offline …` |
| Transfer uncommitted work | Internal test archive or plain file copy — never as a published release |
