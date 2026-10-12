# wwn-neovim

[![CI](https://github.com/Wawona/wwn-neovim/actions/workflows/ci.yml/badge.svg)](https://github.com/Wawona/wwn-neovim/actions/workflows/ci.yml)

Wawona's [Neovim](https://neovim.io) port, cross-compiled with
[wwn-toolchain](https://github.com/Wawona/wwn-toolchain) for **macOS, Apple mobile,
and Android**. Upstream **0.10.4** is fetched at build time (patch-overlay model,
same as `wwn-zsh` / `wwn-fastfetch`).

## App Store compliance (Apple mobile)

Per [WWN-MCP knowledge on iOS shell compliance](../WWN-MCP/knowledge/zsh-ios-appstore-compliance.md):

- Ship as **`libwawona-neovim.a`** with entry point **`wawona_nvim_main`** (no separate Mach-O).
- **`USE_LUAJIT=OFF`** — PUC Lua 5.1 only (no JIT / `MAP_JIT`).
- **Never** `fork`, `exec`, `posix_spawn`, or `system()` on the editor path — spawn stubs in
  `patch-libuv-spawn.py` + `patch-neovim-apple-mobile.py`.
- CI: `.github/scripts/verify-neovim-ios-patches.py`.

Android uses a normal `nvim` binary (fork allowed, like `wwn-zsh` Android).

## Nix registry

| Attribute | Outputs |
|-----------|---------|
| `neovim` | `libwawona-neovim.a` + runtime (Apple mobile); `nvim` binary (macOS/Android) |
| `neovim-rootfs` | Bundled runtime prefix (Apple mobile only) |

## Use in a flake

```nix
inputs.wwn-neovim.url = "github:Wawona/wwn-neovim";

registry = wwn-toolchain.lib.baseRegistry // wwn-neovim.registryFragment;
```

## Standalone build

```sh
nix build .#neovim-macos
nix build .#neovim-ios
nix build .#neovim-android
```

## Dependencies

Neovim's bundled deps (libuv, msgpack, unibilium, libvterm, tree-sitter, Lua/LuaJIT or PUC Lua)
are built via upstream `make deps` inside each platform recipe. Apple mobile uses PUC Lua;
macOS/Android use LuaJIT.

## License

MIT for Wawona packaging (see `LICENSE`). Neovim is Apache-2.0 / Vim; sources are downloaded at build time.
