# Wasm channel (Mode A)

Static registry for **Wawona Runtime** packages. Consumed by `wpm` in store /
Play / macOS builds.

- Index: [`v1/index.json`](v1/index.json)
- Default client base: `https://repo.wawona.io/wasm/v1`

Jailbreak `.deb` APT and Mode B IPA live under `/jailbreak/` — never listed here.
See [Wawona wasm-package-manager.md](https://github.com/Wawona/Wawona/blob/development/docs/wasm-package-manager.md).

To publish a package, add a row to `index.json` and place the blob under
`v1/packages/<name>/<version>/component.wasm` with matching `sha256:` digest.
