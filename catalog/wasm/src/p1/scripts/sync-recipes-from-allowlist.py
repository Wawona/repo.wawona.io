#!/usr/bin/env python3
"""Ensure allowlist.toml active rows have packages/<name>/ and recipes.json rows.

Fails if an active allowlist entry lacks a recipe tree (no silent skip forever).
Blocked rows are omitted from recipes.json.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from pathlib import Path

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from allowlist_load import load_allowlist  # noqa: E402

BRAND_NAME_RE = re.compile(r"^(?:wwn-|wawona-)|(?:-wwn|-wawona)$", re.IGNORECASE)
FORGED_SCRATCH_NAMES = frozenset(
    {
        "jq",
        "gzip",
        "grep",
        "sed",
        "awk",
        "curl",
        "git",
        "tar",
        "find",
        "bash",
        "make",
        "cmake",
        "python3",
        "openssl",
        "base64",
        "cksum",
        "false",
        "uniq",
        "rev",
        "true",
    }
)


def load_native_forbid() -> set:
    path = ROOT / "scripts" / "native-all-targets.txt"
    out = set()
    for line in path.read_text().splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            out.add(s)
    return out


def main() -> int:
    check_only = "--check" in sys.argv
    al = load_allowlist(ROOT / "allowlist.toml")
    native_forbid = load_native_forbid()
    packages = []
    errors = []

    for row in al.get("packages", []):
        name = row["name"]
        status = row.get("status", "active")
        if name in native_forbid and status == "active":
            errors.append(
                f"{name}: native on all Wawona targets (uutils / "
                f"native-all-targets.txt); do not package for wasm"
            )
            continue
        if status == "blocked":
            continue
        if status != "active":
            errors.append(f"{name}: unknown status {status!r}")
            continue
        origin = row.get("origin", "scratch")
        ver = str(row["version"])
        if BRAND_NAME_RE.search(name):
            errors.append(
                f"{name}: never brand with wwn-/wawona- prefix or "
                f"-wwn/-wawona suffix (repo-wawona-io-ports)"
            )
            continue
        if origin == "port":
            upstream_ver = str(row.get("upstream_version") or "")
            if not upstream_ver:
                errors.append(
                    f"{name}: origin=port requires upstream_version "
                    f"(catalog version must be the upstream package version)"
                )
                continue
            if ver != upstream_ver:
                errors.append(
                    f"{name}: version {ver!r} must equal upstream_version "
                    f"{upstream_ver!r} (ABI is a separate field)"
                )
                continue
            # Bootstrap versions only when upstream itself publishes them.
            if ver in ("0.1.0", "0.0.1", "0.0.0") and not row.get(
                "upstream_is_bootstrap"
            ):
                errors.append(
                    f"{name}: port version {ver!r} looks invented for "
                    f"'just ported'; set upstream_is_bootstrap=true only "
                    f"when upstream's release/Cargo version is literally that"
                )
                continue
        if origin == "scratch" and name in FORGED_SCRATCH_NAMES:
            errors.append(
                f"{name}: forged upstream name with origin=scratch; "
                f"use a distinct name (never wawona-/wwn- brand) or "
                f"set origin=port with upstream_version"
            )
            continue
        src = row.get("source", f"packages/{name}")
        pkg_dir = ROOT / src
        cargo = pkg_dir / "Cargo.toml"
        bin_name = row.get("bin", name)
        main_rs = pkg_dir / "src" / "main.rs"
        bin_rs = pkg_dir / "src" / "bin" / f"{bin_name}.rs"
        if not cargo.is_file() or not (main_rs.is_file() or bin_rs.is_file()):
            errors.append(
                f"{name}: missing recipe at {src} "
                f"(need Cargo.toml + src/main.rs or src/bin/{bin_name}.rs)"
            )
            continue
        # Cargo.toml package version must match allowlist for active builds.
        cargo_ver = None
        for line in cargo.read_text().splitlines():
            if line.strip().startswith("version = "):
                cargo_ver = line.split("=", 1)[1].strip().strip('"')
                break
        if cargo_ver and cargo_ver != ver and src.startswith("packages/"):
            # cli-kit shares one crate version for multiple bins; skip strict
            # match when source is shared multicall.
            if Path(src).name != "cli-kit":
                errors.append(
                    f"{name}: Cargo.toml version {cargo_ver!r} != allowlist {ver!r}"
                )
                continue
        smoke_expect = row.get("smoke_expect")
        if smoke_expect == "":
            smoke_expect = None
        homepage = str(row.get("homepage") or "").strip()
        if origin == "port" and not homepage:
            errors.append(
                f"{name}: origin=port requires homepage (upstream project URL)"
            )
            continue
        if homepage and "wawona.io/docs" in homepage:
            errors.append(
                f"{name}: homepage must not be a blanket wawona.io/docs URL"
            )
            continue
        abi = row.get("abi", "wasi-p1")
        if abi == "wasi-p2":
            abi_target = "wasm32-wasip2"
        elif abi == "wasix":
            abi_target = "wasm32-wasix"
        else:
            abi_target = "wasm32-wasip1"
        row_out = {
            "name": name,
            "version": ver,
            "abi": abi,
            "abi_target": abi_target,
            "origin": origin,
            "kind": "cli",
            "summary": row.get("summary", name),
            "path": src,
            "bin": row.get("bin", name),
            "smoke_args": list(row.get("smoke_args") or []),
            "smoke_stdin": row.get("smoke_stdin") or None,
            "smoke_expect": smoke_expect,
            "maintainers": list(
                row.get("maintainers")
                or al.get("meta", {}).get("maintainers")
                or ["aspauldingcode"]
            ),
        }
        if homepage:
            row_out["homepage"] = homepage
        if origin == "port":
            row_out["upstream_version"] = row.get("upstream_version") or ver
            if row.get("upstream_name"):
                row_out["upstream_name"] = row["upstream_name"]
            if row.get("upstream_is_bootstrap"):
                row_out["upstream_is_bootstrap"] = True
        if row.get("smoke_exit") is not None:
            row_out["smoke_exit"] = int(row["smoke_exit"])
        packages.append(row_out)

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        return 1

    out = {"packages": packages}
    recipes_path = ROOT / "recipes.json"
    text = json.dumps(out, indent=2) + "\n"
    if check_only:
        current = recipes_path.read_text() if recipes_path.is_file() else ""
        if current != text:
            print(
                "recipes.json out of sync with allowlist.toml; "
                "run sync-recipes-from-allowlist.py",
                file=sys.stderr,
            )
            return 1
        print(f"ok: {len(packages)} active recipes match allowlist")
        return 0

    recipes_path.write_text(text)
    print(f"wrote recipes.json ({len(packages)} packages)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
