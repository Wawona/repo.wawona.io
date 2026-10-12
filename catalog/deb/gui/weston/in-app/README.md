# wwn-weston

[![CI](https://github.com/Wawona/wwn-weston/actions/workflows/ci.yml/badge.svg)](https://github.com/Wawona/wwn-weston/actions/workflows/ci.yml)

All [Weston](https://gitlab.freedesktop.org/wayland/weston) ports for Wawona live in this repo — compositors, toytoolkit demo clients, terminal, shell clients, and `weston-simple-shm`. Upstream Weston 13.0.0 is fetched at build time and patched in-place (patch-overlay model); nothing vendors the full Weston tree.

Targets: **iOS, iPadOS, tvOS, watchOS, visionOS, macOS, Android (Wear OS), and Linux** (reference / host bundles). Apple mobile and Android ship Weston as **in-process static archives** (`*_main` entry points). macOS and Linux use conventional Meson / binary builds where appropriate.

Built with [wwn-toolchain](https://github.com/Wawona/wwn-toolchain). The iland DRM/GL compositor path consumes [wwn-iland](https://github.com/Wawona/wwn-iland) udev/gbm shims.

## Nix registry

`registryFragment` exposes four attributes. Each maps to per-platform Nix recipes under `dependencies/`:

| Attribute | Role |
|-----------|------|
| `weston` | Toytoolkit (`clients/window.c`) plus in-process demo and shell clients |
| `weston-compositor` | Nested Wayland / headless compositor (`weston_compositor_main`) |
| `weston-compositor-drm` | Nested compositor with iland DRM/KMS + GL renderer |
| `weston-simple-shm` | Minimal SHM demo client (`weston_simple_shm_main`) as a standalone archive |

## `weston` — clients and static archives

Cross-compiled for Apple mobile and Android (`dependencies/clients/weston/ios.nix`, `android.nix`, …). Each client `main` is renamed to `<name>_main` (hyphens → underscores) so Wawona can launch clients inside the app process.

**Output archives (Apple mobile; Android is similar):**

| Archive | Contents |
|---------|----------|
| `libweston-13.a` | Shared toytoolkit + cairo demo clients + `weston_simple_shm_main` (iOS family) |
| `libweston-terminal.a` | Real `clients/terminal.c` (drives bundled zsh via `wawona-pty`) |
| `libweston-desktop-13.a` | `weston-desktop-shell` client (`weston_desktop_shell_main`) |
| `libweston-keyboard.a` | `weston-keyboard` client (`weston_keyboard_main`) |

**Demo clients in `libweston-13.a`** (each exposes `<client>_main`, e.g. `flower_main`):

`flower`, `clickdot`, `smoke`, `eventdemo`, `resizor`, `cliptest`, `transformed`, `stacking`, `dnd`, `image`, `scaler`, `editor`, `constraints`

**GL client (optional):** `simple-egl` → `simple_egl_main` when `enableGlClients = true` (iland + ANGLE stack must link; see `.#weston-ios-gl` in the Wawona flake).

**macOS** (`macos-drm-shared.nix`, flake key `weston.macos`): Meson shared build with Darwin shims plus `drm-backend.so` / `gl-renderer.so` for Mode B fork/exec (DRM/EGL via `dynamic_lookup`; no Mode A/B LC_LOAD). Bare `weston` defaults to DRM/KMS (iland). `WWN_MODEB_TTY` also ignores a nested `--backend=wayland` from host CLI wrappers. Nested Mode A still passes `--backend=wayland`. Legacy client-only recipe kept as `macos.nix`.

**Linux** (`linux.nix`): Host/reference Weston via the shared Linux platform dispatcher.

Upstream Weston ships additional clients (DMABUF, IVI, calibrators, `simple-damage`, `simple-touch`, …). Those are intentionally **not** ported here; this repo covers the cairo/SHM demo set, terminal, keyboard, desktop-shell, compositor, and simple-shm that Wawona actually launches.

## `weston-compositor` and `weston-compositor-drm`

Nested compositor archives for in-process nesting inside Wawona (`libweston-compositor-13.a`, entry `weston_compositor_main`).

| Recipe | Backend |
|--------|---------|
| `compositor-ios.nix`, `compositor-tvos.nix`, … | Wayland + headless, Pixman renderer |
| `compositor-ios-drm.nix` | iland DRM/KMS + GL renderer (`wwn-iland` shims) |
| `compositor-android.nix` | Wayland + headless for Android NDK |

Shared Apple-mobile logic: `compositor-apple-mobile.nix`.

## `weston-simple-shm`

Standalone `libweston_simple_shm.a` (or macOS/Linux binaries) from `dependencies/libs/weston-simple-shm/`. On Apple mobile, `weston_simple_shm_main` is also compiled into `libweston-13.a` when building `weston`; the separate archive remains for targets that link SHM without the full toytoolkit closure.

`patched-src.nix` produces the patched `simple-shm.c` tree (used by Wawona’s Android Gradle build when toytoolkit is not linked).

## Platform coverage

| Platform | `weston` | `weston-compositor` | `weston-compositor-drm` | `weston-simple-shm` |
|----------|----------|---------------------|-------------------------|---------------------|
| iOS | `ios.nix` | `compositor-ios.nix` | `compositor-ios-drm.nix` | `libs/weston-simple-shm/ios.nix` |
| iPadOS | `ios.nix` | `compositor-ios.nix` | `compositor-ios-drm.nix` | `ios.nix` |
| tvOS | `tvos.nix` → `ios.nix` | `compositor-tvos.nix` | — | `tvos.nix` |
| watchOS | `watchos.nix` → `ios.nix` | `compositor-watchos.nix` | — | `watchos.nix` |
| visionOS | `visionos.nix` → `ios.nix` | `compositor-visionos.nix` | — | `visionos.nix` |
| macOS | `macos-drm-shared.nix` | — | (shared `drm-backend.so` in `weston`) | `macos.nix` |
| Android | `android.nix` | `compositor-android.nix` | — | — (use `patched-src.nix` / iOS-style embed in app) |
| Wear OS | `wearos.nix` → `android.nix` | — | — | — |
| Linux | `linux.nix` | — | — | `linux.nix` (standalone binary) |

tvOS and watchOS use the same in-process weston-desktop-shell as iOS (panel,
background, launchers). fork/exec is compiled out; launchers go through
`wwn_launch_panel_client`. Desktop-shell on Android is currently a link stub;
keyboard is not built on Android yet.

## Patches and CI

- `dependencies/clients/weston/terminal-patches/` — terminal and toytoolkit CSD patches applied at build time
- `.github/scripts/verify-weston-ios-patches.py` — anchor checks so upstream drift fails CI instead of silently breaking patches
- `dependencies/generators/weston-toytoolkit-ldflags.nix`, `weston-compositor-ldflags.nix` — link contracts for Xcode / Gradle

## Layout

```
dependencies/
├── clients/weston/          # weston, compositor, compositor-drm recipes + mobile glue
├── libs/weston-simple-shm/  # standalone SHM client + patched-src
└── generators/              # ldflags helpers for app linkers
```

## Use in a flake

```nix
inputs.wwn-weston.url = "github:Wawona/wwn-weston";

registry = wwn-toolchain.lib.baseRegistry
  // wwn-iland.registryFragment
  // wwn-weston.registryFragment;

extraArgs = { ilandSrc = wwn-iland; };   # compositor-drm copies iland udev/gbm shims
```

Consumer examples (Wawona flake): `weston-ios`, `weston-ios-gl`, `weston-compositor-ios`, `weston-compositor-ios-drm`, `weston-android`, `weston-compositor-android`, `weston-macos`, `weston-simple-shm` per platform.

## Standalone build (this flake)

```sh
nix build .#weston-ios
nix build .#weston-macos
nix build .#weston-compositor-ios
nix build .#weston-simple-shm-ios
```

On a machine with the full Wawona flake input, also:

```sh
nix build .#weston-ios-gl
nix build .#weston-compositor-ios-drm
nix build .#weston-android
nix build .#weston-compositor-android
```

## License

MIT for the Wawona Nix packaging and patches (see `LICENSE`). Weston upstream is MIT; its source is downloaded at build time.
