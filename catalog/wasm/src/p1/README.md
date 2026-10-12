# wasm-packages

GitHub Actions builds curated **WASI P1** (and later WASIX) packages for
[`repo.wawona.io/wasm/v1`](https://repo.wawona.io/wasm/v1). Production builds
run on **`ubuntu-24.04` runners**, not developer laptops.

ABI and phase order: [`repo.wawona.io/docs/wasm-abi.md`](https://github.com/Wawona/repo.wawona.io/blob/development/docs/wasm-abi.md).

## CLI coverage

## ArtCraft Crafting Apps

Source map:
[`docs/artcraft-crafting-apps.md`](docs/artcraft-crafting-apps.md).
Nothing ArtCraft is published on `/wasm/v1` until an egui→Wayland wasip1 path
exists (`effectcraft-expr` was pulled). Browser `xtask web` is not `/wasm/v1`.
Site: [wawona.io ArtCraft wasm](https://wawona.io/docs/contributor/artcraft-wasm/).

## Versioning

Catalog `version` is the **software package version**, not WASI P1/P2/WASIX.
See [`docs/package-versioning.md`](docs/package-versioning.md).

- `origin = "port"`: `version` = upstream release; `homepage` = upstream project
  URL (nixpkgs-style). Never invent `0.1.0` for "just ported". Never point
  every row at `wawona.io/docs/wasm/`.
- `origin = "scratch"`: distinct unbranded Wawona smoke name. Never forge
  `jq`/`sed`/`grep`. Stubs stay blocked until a real upstream tree is packaged.


If a CLI already ships **native on every Wawona target** (uutils safe subset;
`scripts/native-all-targets.txt`), do **not** package it for `/wasm/v1`.
`sync-recipes-from-allowlist.py` fails closed. Publish prunes those names
from the live index.


| Lane | Where | What |
|------|--------|------|
| Store **WASI P1** | This repo (`cli-kit` + small ports) | Common Unix CLIs for `wpm` / Pulley |
| **WASIX** / WebC | [`Wawona/wasinix`](https://github.com/Wawona/wasinix) | Nix-ported Linux tools (grep/tar/git/…); Wasmer |

Blocked allowlist rows with `build = "wasinix"` are the WASIX queue. Not empty
stubs in `/wasm/v1`. See `wasinix/docs/wawona-publish.md`.

## Growth loop (automatic)

```text
allowlist.toml (curated; never nixpkgs mirror)
  → nightly / push GHA build + Wasmtime smoke (P1/P2 pass/fail JSON)
  → stage merges `ci` into catalog (green/red dots on /search/?channel=wasm)
  → combine artifact wasm-out
  → publish-to-repo.yml (workflow_run) stages wasm/v1
  → direct push to repo.wawona.io development as wawona-wasm-bot
  → Pages deploys development → live /wasm/v1
```

| Control | Meaning |
|---------|---------|
| `allowlist.toml` | Only listed active packages build. `status = blocked` skips (e.g. curl). |
| `version_policy` | How runners detect updates: `local`, `cargo-deps`, `crates-io`, `git-tag`. |
| `meta.max_new_per_nightly` | Cap new/stale builds per nightly (default 3). |
| `WAWONA_REPO_TOKEN` | Repo secret: PAT or GitHub App token with `contents: write` on `Wawona/repo.wawona.io` and `actions: read` on this repo. Prefer machine user / App `wawona-wasm-bot` over a personal PAT. |

### Updatable sources (runner freshness)

Nightly (and `workflow_dispatch` with `packages=nightly`) runs
`scripts/check-upstream-versions.py` against live `/wasm/v1/index.json` and
upstream registries, then `bump-outdated.py` when needed:

| `version_policy` | Out of date when |
|------------------|------------------|
| `local` | Catalog missing or behind allowlist version |
| `cargo-deps` | crates.io has a newer version than `Cargo.lock` for a direct dep |
| `crates-io` | `upstream_crate` max_version newer than allowlist version |
| `git-tag` | Newest `upstream_git` tag newer than allowlist version |

Report artifact: `upstream-report`. Bumps commit back to `development` as
`wawona-wasm-bot` after a green build (`[skip ci]`). Still allowlist-only:
never auto-mirror nixpkgs.

```bash
# Set once (fine-grained PAT or App install token):
gh secret set WAWONA_REPO_TOKEN --repo Wawona/wasm-packages
```

After editing `allowlist.toml`, regenerate recipes:

```bash
python3 scripts/sync-recipes-from-allowlist.py
python3 scripts/sync-recipes-from-allowlist.py --check
```

## Layout

```text
allowlist.toml           Curated P1 set + blocked rows
packages/<name>/         Rust wasm32-wasip1 sources
recipes.json             Generated from allowlist (active only)
scripts/                 build, smoke, select, stage, sync
.github/workflows/       build-wasm.yml, publish-to-repo.yml
```

## CI

| Workflow | What |
|----------|------|
| `build-wasm.yml` | Matrix build + smoke; cron `0 6 * * *` (stale vs catalog); artifact `wasm-out` |
| `publish-to-repo.yml` | On green build (development): stage + push catalog (or `open_pr=true`) |

```bash
gh workflow run build-wasm.yml --repo Wawona/wasm-packages
```

## Local (optional debug only)

```bash
rustup target add wasm32-wasip1
./scripts/build-package.sh jq
./scripts/smoke-package.sh jq
```

Do not treat local builds as the publish source of truth.
