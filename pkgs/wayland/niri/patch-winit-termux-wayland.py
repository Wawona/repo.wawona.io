#!/usr/bin/env python3
"""Force winit Wayland (free_unix) on Android/Termux. Drop android-activity path.

Smithay backend_winit enables wayland + x11. On Termux we want Wayland only:
android_platform off when feature=wayland, x11_platform never on android, and
Cargo.toml free_unix deps must apply to target_os=android.
"""
import os
import pathlib
import sys


def find_winit() -> pathlib.Path:
    top = pathlib.Path(os.environ.get("NIX_BUILD_TOP", "."))
    for pattern in ("niri-android-*-vendor", "*-vendor"):
        for cand in top.glob(pattern):
            hits = list(cand.glob("winit-*/build.rs"))
            if hits:
                return hits[0].parent
    here = pathlib.Path.cwd()
    for cand in here.parent.glob("*-vendor"):
        hits = list(cand.glob("winit-*/build.rs"))
        if hits:
            return hits[0].parent
    sys.exit(f"winit vendor not found under {top} or {here.parent}")


def patch_build_rs(root: pathlib.Path) -> None:
    p = root / "build.rs"
    text = p.read_text()
    old = """        android_platform: { target_os = "android" },
        web_platform: { all(target_family = "wasm", target_os = "unknown") },
        macos_platform: { target_os = "macos" },
        ios_platform: { target_os = "ios" },
        windows_platform: { target_os = "windows" },
        apple: { any(target_os = "ios", target_os = "macos") },
        free_unix: { all(unix, not(apple), not(android_platform), not(target_os = "emscripten")) },
        redox: { target_os = "redox" },

        // Native displays.
        x11_platform: { all(feature = "x11", free_unix, not(redox)) },
        wayland_platform: { all(feature = "wayland", free_unix, not(redox)) },"""
    new = """        // Termux: nest as Wayland client when feature=wayland (not android-activity).
        android_platform: { all(target_os = "android", not(feature = "wayland")) },
        web_platform: { all(target_family = "wasm", target_os = "unknown") },
        macos_platform: { target_os = "macos" },
        ios_platform: { target_os = "ios" },
        windows_platform: { target_os = "windows" },
        apple: { any(target_os = "ios", target_os = "macos") },
        free_unix: { all(unix, not(apple), not(android_platform), not(target_os = "emscripten")) },
        redox: { target_os = "redox" },

        // Native displays. No X11 on Termux Android.
        x11_platform: { all(feature = "x11", free_unix, not(redox), not(target_os = "android")) },
        wayland_platform: { all(feature = "wayland", free_unix, not(redox)) },"""
    if old not in text:
        if "all(target_os = \"android\", not(feature = \"wayland\"))" in text:
            print("already patched", p)
            return
        sys.exit(f"winit build.rs cfg_aliases block not found in {p}")
    p.write_text(text.replace(old, new, 1))
    print("patched", p)


def patch_cargo_toml(root: pathlib.Path) -> None:
    p = root / "Cargo.toml"
    text = p.read_text()
    # free_unix deps: include android (Termux Wayland).
    needle = 'target_os = "android", target_os = "ios", target_os = "macos"'
    if needle not in text:
        if 'target_os = "ios", target_os = "macos"' in text and "android-activity" not in text:
            print("already patched", p)
            return
        sys.exit(f"winit Cargo.toml free_unix cfg needle not found in {p}")
    text2 = text.replace(needle, 'target_os = "ios", target_os = "macos"')

    # Drop android-activity / ndk deps and features that reference them.
    import re

    text2, n_feat = re.subn(
        r"\nandroid-game-activity = \[\"android-activity/game-activity\"\]\n"
        r"android-native-activity = \[\"android-activity/native-activity\"\]\n",
        "\n",
        text2,
        count=1,
    )
    text2, n_aa = re.subn(
        r"\n\[target\.'cfg\(target_os = \"android\"\)'\.dependencies\.android-activity\]\n"
        r"version = \"[^\"]+\"\n",
        "\n",
        text2,
        count=1,
    )
    text2, n_ndk = re.subn(
        r"\n\[target\.'cfg\(target_os = \"android\"\)'\.dependencies\.ndk\]\n"
        r"version = \"[^\"]+\"\n"
        r"default-features = false\n",
        "\n",
        text2,
        count=1,
    )
    # docs.rs metadata may still list android-native-activity; strip that token.
    text2 = text2.replace('"android-native-activity",\n', "")
    text2 = text2.replace('"android-native-activity"\n', "")
    # rwh_* features gate optional ndk; without the ndk dep, drop those lines.
    text2 = text2.replace('    "ndk/rwh_04",\n', "")
    text2 = text2.replace('    "ndk/rwh_05",\n', "")
    text2 = text2.replace('    "ndk/rwh_06",\n', "")
    if "android-activity" in text2 or "ndk/" in text2:
        sys.exit(
            f"android-activity/ndk still referenced in winit Cargo.toml "
            f"(feat={n_feat} aa={n_aa} ndk={n_ndk})"
        )
    p.write_text(text2)
    print("patched", p)


def patch_is_main_thread(root: pathlib.Path) -> None:
    p = root / "src" / "platform_impl" / "linux" / "mod.rs"
    text = p.read_text()
    old = '#[cfg(target_os = "linux")]\nfn is_main_thread() -> bool {'
    new = (
        '#[cfg(any(target_os = "linux", target_os = "android"))]\n'
        "fn is_main_thread() -> bool {"
    )
    if new in text:
        print("already patched is_main_thread", p)
        return
    if old not in text:
        sys.exit(f"is_main_thread linux cfg not found in {p}")
    p.write_text(text.replace(old, new, 1))
    print("patched is_main_thread", p)


def main() -> None:
    root = find_winit()
    patch_build_rs(root)
    patch_cargo_toml(root)
    patch_is_main_thread(root)


if __name__ == "__main__":
    main()

