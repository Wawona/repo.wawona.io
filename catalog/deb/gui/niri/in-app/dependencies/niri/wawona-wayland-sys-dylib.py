#!/usr/bin/env python3
"""Darwin: wayland-sys only dlopens libwayland-server.so.0. Also try .dylib."""
import sys
from pathlib import Path

old = '        let versions = ["libwayland-server.so.0", "libwayland-server.so"];'
new = '''        let versions = [
            "libwayland-server.0.dylib",
            "libwayland-server.dylib",
            "libwayland-server.so.0",
            "libwayland-server.so",
        ];'''
old_client = '        let versions = ["libwayland-client.so.0", "libwayland-client.so"];'
new_client = '''        let versions = [
            "libwayland-client.0.dylib",
            "libwayland-client.dylib",
            "libwayland-client.so.0",
            "libwayland-client.so",
        ];'''

changed = 0
for path in map(Path, sys.argv[1:]):
    if not path.is_file():
        continue
    text = path.read_text()
    orig = text
    if old in text:
        text = text.replace(old, new, 1)
    if old_client in text:
        text = text.replace(old_client, new_client, 1)
    if text != orig:
        path.write_text(text)
        print(f"Patched wayland-sys dylib names: {path}")
        changed += 1

if changed == 0:
    print("warning: wayland-sys .so name anchors not found", file=sys.stderr)
