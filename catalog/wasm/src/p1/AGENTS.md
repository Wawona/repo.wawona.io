# AGENTS.md: wasm-packages

Builds for `repo.wawona.io/wasm/v1` run on **GitHub Actions**
(`ubuntu-24.04`). Do not treat local `cargo` as the publish path.

- Recipes: `recipes.json` + `packages/<name>/`
- Skill: `docs/agent-skills/wasm-packages-gha/SKILL.md`
- ABI rules: `repo.wawona.io/docs/wasm-abi.md`
- Catalog host: `repo.wawona.io` (thin; no build recipes here)
- Org: FUNDING + Discord push webhook like other `Wawona/*` repos
- Never revive `nixpkgs2wasi`
- WASIX / Wasmer lane is later; this repo ships P1 first
- Proven: `hello-wasi` 0.1.2, `wasi-true` 0.1.0 via `build-wasm.yml`

Agents: skill/rule `wawona-wasm-cli-ports` (store P1 here; WASIX in wasinix).
