# wwn-niri

[![CI](https://github.com/Wawona/wwn-niri/actions/workflows/ci.yml/badge.svg)](https://github.com/Wawona/wwn-niri/actions/workflows/ci.yml)

Wawona's port of **niri** — a scrollable-tiling, smithay-based Wayland
compositor — running under Wawona on the Apple ecosystem and Android, App Store
compliant. Aligns with `wwn-toolchain` like every other `wwn-*` port.

> **Status: PORTED (Phase 29, port #1).** Upstream niri v26.04 plus the Wawona
> nested-backend patch (`dependencies/niri/wawona-nested-port.patch`), built
> per-platform through `wwn-toolchain`. watchOS is excluded (stub).

## Delivery model

niri is itself a Wayland compositor. Under Wawona Mode A it runs **nested**: a
Wayland client of the Wawona compositor. On macOS Mode B it is the session
compositor (`NIRI_BACKEND=tty`) over iland userspace DRM/KMS, with
`libwayland-mac.dylib` injected. Nested Mode A still exports a child socket
through `NIRI_NESTED_WAYLAND_DISPLAY`. See
[Wawona docs: wlroots compat](https://github.com/Wawona/Wawona/blob/main/docs/2026-wlroots-compat.md)
and the platform delivery matrix.

## The nested backend patch

`dependencies/niri/src.nix` stages upstream `YaLTeR/niri` v26.04 and applies
`wawona-nested-port.patch`, `wawona-spawn-mobile.patch`,
`wawona-niri-main-catch-unwind.patch`, and `wawona-macos-drm-tty.patch`. The
nested-port patch:

- adds `src/backend/nested/` — a Wayland-client backend: the niri output is an
  `xdg_toplevel` on the host compositor, rendering is GLES over
  `EGL_KHR_platform_wayland` / `EGL_EXT_platform_wayland` (served on mobile by
  the `wwn-iland`/ANGLE EGL), and host seat input (pointer/keyboard/touch) is
  translated into niri's input pipeline;
- gates winit/pipewire as Linux-only; macOS Mode B re-enables DRM/KMS tty
  (`wawona-macos-drm-tty.patch`). iOS/Android stay nested-only. Desktop-Linux
  builds keep upstream behavior;
- adds `src/c_api.rs` (`niri_main` C ABI) plus a `staticlib` crate-type so
  mobile targets can host niri in-process;
- honors `NIRI_BACKEND=nested` (Mode A, every platform) and
  `NIRI_BACKEND=tty` on Linux and **macOS Mode B** (iland DRM/KMS). `WWN_MODEB_TTY=1`
  (Doorman login after Classic Take Over) selects tty only when there is no
  live parent Wayland socket. A compositor started inside weston or niri
  always nests on that parent (`wayland` / nested), including after Classic.
  A stale `WAYLAND_DISPLAY` without a live socket, or leftover `DISPLAY` from
  XQuartz, does not select nested on macOS. iOS/Android stay nested-only.
  `backend_winit` stays Linux-only. `niri_main` is not re-entrant.

## Per-platform artifacts & store viability

| Platform | Artifact | Launch model | Store posture |
| --- | --- | --- | --- |
| macOS | `bin/niri` + `lib/libniri.a` | app fork/execs the bundled binary | Developer ID / notarization: viable (out-of-process helper binaries are allowed) |
| iOS / iPadOS | `lib/libniri.a` (`niri_main`) | linked into the app, started on a dedicated thread in-process | App Store: viable — no JIT, no fork/exec, no dlopen of downloaded code; config KDL ships as read-only bundle data; sockets live in the app-container `XDG_RUNTIME_DIR` |
| tvOS / visionOS | same as iOS (registry reuses `ios.nix`) | in-process | same as iOS |
| Android / Wear OS | `lib/libniri_bin.so` (PIE exe, waypipe pattern) + `lib/libniri.a` | exec'd from the APK's `nativeLibraryDir` (exec-allowed) | Play Store: viable — binary ships inside the APK's jniLibs, `extractNativeLibs` exec path |
| watchOS | stub | — | excluded from the port |

GPL-3.0-or-later licensing is disclosed in the port plan / registryFragment entry;
source-offer obligations are met by this repo (patch + pinned upstream).

## Validation

- `nix build .#niri-macos` (host baseline) — binary + static lib.
- `nix build .#fuzzel-macos` — niri's default Mod+D launcher (bundled into the
  macOS app as `Contents/Resources/bin/fuzzel`).
- Wawona flake exposes `niri-android` (needs the Android SDK context) and
  bundles niri into the macOS app and Android APK.
- Capability lane: `Wawona/scripts/ci-capability-lane.sh` (Linux, optional niri
  stage) and `Wawona/scripts/niri-smoke-macos.sh` (macOS: nested boot + child
  socket + non-black frame assertion).
- Android: validated on the API 36 emulator — the Machines picker launches niri
  nested (`NIRI_BACKEND=nested`, offscreen + `wl_shm` presentation), it serves
  its own child socket (`wayland-1`), and renders its hotkey overlay. Replay:
  `Wawona/.agent-device/wawona-android-niri-smoke.ad`.
- Delivery: mandatory native bundle (not StoreKit ODR / wwn-apt).

## Convention

Follows [wwn-* porting convention](https://github.com/Wawona/Wawona/blob/main/docs/2026-wwn-porting-convention.md).
