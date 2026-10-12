#!/usr/bin/env python3
"""Stage wasmer.gtk4-hello into a repo.wawona.io checkout as a WASIX row.

Does NOT label the package as wasi-p1. Mode A wpm must keep filtering to p1.
Usage (from wasinix after nix build .#wasmer.gtk4-hello -o result-gtk4-hello):

  python3 scripts/stage-gtk4-hello-for-repo.py \\
    --wasm result-gtk4-hello/pkg/gtk4-hello/bin/gtk4-hello.wasm \\
    --wasmer-toml result-gtk4-hello/pkg/gtk4-hello/wasmer.toml \\
    --catalog /path/to/repo.wawona.io
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

NAME = "gtk4-hello"
VERSION = "0.1.0"
ENTRY = "gtk4-hello.wasm"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--wasm", type=Path, required=True)
    p.add_argument("--wasmer-toml", type=Path, default=None)
    p.add_argument("--catalog", type=Path, required=True)
    p.add_argument("--version", default=VERSION)
    args = p.parse_args()

    wasm = args.wasm.resolve()
    if not wasm.is_file():
        print(f"missing wasm: {wasm}", file=sys.stderr)
        return 1
    catalog = args.catalog.resolve()
    index_path = catalog / "wasm" / "v1" / "index.json"
    if not index_path.is_file():
        print(f"missing catalog index: {index_path}", file=sys.stderr)
        return 1

    version = args.version
    dest_dir = catalog / "wasm" / "v1" / "packages" / NAME / version
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_wasm = dest_dir / ENTRY
    shutil.copy2(wasm, dest_wasm)
    if args.wasmer_toml and args.wasmer_toml.is_file():
        shutil.copy2(args.wasmer_toml, dest_dir / "wasmer.toml")

    digest = f"sha256:{sha256_file(dest_wasm)}"
    rel_url = f"packages/{NAME}/{version}/{ENTRY}"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    row = {
        "name": NAME,
        "version": version,
        "digest": digest,
        "url": rel_url,
        "wasi": "wasix",
        "kind": "wayland",
        "summary": "Hello, Wayland World! GTK4 demo on WASIX (Wasmer + Relay)",
        "long_description": (
            "GTK4 ApplicationWindow with the title Hello, Wayland World!. "
            "Built with wasixcc against wasinix libraries.gtk4. Needs Wawona "
            "Relay host imports (wawona_wayland_*). Not store Pulley / WASI P1."
        ),
        "license": "MIT",
        "runtime": "wasmer",
        "entry": ENTRY,
        "homepage": "https://github.com/Wawona/wasinix/tree/development/pkgs/programs/gtk4-hello",
        "source": "https://github.com/Wawona/wasinix/tree/development/pkgs/programs/gtk4-hello",
        "programs": [NAME],
        "maintainers": ["aspauldingcode"],
        "platforms": [
            "macos",
            "ios",
            "ipados",
            "android",
            "linux",
        ],
        "capabilities": {
            "wayland": True,
            "filesystem": [],
            "network": False,
        },
        "origin": "scratch",
        "upstream_version": version,
        "ci": {
            "status": "unknown",
            "runtime": "wasmer",
            "checked_at": now,
            "suites": {
                "smoke": "unknown",
                "terminal": "unknown",
                "socket": "unknown",
                "wayland": "unknown",
            },
        },
    }

    index = json.loads(index_path.read_text(encoding="utf-8"))
    packages = index.setdefault("packages", [])
    packages = [pkg for pkg in packages if not (pkg.get("name") == NAME and pkg.get("version") == version)]
    packages.append(row)
    packages.sort(key=lambda pkg: (pkg.get("name", ""), pkg.get("version", "")))
    index["packages"] = packages
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")

    print(f"staged {NAME}@{version} digest={digest} -> {dest_wasm}")
    print(f"updated {index_path} (wasi=wasix)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
