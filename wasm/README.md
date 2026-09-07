# Wasm channel (Mode A)

Static registry for **Wawona Runtime** packages. Consumed by `wpm` in store /
Play / macOS builds.

- Human catalog: [`https://repo.wawona.io/wasm/`](https://repo.wawona.io/wasm/)
  (search, filters, per-package detail; same data as the index)
- Index: [`v1/index.json`](v1/index.json)
- Default client base: `https://repo.wawona.io/wasm/v1`

Jailbreak `.deb` APT and Mode B IPA live under `/jailbreak/` and the [Sileo
landing page](../). Never listed here.

See [Wawona wasm-package-manager.md](https://github.com/Wawona/Wawona/blob/development/docs/wasm-package-manager.md).

To publish a package, add a row to `index.json` and place the blob under
`v1/packages/<name>/<version>/component.wasm` with matching `sha256:` digest.
**`maintainers`** is required: a list of GitHub usernames from
[`maintainers.json`](../maintainers.json). Names are resolved from GitHub, not
typed. Optional catalog fields (`kind`, `long_description`, `license`,
`homepage`, `source`, `programs`, `capabilities`, `platforms`) are ignored by
`wpm` and shown on the search page.
