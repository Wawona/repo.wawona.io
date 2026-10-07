# Wasm channel (Mode A)

Static registry for **Wawona Runtime** packages. Consumed by `wpm` in store /
Play / macOS builds.

- Human catalog: [`https://repo.wawona.io/search/?channel=wasm`](https://repo.wawona.io/search/?channel=wasm)
  (`/wasm/` HTML redirects here; same data as the index)
- Index: [`v1/index.json`](v1/index.json) (machine API; do not redirect)
- Default client base: `https://repo.wawona.io/wasm/v1`

Sileo `.deb` APT (jailbroken iOS, rootless/rootful) and Termux `.deb` APT
(sideloaded Android, not jailbreak) live under the same repo-root source. Humans
browse them at [`/search/?channel=deb`](https://repo.wawona.io/search/?channel=deb).
Never listed in this wasm index. Store `wpm` never reads APT.

ABI labels (WASI P1 / P2 / WASIX), later Wasmer/WebC publish via wasinix, and
the same-commit product gate before WASIX is treated as runnable everywhere:
[`../docs/wasm-abi.md`](../docs/wasm-abi.md).

See [Wawona wasm-package-manager.md](https://github.com/Wawona/Wawona/blob/development/docs/wasm-package-manager.md).

## Today: publish a package

**Preferred:** build on GitHub Actions in
[`Wawona/wasm-packages`](https://github.com/Wawona/wasm-packages)
(`build-wasm.yml`), then land blobs + `index.json` here via
`publish-to-repo.yml` (secret `WAWONA_REPO_TOKEN`) or a staged PR.

Manual fallback (debug only): add a row to `index.json` and place the blob under
`v1/packages/<name>/<version>/component.wasm` with matching `sha256:` digest.
**`maintainers`** is required: a list of GitHub usernames from
[`maintainers.json`](../maintainers.json). Names are resolved from GitHub, not
typed. Optional catalog fields (`kind`, `long_description`, `license`,
`homepage`, `source`, `programs`, `capabilities`, `platforms`) are ignored by
`wpm` and shown on the search page. Do not treat a laptop build as production.

## Later registry (planned)

`repo.wawona.io/wasm` becomes a curated Wasmer-compatible registry. Unit is
WebC (`.webc`) via `wasmer publish`. Orchestration is upstream wasinix (later
Wawona fork with a `wawona` publication profile). Not a Wawona nixpkgs
converter. Package names look like `wawona/wasi-p1-grep` and
`wawona/wasix-ripgrep`. `/wasm/v1` stays the live `wpm` API until that work
lands and clients are updated. Details: [`../docs/wasm-abi.md`](../docs/wasm-abi.md).
