#!/usr/bin/env python3
"""Select packages for the GHA matrix (all / named / nightly freshness).

Nightly uses check-upstream-versions.py:
  - missing from catalog / catalog behind allowlist
  - upstream ahead (crates-io / git-tag)
  - cargo-deps outdated vs crates.io
Cap: meta.max_new_per_nightly (default 3). Prefer never-published, then bumps.
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from allowlist_load import load_allowlist  # noqa: E402


def load_recipes():
    return json.loads((ROOT / "recipes.json").read_text())["packages"]


def matrix(names):
    return json.dumps({"include": [{"package": n} for n in names]})


def run_freshness_report(path: pathlib.Path, reuse: bool = True) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    if reuse and path.is_file():
        return json.loads(path.read_text())
    subprocess.check_call(
        [
            sys.executable,
            str(ROOT / "scripts" / "check-upstream-versions.py"),
            "--out",
            str(path),
        ]
    )
    return json.loads(path.read_text())


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    recipes = load_recipes()
    by_name = {p["name"]: p for p in recipes}

    if mode == "nightly":
        report_path = ROOT / "out" / "upstream-report.json"
        report = run_freshness_report(report_path)
        meta = load_allowlist(ROOT / "allowlist.toml").get("meta", {})
        cap = int(meta.get("max_new_per_nightly", 3))
        stale = list(report.get("outdated_names") or [])
        # Prefer packages that need a source bump, then catalog-only lag.
        bump_set = set(report.get("bump_names") or [])
        never = []
        bumps = []
        for name in stale:
            row = next((p for p in report["packages"] if p["name"] == name), None)
            if not row:
                continue
            if row.get("catalog_version") is None:
                never.append(name)
            elif name in bump_set or "catalog_behind_allowlist" in row.get("reasons", []):
                bumps.append(name)
            else:
                bumps.append(name)
        # de-dupe preserve order
        ordered = []
        for n in never + bumps:
            if n not in ordered:
                ordered.append(n)
        selected = ordered[:cap]
        if not selected:
            selected = ["hello-wasi"] if "hello-wasi" in by_name else list(by_name)[:1]
        print(matrix(selected))
        print(
            f"nightly selected {selected} (stale={stale}, bumps={sorted(bump_set)}, cap={cap})",
            file=sys.stderr,
        )
        return 0

    if mode == "all" or mode == "":
        names = [p["name"] for p in recipes]
        print(matrix(names))
        return 0

    wanted = {n.strip() for n in mode.split(",") if n.strip()}
    names = [n for n in by_name if n in wanted]
    missing = wanted - set(names)
    if missing:
        print(f"unknown packages: {sorted(missing)}", file=sys.stderr)
        return 1
    print(matrix(names))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
