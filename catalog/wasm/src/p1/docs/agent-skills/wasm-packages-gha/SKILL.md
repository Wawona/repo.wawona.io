---
name: wasm-packages-gha
description: Build store WASI P1 packages for repo.wawona.io/wasm on GitHub Actions. Use for allowlist, recipes, nightly build, auto-publish. For nixpkgs→WASIX use wasinix + skill wawona-wasm-cli-ports.
---

# wasm-packages GHA builds (store WASI P1)

Production path: **GitHub Actions** on `ubuntu-24.04`. Not a laptop.

This repo is the **store / Pulley P1** lane only. Nixpkgs → WASIX lives in
`Wawona/wasinix`. Decision table: skill/rule `wawona-wasm-cli-ports`.

| Piece | Path |
|-------|------|
| Allowlist | `allowlist.toml` (curated; `blocked` skips; no nixpkgs mirror) |
| Freshness | `version_policy` + `check-upstream-versions.py` / `bump-outdated.py` |
| Recipes | `recipes.json` via `scripts/sync-recipes-from-allowlist.py` + `packages/<name>/` |
| Build | `build-wasm.yml` (push, dispatch, cron; nightly freshness; `wasm-out`) |
| Publish | `publish-to-repo.yml` (`workflow_run` + dispatch; `WAWONA_REPO_TOKEN`) |
| Catalog | `repo.wawona.io` `/wasm/v1` on **development** (Pages deploys that branch) |

Ports need real upstream trees, `upstream_version`, and `homepage` (upstream
URL). Stubs named `jq`/`grep`/`sed` stay **blocked**.

```bash
gh secret set WAWONA_REPO_TOKEN --repo Wawona/wasm-packages   # bot/App preferred
python3 scripts/sync-recipes-from-allowlist.py
gh workflow run build-wasm.yml --repo Wawona/wasm-packages
```

Nightly selects packages missing/stale vs live `index.json`, capped by
`meta.max_new_per_nightly`. Green build auto-pushes catalog as `wawona-wasm-bot`
unless `open_pr=true`.

ABI / phase order: `repo.wawona.io/docs/wasm-abi.md`.
Org catalogs skill: `repo-wawona-io-catalogs`.

## Never

- Publish laptop-built `.wasm` as production
- Revive `nixpkgs2wasi` / auto-mirror nixpkgs
- Claim WASIX runs on store Pulley (WASIX = wasinix lane)
- Put WASIX build recipes only in this repo (use `wasinix`)
- Put build recipes only in `repo.wawona.io` (catalog host stays thin)
- Ship empty stubs for `blocked` allowlist rows
- Forge upstream names at invented `0.1.0`

Never package names in `scripts/native-all-targets.txt` (native uutils on all targets).
