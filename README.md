# nemo-devkit

Tooling around a patched build of [Nemo](https://github.com/linuxmint/nemo)
(the Cinnamon file manager): build, patch, install and keep the local copy
up to date with upstream.

The patches themselves live in a separate fork:
**<https://github.com/dronov-dmitry/nemo>**. This repository only carries the
scripts and patch files — it does not duplicate the Nemo sources.

Video: [https://youtu.be/_4FF53jmb7s](https://youtu.be/_4FF53jmb7s)

English · [Русский](README.ru.md)

## Contents

| Path                               | Purpose                                                                          |
| ---------------------------------- | -------------------------------------------------------------------------------- |
| `nemo-update.sh`                   | Main script: sync fork + upstream, apply the patch, carry over the local functionality, build, install, restart Nemo |
| `build_and_install.sh`             | Build + install from the local copy of the sources, re-synced with the merged tree on every run |
| `git-download.sh`                  | Interactive shallow clone of a whole repo or a single folder                     |
| `opencode-session.sh`              | Open `opencode` in a maximized terminal, offer a Nemo restart afterwards         |
| `patches/`                         | Ready-made `.patch` files (for `git am` or for review in a PR)                   |
| `docs/PR_PROMPT.md`                | Write-up of one of the proposed fixes (root-cause analysis + fix)                |
| `examples/run_install.example.txt` | Example command for installing locally built `.deb` packages                     |

## Requirements

- Debian/Ubuntu-based system with `apt`
- `git`, `meson`, `ninja-build`, `sudo` for installation
- A fork of `linuxmint/nemo` with your patch branch

## Quick start

```bash
# 1. Point the scripts at your fork and branch
export NEMO_FORK=https://github.com/dronov-dmitry/nemo.git
export NEMO_BRANCH=dnd-keep-drop-target-visible

# 2. Check the state of the installed Nemo (0 = fine, 1 = update needed)
./nemo-update.sh --check

# 3. Update, apply the patch, build and install
./nemo-update.sh --yes

# 4. Or do it step by step, interactively
./nemo-update.sh
```

On the first run `nemo-update.sh` clones the fork into `~/nemo-patched-src`
and keeps it there; afterwards it just fetches and rebases the patch on the
latest upstream master.

### Local functionality

Extra functionality you build on top of Nemo does not have to be pushed
anywhere: just leave it as uncommitted changes in the local copy
`~/nemo-build`. `nemo-update.sh` extracts them as a patch, applies it on top
of the new version (three-way merge) and commits the result, then syncs the
local copy with the merged tree — so an update never drops your work, and a
later `build_and_install.sh` run builds exactly the same merged tree.

## Environment variables

| Variable              | Default                                            | Used by                | Meaning                                     |
| --------------------- | -------------------------------------------------- | ---------------------- | ------------------------------------------- |
| `NEMO_FORK`           | `https://github.com/dronov-dmitry/nemo.git`        | all                    | Your fork                                   |
| `NEMO_BRANCH`         | `dnd-keep-drop-target-visible`                     | `nemo-update.sh`       | Branch carrying the patch                   |
| `NEMO_UPSTREAM`       | `https://github.com/linuxmint/nemo.git`            | `nemo-update.sh`       | Upstream repo                               |
| `NEMO_SRC`            | `~/nemo-patched-src`                               | both                   | Sources sandbox (the merged tree)           |
| `NEMO_LOCAL_SRC`      | `~/nemo-build`                                     | both                   | Local copy built from; its uncommitted changes are the "local functionality" |
| `NEMO_LOCAL_PATCH`    | `~/nemo-local-features.patch`                      | `nemo-update.sh`       | Where the extracted local changes are saved |
| `NEMO_FEATURE_SYMBOL` | `nemo_window_dnd_source_press`                     | both                   | Symbol used to prove the patch is installed |
| `NEMO_INSTALLED`      | `/usr/bin/nemo`                                    | `nemo-update.sh`       | Binary to check                             |
| `NEMO_RAW`            | raw `meson.build` of linuxmint/nemo                | `nemo-update.sh`       | Where to read the upstream version from     |

`build_and_install.sh` builds strictly from `NEMO_LOCAL_SRC` (by default on the
system disk), creating it from `NEMO_SRC` on the first run and re-syncing on
every run. This avoids building directly on a flaky external drive that can
fail with I/O errors. Uncommitted changes in the local copy are stashed and
restored around the sync — they are never lost; run `nemo-update.sh` to merge
them into the new version.

## Applying patches manually

The files in `patches/` are the same commits as the fork branch, exported with
`git format-patch`. To apply them on top of a fresh upstream checkout:

```bash
git clone https://github.com/linuxmint/nemo.git
cd nemo
git am /path/to/nemo-devkit/patches/*.patch
```

To send them upstream as a pull request, push the branch to your fork and open
a PR against `linuxmint/nemo`.

## License

The scripts here are provided as-is, under the same spirit as the patches they
carry. The patches themselves are contributions to Nemo
(GPL-2.0-or-later, see `linuxmint/nemo`).
