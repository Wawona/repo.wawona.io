# wwn-fastfetch

[![CI](https://github.com/Wawona/wwn-fastfetch/actions/workflows/ci.yml/badge.svg)](https://github.com/Wawona/wwn-fastfetch/actions/workflows/ci.yml)

Wawona's port of [fastfetch](https://github.com/fastfetch-cli/fastfetch) — cross-compiled
with [wwn-toolchain](https://github.com/Wawona/wwn-toolchain) for **macOS, Apple mobile,
and Android**. Upstream 2.64.2 is fetched at build time and patched in-place (patch-overlay
model, same as `wwn-zsh` / `wwn-weston`).

## Wawona fork change

On macOS, when `WAYLAND_DISPLAY` is set, fastfetch reports the compositor as **Wayland**
(with optional `XDG_CURRENT_DESKTOP` pretty name) instead of only "Quartz Compositor".
This makes nested Wayland sessions inside Wawona obvious in `fastfetch` output.

Patch: `dependencies/clients/fastfetch/patches/apply-wawona-wayland-macos.py`

## App Store compliance + in-process lifecycle safety (Apple mobile)

Per [WWN-MCP knowledge on iOS shell compliance](https://github.com/Wawona/WWN-MCP/blob/main/knowledge/zsh-ios-appstore-compliance.md), Apple mobile builds run **in-process** on the zsh pthread inside the Wawona app:

- Ship as **`libfastfetch.a`** with entry point **`fastfetch_main`** (no separate Mach-O in the bundle).
- **Never** `fork`, `exec`, `posix_spawn`, `system()`, `dlopen()`, or JIT — subprocess-based module detection is stubbed (`patch-fastfetch-apple-mobile.py`).
- **IOKit/SMC stubbed** — the original `EXC_BAD_ACCESS` came from macOS IORegistry/SMC detection paths in the iOS sandbox. CPU, host, SMC-temps, and OS detection are sysctl-only.
- **No process-global side effects.** `ffStart()`'s `sigaction`/`sigprocmask` handlers and the `atexit(ffDestroyInstance)` / `atexit(restoreTerm)` registrations are guarded off; they would hijack the host app's signals or accumulate/fire against a re-inited global at app exit. Cleanup runs deterministically per invocation instead.
- **`exit()` cannot kill the app.** `fastfetch` calls `exit()` on `--help`, `--version`, bad flags, and parse errors. A `setjmp`/`longjmp` shim (`wawona_ff_inprocess.{h,c}`, force-included on mobile) redirects `exit()` back to the dispatcher so those paths return to the shell prompt. `fastfetch.c`'s entry is compiled as `fastfetch_main_impl`; the public `fastfetch_main` wraps it with the barrier + per-run reset.
- **Re-entry is safe after a crash.** The global `FFinstance` is a singleton reused on every in-process run. A fatal signal (a `SIGBUS`/`EXC_BAD_ACCESS` was observed when `parseConfigFiles` iterated a torn `configDirs` whose `.data` was a stale tag like `0x1000000005` while `.length` stayed non-zero) skips the post-run cleanup, so the wrapper also calls `ffDestroyInstance()` *before* each run. `ffDestroyInstance`/`ffInitInstance` are idempotent via a live flag, `ffPlatformInit` frees prior resources before re-init, `ffListDestroy`/`ffPlatformDestroy` treat sub-4GiB `.data` as invalid and `ffListInit` the list, and `parseConfigFiles` refuses to iterate unless `ffListDataIsValid()` passes.
- pthreads are approved, so multithreaded detection is available; the default iOS config ships `general.multithreading: false` pending on-device stress testing (re-enable once validated).

CI: `.github/scripts/verify-fastfetch-ios-patches.py` asserts all of the above (guards, exit-shim wiring, in-process lifecycle re-entry guards, banned syscalls across the authored stub set, per-platform framework tiering, Android decoupling) against pristine 2.64.2.

Android uses a normal `fastfetch` binary (fork/exec/dynamic loading allowed under Play policy, like `wwn-zsh` Android); it runs its own `patch-fastfetch-android-glob.py` and never defines `WAWONA_APPLE_MOBILE`, so none of the in-process guards apply.

### Per-platform capability matrix

Frameworks are tiered in `apple-mobile.nix` and emitted to `$out/nix-support/fastfetch-frameworks`; consumers (`fastfetch-ldflags.nix`, Wawona `xcodegen`) read that manifest instead of hardcoding.

| Capability / framework | iOS | iPadOS | tvOS | visionOS | watchOS | Android |
|---|---|---|---|---|---|---|
| CoreFoundation / Foundation | Y | Y | Y | Y | Y | n/a |
| Metal (GPU name) | Y | Y | Y | Y | **N** | n/a |
| VideoToolbox (codec) | Y | Y | Y | Y | **N** (stub) | stub |
| IOKit framework | drop | drop | drop | drop | drop | n/a |
| sysctl (OS/CPU/mem/swap/uptime/host) | Y | Y | Y | Y | Y | native |
| getifaddrs (LocalIp) | Y | Y | Y | Y | Y | native |
| Wayland WM (env-based) | Y | Y | Y | Y | Y | off |
| fork/exec/system | forbidden | forbidden | forbidden | forbidden | forbidden | allowed |

watchOS omits Metal and VideoToolbox (and IOKit headers entirely): the GPU module self-stubs, the codec detector is swapped for a no-op, and those frameworks are dropped from the emitted manifest. OS **names** are reported per platform (`iOS`/`iPadOS`/`tvOS`/`watchOS`/`visionOS`) via `TargetConditionals` + `hw.machine`; `os->id` is always `macos` so auto-detected logo matches macOS (Apple logo, not the unknown `?` art).

## Nix registry

| Attribute | Outputs |
|-----------|---------|
| `fastfetch` | `libfastfetch.a` + `fastfetch_main` (Apple mobile); `fastfetch` binary (macOS/Android); nixpkgs ref (Linux) |

## Platform coverage

| Platform | Recipe | Notes |
|----------|--------|-------|
| iOS / iPadOS / tvOS / watchOS / visionOS | `apple-mobile.nix` | In-process archive |
| macOS | `macos.nix` | Standalone binary + `libfastfetch.a` |
| Android / Wear OS | `android.nix` | NDK binary |
| Linux | `linux.nix` | nixpkgs `fastfetch` reference |

## Use in a flake

```nix
inputs.wwn-fastfetch.url = "github:Wawona/wwn-fastfetch";

registry = wwn-toolchain.lib.baseRegistry // wwn-fastfetch.registryFragment;
```

## Standalone build

```sh
nix build .#fastfetch-ios
nix build .#fastfetch-macos
```

## Layout

```
dependencies/clients/fastfetch/
  patches/           # apply at build time (not vendored upstream tree)
  apple-mobile.nix   # iOS family in-process archive
  macos.nix
  android.nix
```

## Migration note

Supersedes the org fork `github.com/Wawona/fastfetch` (dev branch with the same Wayland
WM tweak). New work lives here under the `wwn-*` patch-overlay model.

## License

MIT for Wawona packaging (see `LICENSE`). fastfetch upstream is MIT; sources are downloaded at build time.
