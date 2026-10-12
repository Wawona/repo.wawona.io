#!/usr/bin/env python3
"""Fail if a Wayland package imports the NDK file itself.

Packages use pkgs/wayland/ndkLibs.nix. One compiler. One library set.
"""

from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1] / "pkgs" / "wayland"
bad = []
for path in root.rglob("*.nix"):
    if path.name in ("ndkLibs.nix", "TEMPLATE.nix"):
        continue
    text = path.read_text()
    if "lib/androidNdk.nix" in text or "androidNdk.nix" in text:
        bad.append(str(path.relative_to(root.parent.parent)))
if bad:
    print("raw androidNdk import (use ndkLibs.nix):")
    for item in bad:
        print(" ", item)
    sys.exit(1)
print("wayland ndk imports ok")
