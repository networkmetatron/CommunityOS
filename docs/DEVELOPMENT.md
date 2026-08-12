# CommunityOS development workflow

## Permanent Git working tree

`~/communityos` (or any clone of the repository) is the permanent Git working tree.

- Keep the `.git` directory.
- Commit and push from this tree.
- Deploy local changes to `/opt/communityos` when testing them locally.

**Never** replace this directory by extracting a release or test archive over it.

## Normal releases

The release version is stored in the repository `VERSION` file.

Release flow:

```text
Update VERSION
      ↓
Update CHANGELOG.md
      ↓
Test
      ↓
Commit and push main
      ↓
Create matching Git tag
      ↓
Push tag
      ↓
GitHub Release
```

Example:

```bash
cd ~/communityos

printf 'X.Y.Z\n' > VERSION

# Update CHANGELOG.md with the release notes.

git diff --check
git status

git add VERSION CHANGELOG.md README.md bin/communityos
git commit -m "Prepare CommunityOS X.Y.Z"
git push origin main

git tag -a vX.Y.Z -m "CommunityOS X.Y.Z"
git push origin vX.Y.Z
```

The tag must match the value in `VERSION`.

For example:

```text
VERSION = X.Y.Z
Git tag = vX.Y.Z
```

GitHub provides the normal Source Code zip/tar archives automatically from the tag.

Do not create a separate custom source archive for a normal GitHub release.

## Online installation

A normal online installation can use the repository source:

```bash
git clone --branch vX.Y.Z https://github.com/networkmetatron/CommunityOS.git
cd CommunityOS
sudo ./install.sh
```

The repository's `VERSION` file is copied into the installed CommunityOS tree.

The development Git working tree and the installed system are separate:

```text
~/communityos
    ↓
/opt/communityos
```

## Local development deployment

When testing changes from the Git working tree, copy the changed files into the installed system.

For example:

```bash
sudo cp ~/communityos/bin/communityos /opt/communityos/bin/communityos
sudo cp ~/communityos/bin/communityos /usr/local/bin/communityos
sudo cp ~/communityos/VERSION /opt/communityos/VERSION
sudo cp ~/communityos/lib/*.sh /opt/communityos/lib/
sudo cp ~/communityos/scripts/*.sh /opt/communityos/scripts/ 2>/dev/null || true
```

Copy other changed files as needed.

Then verify:

```bash
sudo communityos version
sudo communityos doctor
```

The installed `/opt/communityos/VERSION` should match the repository `VERSION`.

## Offline bundles

Offline installation is a separate product path for air-gapped servers.

Build the offline bundle on a **connected Debian 13 machine**:

```bash
sudo ./scripts/package-offline.sh
```

The packager automatically reads the release version from:

```text
VERSION
```

A version can also be supplied explicitly:

```bash
sudo ./scripts/package-offline.sh X.Y.Z
```

The bundle is written under:

```text
dist/
```

The resulting bundle has a name similar to:

```text
communityos-offline-vX.Y.Z-amd64.tar
```

Copy the bundle to the air-gapped server and install it there:

```bash
tar -xf communityos-offline-vX.Y.Z-amd64.tar
cd communityos-offline-vX.Y.Z-amd64
sudo ./install.sh
```

The offline bundle contains the Debian packages and Docker images required by the offline installation path.

See `docs/OFFLINE.md` for the offline bundle format, limitations, and validation checklist.

Offline bundles are separate from normal GitHub Source Code archives.

## Do not publish custom source ZIPs

Do not generate or upload:

```text
communityos-vX.Y.Z.zip
```

as a normal GitHub Release asset.

Normal GitHub releases use:

- Git commits
- Git tags
- GitHub's automatic Source Code archives

The offline bundle is produced separately with:

```bash
scripts/package-offline.sh
```

## Paths

| Path               | Role                                              |
| ------------------ | ------------------------------------------------- |
| `~/communityos`    | Permanent Git working tree                        |
| `~/releases/`      | Optional local test extracts or internal archives |
| `/opt/communityos` | Installed runtime, data, and configuration        |
| `dist/`            | Offline bundle output                             |

## Forbidden workflow

Do not do this:

```text
release ZIP
    ↓
rm -rf ~/communityos
    ↓
extract ZIP into ~/communityos
```

That destroys the Git working tree and can lead to unnecessary repository recovery, recommits, and force-pushes.

Keep the Git clone intact.

## Release checklist

Before creating a release tag:

```bash
git status
git diff --check
git diff
```

Verify the version:

```bash
cat VERSION
```

Verify the CLI uses the repository version when running from the repository:

```bash
./bin/communityos version
```

Verify there are no stale manually maintained release numbers in the main documentation or CLI:

```bash
grep -RInE \
  'Version 1\.|version 1\.|VERSION=1\.|v1\.' \
  README.md docs scripts bin VERSION CHANGELOG.md 2>/dev/null
```

Review the results and make sure any version references are intentional, historical changelog entries, or examples using `X.Y.Z`.

Run the relevant health and installation tests before tagging.

## Summary

| Goal                   | Method                                                   |
| ---------------------- | -------------------------------------------------------- |
| Develop                | Work in the Git clone                                    |
| Test local changes     | Deploy changed files to `/opt/communityos`               |
| Set release version    | Update `VERSION`                                         |
| Document release       | Update `CHANGELOG.md`                                    |
| Release online         | Commit → push → tag → push tag → GitHub Release          |
| Normal online install  | GitHub source/tag → `sudo ./install.sh`                  |
| Release offline        | `scripts/package-offline.sh` on connected Debian 13      |
| Install offline        | Copy bundle to air-gapped server → run offline installer |
| Source archive         | Use GitHub's automatic Source Code archives              |
| Custom release ZIP     | Do not publish                                           |
