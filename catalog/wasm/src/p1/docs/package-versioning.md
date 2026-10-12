# Wasm package versioning

Catalog `version` is the **software package version**, not the WASI/WASIX ABI.

| Field | Meaning |
|-------|---------|
| `version` | Upstream (or Wawona-original) **package** version users install |
| `abi` / `wasi` | `wasi-p1` \| `wasi-p2` \| `wasix` (execute surface). Never put this in `version` |
| `origin` | `port` = build of an existing project; `scratch` = Wawona-written tool |
| `homepage` | Upstream project URL (nixpkgs `meta.homepage`). Field name is **`homepage`**, not `website`. |
| `source` | Port / packaging tree used to build this row |

## Rules

1. **`origin = "port"`:** `version` must equal the upstream project's release
   version (semver/tag as they publish). Set `upstream_version` to the same
   string. Example: packaging `jaq` 2.3.0 → catalog name `jaq`, version
   `2.3.0`, `homepage = https://github.com/01mf02/jaq`. Rebuilds that do not
   change upstream may use a separate `revision` / digest only; do not invent
   `0.1.0` because the port just landed on Wawona. If upstream itself is still
   at `0.1.0`, set `upstream_is_bootstrap = true`.
2. **`origin = "scratch"`:** Wawona owns the name and version. Use a
   **distinct** name (`hello-wasi`, not `jq` and not `wawona-jq`). Never brand
   with `wawona-` / `wwn-` prefixes or `-wawona` / `-wwn` suffixes. Never use a
   forged upstream name (`jq`, `gzip`, `grep`) with a fake `0.1.0`.
3. A short reimplementation is **not** a port. Do not publish stubs under
   `sed` / `jq` / `grep` until the real upstream tree is packaged.
4. Native-first still applies (`native-all-targets.txt`). Do not wasm-package
   tools that already ship native on every target.
5. Build lane: store P1 in this repo; nixpkgs→WASIX in `wasinix`. Rule/skill
   `wawona-wasm-cli-ports`.
6. Catalog host rule: `repo.wawona.io` `repo-wawona-io-ports`.

## Hard rejects

- `version` encoding ABI (`1.0.0-p1`, `wasix-3`, …)
- Port version invented for "just ported"
- Catalog name `jq` at `0.1.0` for a serde_json toy that is not jqlang/jq
- `wawona-*` / `wwn-*` package names (or `-wawona` / `-wwn` suffixes)
- Field renamed to `website`
- Blanket `https://wawona.io/docs/wasm/` as every package's `homepage`
- Claiming a port while shipping a from-scratch stub
