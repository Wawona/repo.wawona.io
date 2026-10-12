#!/usr/bin/env python3
"""Apply version bumps from an upstream-report.json (or regenerate it).

For cargo-deps: cargo update + bump package patch in Cargo.toml + allowlist.
For crates-io / git-tag: set allowlist + Cargo.toml to suggested_version.
Then sync recipes.json.
"""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from allowlist_load import load_allowlist  # noqa: E402


def set_cargo_version(cargo_toml: pathlib.Path, version: str) -> None:
    text = cargo_toml.read_text()
    new, n = re.subn(
        r'(?m)^version = "[^"]*"',
        f'version = "{version}"',
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit(f"could not set version in {cargo_toml}")
    cargo_toml.write_text(new)


def set_allowlist_version(name: str, version: str) -> None:
    path = ROOT / "allowlist.toml"
    lines = path.read_text().splitlines(keepends=True)
    out = []
    in_pkg = False
    current_name = None
    for line in lines:
        raw = line.split("#", 1)[0]
        if raw.strip() == "[[packages]]":
            in_pkg = True
            current_name = None
            out.append(line)
            continue
        if in_pkg and raw.strip().startswith("name ="):
            current_name = raw.split("=", 1)[1].strip().strip('"')
            out.append(line)
            continue
        if (
            in_pkg
            and current_name == name
            and raw.strip().startswith("version =")
        ):
            indent = line[: len(line) - len(line.lstrip())]
            out.append(f'{indent}version = "{version}"\n')
            continue
        out.append(line)
    path.write_text("".join(out))


def main() -> int:
    report_path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "out" / "upstream-report.json"
    if not report_path.is_file():
        subprocess.check_call(
            [
                sys.executable,
                str(ROOT / "scripts" / "check-upstream-versions.py"),
                "--out",
                str(report_path),
            ]
        )
    report = json.loads(report_path.read_text())
    al = {p["name"]: p for p in load_allowlist(ROOT / "allowlist.toml").get("packages", [])}
    bumped = []

    for row in report.get("packages", []):
        if not row.get("needs_bump"):
            continue
        name = row["name"]
        meta = al.get(name)
        if not meta or meta.get("status") == "blocked":
            continue
        new_ver = row["suggested_version"]
        src = meta.get("source", f"packages/{name}")
        pkg_dir = ROOT / src
        cargo = pkg_dir / "Cargo.toml"
        if not cargo.is_file():
            print(f"skip {name}: no Cargo.toml", file=sys.stderr)
            continue
        print(f"bump {name}: {row['allowlist_version']} -> {new_ver} ({row['version_policy']})")
        set_cargo_version(cargo, new_ver)
        set_allowlist_version(name, new_ver)
        if row["version_policy"] == "cargo-deps":
            subprocess.check_call(
                ["cargo", "update"],
                cwd=pkg_dir,
            )
        bumped.append(name)

    if not bumped:
        print("no bumps needed")
        return 0

    subprocess.check_call(
        [sys.executable, str(ROOT / "scripts" / "sync-recipes-from-allowlist.py")]
    )
    # Refresh report after bump
    subprocess.check_call(
        [
            sys.executable,
            str(ROOT / "scripts" / "check-upstream-versions.py"),
            "--out",
            str(report_path),
        ]
    )
    print(f"bumped: {bumped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
