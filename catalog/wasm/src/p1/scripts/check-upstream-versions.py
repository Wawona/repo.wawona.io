#!/usr/bin/env python3
"""Identify allowlist packages that are out of date vs catalog and upstream.

Writes JSON report (stdout or --out PATH). Used by nightly selection and bump.

version_policy:
  local       — version owned in allowlist/Cargo.toml; only catalog lag
  cargo-deps  — crates.io newer than Cargo.lock for direct deps
  crates-io   — crates.io max_version for upstream_crate > allowlist version
  git-tag     — newest matching git tag > allowlist version
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from allowlist_load import load_allowlist  # noqa: E402
from semver_util import bump_patch, cmp_semver  # noqa: E402

CATALOG_URL = "https://repo.wawona.io/wasm/v1/index.json"
CRATES_API = "https://crates.io/api/v1/crates/{name}"
UA = "Wawona-wasm-packages-freshness/1.0 (https://github.com/Wawona/wasm-packages)"


def http_json(url: str) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.loads(resp.read().decode())


def fetch_catalog() -> Dict[str, str]:
    try:
        data = http_json(CATALOG_URL)
    except Exception as e:  # noqa: BLE001
        print(f"warn: catalog fetch failed ({e})", file=sys.stderr)
        return {}
    return {p["name"]: str(p["version"]) for p in data.get("packages", [])}


def crates_max_version(name: str) -> Optional[str]:
    try:
        data = http_json(CRATES_API.format(name=name))
        return str(data["crate"]["max_version"])
    except Exception as e:  # noqa: BLE001
        print(f"warn: crates.io {name}: {e}", file=sys.stderr)
        return None


def git_latest_tag(repo: str, prefix: str = "v") -> Optional[str]:
    """repo is owner/name or https://github.com/owner/name.git"""
    m = re.search(r"github\.com[:/]([^/]+)/([^/.]+)", repo)
    if not m:
        print(f"warn: unsupported git upstream {repo!r}", file=sys.stderr)
        return None
    owner, name = m.group(1), m.group(2)
    url = f"https://api.github.com/repos/{owner}/{name}/tags?per_page=30"
    try:
        tags = http_json(url)
    except Exception as e:  # noqa: BLE001
        print(f"warn: git tags {owner}/{name}: {e}", file=sys.stderr)
        return None
    best = None
    for t in tags:
        tag = t.get("name", "")
        if prefix and not tag.startswith(prefix) and not re.match(r"^\d", tag):
            continue
        ver = tag[len(prefix) :] if prefix and tag.startswith(prefix) else tag.lstrip("v")
        if best is None or cmp_semver(ver, best) > 0:
            best = ver
    return best


def parse_cargo_deps(cargo_toml: pathlib.Path) -> List[Tuple[str, str]]:
    """Return [(crate, version_req)] from [dependencies] only."""
    if not cargo_toml.is_file():
        return []
    text = cargo_toml.read_text()
    in_deps = False
    out: List[Tuple[str, str]] = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            in_deps = s == "[dependencies]"
            continue
        if not in_deps or not s or s.startswith("#") or "=" not in s:
            continue
        key, val = s.split("=", 1)
        crate = key.strip()
        val = val.strip()
        if val.startswith("{"):
            m = re.search(r'version\s*=\s*"([^"]+)"', val)
            if not m:
                continue
            out.append((crate, m.group(1)))
        elif val.startswith('"'):
            out.append((crate, val.strip('"')))
    return out


def lock_versions(lock_path: pathlib.Path) -> Dict[str, str]:
    if not lock_path.is_file():
        return {}
    versions: Dict[str, str] = {}
    name = None
    for line in lock_path.read_text().splitlines():
        s = line.strip()
        if s.startswith("name = "):
            name = s.split("=", 1)[1].strip().strip('"')
        elif s.startswith("version = ") and name:
            versions[name] = s.split("=", 1)[1].strip().strip('"')
            name = None
    return versions


def cargo_toml_version(cargo_toml: pathlib.Path) -> Optional[str]:
    if not cargo_toml.is_file():
        return None
    for line in cargo_toml.read_text().splitlines():
        if line.strip().startswith("version = "):
            return line.split("=", 1)[1].strip().strip('"')
    return None


def check_package(row: Dict[str, Any], catalog: Dict[str, str]) -> Dict[str, Any]:
    name = row["name"]
    status = row.get("status", "active")
    policy = row.get("version_policy", "local")
    allow_ver = str(row.get("version", "0.0.0"))
    catalog_ver = catalog.get(name)
    src = row.get("source", f"packages/{name}")
    pkg_dir = ROOT / src
    cargo = pkg_dir / "Cargo.toml"
    lock = pkg_dir / "Cargo.lock"

    reasons: List[str] = []
    upstream_latest: Optional[str] = None
    dep_updates: List[Dict[str, str]] = []

    if status == "blocked":
        return {
            "name": name,
            "status": status,
            "version_policy": policy,
            "allowlist_version": allow_ver,
            "catalog_version": catalog_ver,
            "upstream_latest": None,
            "outdated": False,
            "needs_bump": False,
            "needs_rebuild": False,
            "reasons": ["blocked"],
            "suggested_version": allow_ver,
            "dep_updates": [],
        }

    if catalog_ver is None:
        reasons.append("missing_from_catalog")
    elif catalog_ver != allow_ver:
        reasons.append("catalog_behind_allowlist")

    if policy == "local":
        toml_ver = cargo_toml_version(cargo)
        if toml_ver and toml_ver != allow_ver:
            reasons.append("cargo_toml_mismatch")
        upstream_latest = allow_ver

    elif policy == "cargo-deps":
        locked = lock_versions(lock)
        for crate, _req in parse_cargo_deps(cargo):
            latest = crates_max_version(crate)
            locked_ver = locked.get(crate)
            if latest and locked_ver and cmp_semver(latest, locked_ver) > 0:
                dep_updates.append(
                    {"crate": crate, "locked": locked_ver, "latest": latest}
                )
        if dep_updates:
            reasons.append("cargo_deps_outdated")
            upstream_latest = dep_updates[0]["latest"]
        else:
            upstream_latest = allow_ver

    elif policy == "crates-io":
        crate = row.get("upstream_crate") or name
        upstream_latest = crates_max_version(str(crate))
        if upstream_latest and cmp_semver(upstream_latest, allow_ver) > 0:
            reasons.append("upstream_ahead_of_allowlist")

    elif policy == "git-tag":
        git = row.get("upstream_git") or ""
        prefix = str(row.get("upstream_tag_prefix", "v"))
        upstream_latest = git_latest_tag(str(git), prefix=prefix)
        if upstream_latest and cmp_semver(upstream_latest, allow_ver) > 0:
            reasons.append("upstream_ahead_of_allowlist")

    else:
        reasons.append(f"unknown_version_policy:{policy}")

    needs_bump = any(
        r in ("cargo_deps_outdated", "upstream_ahead_of_allowlist", "cargo_toml_mismatch")
        for r in reasons
    )
    needs_rebuild = bool(reasons) and "blocked" not in reasons

    if policy == "crates-io" and "upstream_ahead_of_allowlist" in reasons and upstream_latest:
        suggested = upstream_latest
    elif needs_bump:
        suggested = bump_patch(allow_ver)
    else:
        suggested = allow_ver

    return {
        "name": name,
        "status": status,
        "version_policy": policy,
        "allowlist_version": allow_ver,
        "catalog_version": catalog_ver,
        "upstream_latest": upstream_latest,
        "outdated": needs_rebuild,
        "needs_bump": needs_bump,
        "needs_rebuild": needs_rebuild,
        "reasons": reasons,
        "suggested_version": suggested,
        "dep_updates": dep_updates,
        "source": src,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=pathlib.Path, default=None)
    ap.add_argument("--json-stdout", action="store_true")
    args = ap.parse_args()

    al = load_allowlist(ROOT / "allowlist.toml")
    catalog = fetch_catalog()
    packages = [check_package(row, catalog) for row in al.get("packages", [])]
    outdated = [p for p in packages if p["needs_rebuild"] and p["status"] == "active"]
    bumps = [p for p in packages if p["needs_bump"] and p["status"] == "active"]

    report = {
        "catalog_url": CATALOG_URL,
        "packages": packages,
        "outdated_names": [p["name"] for p in outdated],
        "bump_names": [p["name"] for p in bumps],
        "summary": {
            "active": sum(1 for p in packages if p["status"] == "active"),
            "outdated": len(outdated),
            "needs_bump": len(bumps),
        },
    }

    text = json.dumps(report, indent=2) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text)
        print(f"wrote {args.out}", file=sys.stderr)
    if args.json_stdout or not args.out:
        sys.stdout.write(text)
    else:
        print(
            f"outdated={report['outdated_names']} bumps={report['bump_names']}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
