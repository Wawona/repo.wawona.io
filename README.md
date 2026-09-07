# Wawona Repo

Hosted at [repo.wawona.io](https://repo.wawona.io)

## Channels (do not mix)

| Path / artifact | Audience | Contents |
|-----------------|----------|----------|
| **`/wasm/`** | App Store, Play, macOS (Mode A) | WASI `.wasm` packages for **Wawona Runtime**. Human search catalog plus `v1/index.json` for `wpm`. |
| **`/jailbreak/`** APT / Sileo | Jailbroken iOS | **`.deb` tweaks** (Desktop, LockScreen, Wawona Swinging Bridge Mode B, …) |
| **Mode B IPA** (automated) | Jailbroken iOS via Sileo | Full **Wawona Mode B** app: **JIT** VMs + containers, unsandboxed shell / host APT. **Never** submitted to App Store. |

### Mode A (store-safe)

Store / Play Wawona may download Wasm from `/wasm/` only. VMs/containers in the
**App Store IPA** use jitless UTM-SE-class engines only (see Wawona docs).

### Mode B (jailbreak)

1. Keep Procursus/Sileo **`.deb`** packaging ([docs/packaging.md](docs/packaging.md)).
2. **CI must build and publish a Mode B Wawona iOS IPA** for Sileo so jailbroken
   users get JIT UTM containers/VMs and jailbreak APT tooling.
3. Store-shaped binaries must never embed Mode B engines or link this IPA’s JIT path.

Plan: [mode-a-b.md](https://github.com/Wawona/Wawona/blob/development/docs/mode-a-b.md),
[wasm-package-manager.md](https://github.com/Wawona/Wawona/blob/development/docs/wasm-package-manager.md).

## Historical note

Older docs said App Store builds must never touch this host. That was when the
host was APT-only. **`/wasm/`** is the store-safe exception; jailbreak APT and
Mode B IPA remain off-limits inside store binaries.
