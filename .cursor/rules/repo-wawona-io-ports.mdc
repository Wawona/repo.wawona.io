---
description: Wawona Ports naming, upstream versions, and homepage/source links for repo.wawona.io packages
alwaysApply: true
---

# Wawona Ports (catalog packages)

Almost every package on `repo.wawona.io` (wasm `/wasm/v1` and jailbreak /
Termux debs) is a **port** of existing software onto Wawona's Runtime or APT
channels. Call that surface **Wawona Ports**. The catalog is not a place to
rebrand upstream tools with Wawona vanity names or fake "just ported" versions.

## Package name

Human-facing package `name` (wasm index) and short APT `Package` / recipe
`pname` (not reverse-DNS Mode B app ids):

- **Never** prefix with `wwn-` or `wawona-`
- **Never** suffix with `-wwn` or `-wawona`
- Use the upstream project's usual name (`grep`, `sed`, `jaq`, `chess`)
- Scratch tools that are not ports use a **distinct** name that does not
  pretend to be a famous upstream (`jsonlit`, not `jq` and not `wawona-jq`)

Allowed exception: reverse-DNS first-party Mode B apps such as
`com.aspauldingcode.wawona.modeb.demo` (product identity, not a port name).

## Version

For a **port**, `version` is the **upstream software version** you ported
(the release/tag the source tree corresponds to).

- **Never** invent `0.1.0` / `0.0.1` / `0.0.0` because the port just landed
  in the Wawona catalog
- Require `upstream_version` equal to `version`. If upstream itself is still
  at a bootstrap like `0.1.0`, set `upstream_is_bootstrap = true`
- Rebuilds that do not change upstream keep tags/digests; do not bump a fake
  semver for "Wawona packaging revision" in `version`
- ABI (`wasi-p1` / `wasix`) is never encoded in `version`

Scratch (Wawona-written, `origin = scratch`) may use Wawona-owned versions.
Do not publish a from-scratch stub under an upstream name at a forged
`0.1.0` that looks like that project's release. A 30-line reimplementation
is **not** a port of GNU sed / jqlang jq. Keep it out of the catalog until
the real upstream tree is packaged.

## Links (nixpkgs-style)

Every package must publish both:

| Field | Meaning |
|-------|---------|
| `homepage` | Upstream project homepage (original software). Same role as nixpkgs `meta.homepage`. Field name is **`homepage`**, not `website`. |
| `source` | The port / packaging tree used to build this catalog row (Wawona recipe, fork commit, or wasm-packages path). |

UI shows **homepage** and **source**.

- Port: `homepage` must be the upstream project's site (e.g. `https://jqlang.github.io/jq/`). Never a blanket `wawona.io/docs/…` URL.
- Scratch (Wawona-original smoke): `homepage` is that tool's own project page (usually its GitHub tree). Still never a catch-all docs URL shared by every row.

## Hard rejects

- `wawona-grep`, `wwn-foo`, `chess-wawona`, or any `wwn-` / `wawona-` brand
  in the package name
- Port row with invented bootstrap version instead of upstream
- Port row with only a Wawona docs URL as `homepage`
- Blanket `https://wawona.io/docs/wasm/` (or similar) as `homepage` for every package
- Missing `homepage` or `source` on a catalog package
- Renaming the field to `website`
- Claiming a port (or publishing under `sed` / `jq` / `grep`) while shipping
  an unrelated stub

## How to build (two lanes)

Do not scrape nixpkgs. Do not revive `nixpkgs2wasi`. Full law:
`wawona-wasm-cli-ports`.

| Need | Repo |
|------|------|
| Store WASI P1 / Pulley | `Wawona/wasm-packages` GHA allowlist + real upstream recipe |
| Nixpkgs → WASIX / WebC | `Wawona/wasinix` (`nix build .#wasix.*` / `.#wasmer.*`) |

## Related

- Build law: `wawona-wasm-cli-ports` (skill + rule)
- Build allowlist / GHA: `Wawona/wasm-packages` (`docs/package-versioning.md`)
- WASIX: `wasinix/docs/wawona-publish.md`
- Dual catalogs: `repo-wawona-io-channels`
- Maintainers: `repo-wawona-io-maintainers`
- Skill: `repo-wawona-io-catalogs`
