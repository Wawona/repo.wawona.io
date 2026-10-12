#!/usr/bin/env python3
"""Drop winit x11 feature from smithay (Termux Wayland nest only)."""
import os
import pathlib
import sys


def find_toml() -> pathlib.Path:
    top = pathlib.Path(os.environ.get("NIX_BUILD_TOP", "."))
    # Prefer smithay-0.* only (not smithay-client-toolkit / smithay-drm-extras).
    for pattern in ("niri-android-*-vendor", "*-vendor"):
        for cand in top.glob(pattern):
            hits = sorted(cand.glob("smithay-0.*/Cargo.toml"))
            if hits:
                return hits[0]
    here = pathlib.Path.cwd()
    for cand in here.parent.glob("*-vendor"):
        hits = sorted(cand.glob("smithay-0.*/Cargo.toml"))
        if hits:
            return hits[0]
    sys.exit("smithay-0.*/Cargo.toml not found")


def main() -> None:
    p = find_toml()
    text = p.read_text()
    old = 'features = ["wayland", "wayland-dlopen", "x11", "rwh_06"]'
    new = 'features = ["wayland", "wayland-dlopen", "rwh_06"]'
    if new in text and old not in text:
        print("already patched", p)
        return
    if old not in text:
        sys.exit(f"smithay winit features line not found in {p}")
    p.write_text(text.replace(old, new, 1))
    print("patched", p)


if __name__ == "__main__":
    main()
