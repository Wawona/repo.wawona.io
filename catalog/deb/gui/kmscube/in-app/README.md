# wwn-kmscube

[![CI](https://github.com/Wawona/wwn-kmscube/actions/workflows/ci.yml/badge.svg)](https://github.com/Wawona/wwn-kmscube/actions/workflows/ci.yml)

Wawona's native graphics acceptance clients: the canonical
[kmscube](https://gitlab.freedesktop.org/mesa/kmscube) GBM/EGL/DRM GL client and
an iland-portable adaptation of [krh/vkcube](https://github.com/krh/vkcube).
Both are static, in-process clients on Apple mobile and Android.

KMS/GBM/DRM and all GPU providers come from
[wwn-iland](https://github.com/Wawona/wwn-iland). `vkcube` calls Vulkan
directly: MoltenVK or KosmicKrisp to Metal on Apple, and the system or bundled
SwiftShader ICD on Android. Android's client-local dispatch keeps SwiftShader
separate from the system loader used for host ANativeWindow WSI. It never opens
KGSL directly or introduces an EGL, Zink, or Venus translation chain.

## Outputs

| Artifact | Description |
|----------|-------------|
| `libkmscube.a` | In-process archive; `main` renamed to `kmscube_main` |
| `kmscube` (macOS) | Standalone binary linked against iland + ANGLE |
| `include/kmscube.h` | `kmscube_main` declaration for app linkers |
| `libvkcube.a` | Native Vulkan renderer; `main` renamed to `vkcube_main` |
| `include/vkcube.h` | `vkcube_main` declaration for app linkers |
| `libgbm_es2_demo.a` | In-process archive; CLI `main` renamed (never LC_MAIN) |

## Nix registry

`registryFragment` exposes:

| Attribute | Role |
|-----------|------|
| `kmscube` | Primary entry — all platform recipes |
| `vkcube` | Vulkan acceptance client for macOS, iOS/iPadOS/visionOS, Android/Wear OS |
| `iland-gl-clients` | Legacy alias (same recipes); kept for flakes that still use that name |

## Platform coverage

| Platform | Recipe | Notes |
|----------|--------|-------|
| iOS / iPadOS | `ios.nix` → `apple-mobile.nix` | `libkmscube.a` only |
| tvOS / watchOS / visionOS | re-export `ios.nix` | same archive model |
| macOS | `macos.nix` | binary + `libkmscube.a` |
| Android / Wear OS | `android.nix` | `libkmscube.a`; requires iland on Android |
| Linux | `linux.nix` | nixpkgs `kmscube` reference binary |

`vkcube` is available on macOS, iOS, iPadOS, visionOS, Android, and Wear OS.
Its tvOS and watchOS registry variants are explicitly `null`: those products
must not bundle Vulkan.

Sources live in `upstream/` (vendored from the iland kmscube test tree; `kmscube_compat.h` handles Apple EGL display typing).

F7/F8/F9 Mode B overlay clients (kmscube, gbm-es2-demo, vkcube-kms) and the
Wayland opengl-cube / vkcube clients draw a corner status hub: client name, fps, kms/drm/gbm,
OpenGL vs Vulkan, and the live backend (ANGLE, MoltenVK, KosmicKrisp).

## Use in a flake

```nix
inputs.wwn-kmscube.url = "github:Wawona/wwn-kmscube";

registry = wwn-toolchain.lib.baseRegistry
  // wwn-iland.registryFragment
  // wwn-kmscube.registryFragment;
```

Link helper for Xcode app targets: `dependencies/generators/kmscube-ldflags.nix` (iland + ANGLE + `-force_load libkmscube.a`).

## Standalone build

```sh
nix build .#kmscube-ios
nix build .#kmscube-macos
nix build .#vkcube-ios
nix build .#vkcube-macos
nix build .#vkcube-android
```

With Wawona's flake: `kmscube-ios`, `kmscube-macos`, `kmscube-android` (when iland Android is available).

## Layout

```
upstream/                    # kmscube sources
upstream/vkcube/             # krh/vkcube-derived portable KMS renderer + pinned SPIR-V
dependencies/clients/kmscube/  # per-platform Nix recipes
dependencies/generators/       # kmscube-ldflags.nix
```

## License

MIT for Wawona packaging (see `LICENSE`). kmscube upstream is MIT; sources are vendored in `upstream/`.
