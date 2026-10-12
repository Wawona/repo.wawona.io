#!/usr/bin/env python3
"""Merge built out/ into a checkout of repo.wawona.io wasm/v1 (+ index.json).

Copies new blobs when digests change. Always merges CI smoke status from
out/<name>/<ver>/smoke-result.json into each index row (Hydra-style verified
dot on /search/?channel=wasm).
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]

CI_SUITE_KEYS = ("smoke", "terminal", "socket", "wayland")


def load_native_forbid() -> set:
    path = ROOT / "scripts" / "native-all-targets.txt"
    out = set()
    for line in path.read_text().splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            out.add(s)
    return out


def load_prune_names() -> set:
    """Names to remove from the live index (forged stubs, native twins)."""
    sys.path.insert(0, str(ROOT / "scripts"))
    from allowlist_load import load_allowlist  # noqa: E402

    names = set(load_native_forbid())
    al = load_allowlist(ROOT / "allowlist.toml")
    for row in al.get("packages", []):
        if row.get("status") != "blocked":
            continue
        if str(row.get("version")) in ("0.0.0", "0.1.0") or row.get("build") == "none":
            names.add(row["name"])
    return names


def abi_to_wasi(abi: str) -> str:
    if abi == "wasi-p2":
        return "p2"
    if abi == "wasix":
        return "wasix"
    return "p1"


def runtime_for_abi(abi: str) -> str:
    if abi == "wasix":
        return "wasmer"
    return "wasmtime"


def empty_suites() -> dict:
    return {k: "unknown" for k in CI_SUITE_KEYS}


def ci_from_smoke(smoke_path: pathlib.Path, abi: str) -> dict:
    """Build index `ci` object from a per-package smoke-result.json."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    suites = empty_suites()
    if not smoke_path.is_file():
        return {
            "status": "unknown",
            "runtime": runtime_for_abi(abi),
            "checked_at": None,
            "suites": suites,
        }
    try:
        raw = json.loads(smoke_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {
            "status": "fail",
            "runtime": runtime_for_abi(abi),
            "checked_at": now,
            "suites": {**suites, "smoke": "fail"},
            "detail": "unreadable smoke-result.json",
        }
    smoke_status = raw.get("status") or "fail"
    if smoke_status not in ("pass", "fail", "skip"):
        smoke_status = "fail"
    # skip → unknown overall (not verified working)
    if smoke_status == "skip":
        overall = "unknown"
        suites["smoke"] = "unknown"
    else:
        overall = smoke_status
        suites["smoke"] = smoke_status
    out = {
        "status": overall,
        "runtime": raw.get("runtime") or runtime_for_abi(abi),
        "checked_at": now,
        "suites": suites,
    }
    if raw.get("detail"):
        out["detail"] = str(raw["detail"])[:200]
    return out


def write_ci_summary(dest_root: pathlib.Path, packages: list[dict]) -> None:
    """Machine-readable Hydra-style summary next to the index."""
    results = []
    for pkg in packages:
        ci = pkg.get("ci") or {}
        results.append(
            {
                "name": pkg.get("name"),
                "version": pkg.get("version"),
                "status": ci.get("status") or "unknown",
                "runtime": ci.get("runtime"),
                "checked_at": ci.get("checked_at"),
                "suites": ci.get("suites") or empty_suites(),
            }
        )
    passed = sum(1 for r in results if r["status"] == "pass")
    failed = sum(1 for r in results if r["status"] == "fail")
    unknown = sum(1 for r in results if r["status"] not in ("pass", "fail"))
    summary = {
        "schema": 1,
        "description": "Wasm package CI smoke status (Hydra-style). UI dots on /search/?channel=wasm.",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "runtime_policy": {
            "wasi-p1": "wasmtime",
            "wasi-p2": "wasmtime",
            "wasix": "wasmer",
        },
        "suites": list(CI_SUITE_KEYS),
        "total": len(results),
        "passed": passed,
        "failed": failed,
        "unknown": unknown,
        "packages": results,
    }
    path = dest_root / "wasm" / "v1" / "ci.json"
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {path.relative_to(dest_root)} ({passed} pass / {failed} fail / {unknown} unknown)")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: stage-for-repo.py <repo.wawona.io checkout>", file=sys.stderr)
        return 2
    dest_root = pathlib.Path(sys.argv[1]).resolve()
    index_path = dest_root / "wasm" / "v1" / "index.json"
    recipes = json.loads((ROOT / "recipes.json").read_text())
    index = json.loads(index_path.read_text())
    by_name = {p["name"]: p for p in index["packages"]}
    changed = 0
    prune = load_prune_names()
    for name in list(by_name):
        if name in prune:
            print(f"prune {name}", file=sys.stderr)
            del by_name[name]
            changed += 1

    recipe_by_name = {m["name"]: m for m in recipes["packages"]}

    for meta in recipes["packages"]:
        if meta["name"] in prune:
            print(f"skip pruned {meta['name']}", file=sys.stderr)
            continue
        name = meta["name"]
        ver = meta["version"]
        abi = meta.get("abi") or "wasi-p1"
        src = ROOT / "out" / name / ver / "component.wasm"
        smoke_path = ROOT / "out" / name / ver / "smoke-result.json"
        if not src.is_file():
            print(f"skip {name}: no build at {src}", file=sys.stderr)
            continue
        digest = "sha256:" + hashlib.sha256(src.read_bytes()).hexdigest()
        existing = by_name.get(name)
        ci = ci_from_smoke(smoke_path, abi)
        blob_changed = not (
            existing
            and existing.get("version") == ver
            and existing.get("digest") == digest
        )

        if blob_changed:
            pkg_dir = dest_root / "wasm" / "v1" / "packages" / name / ver
            pkg_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, pkg_dir / "component.wasm")
            origin = meta.get("origin", "scratch")
            src_path = meta.get("path") or f"packages/{name}"
            source_url = (
                meta.get("source_url")
                or f"https://github.com/Wawona/wasm-packages/tree/development/{src_path}"
            )
            homepage = meta.get("homepage") or meta.get("upstream_homepage") or ""
            if not homepage:
                if origin == "port":
                    print(
                        f"skip {name}: origin=port requires homepage "
                        f"(upstream project URL)",
                        file=sys.stderr,
                    )
                    continue
                homepage = source_url
            if "wawona.io/docs" in homepage:
                print(
                    f"skip {name}: homepage must not be a blanket wawona.io/docs URL",
                    file=sys.stderr,
                )
                continue
            row = {
                "name": name,
                "version": ver,
                "digest": digest,
                "url": f"packages/{name}/{ver}/component.wasm",
                "wasi": abi_to_wasi(abi),
                "kind": meta.get("kind", "cli"),
                "origin": origin,
                "summary": meta.get("summary", name),
                "license": "MIT",
                "runtime": "wawona-1",
                "entry": "component.wasm",
                "homepage": homepage,
                "source": source_url,
                "programs": [meta.get("bin", name)],
                "maintainers": meta.get("maintainers", ["aspauldingcode"]),
                "platforms": [
                    "macos",
                    "ios",
                    "ipados",
                    "tvos",
                    "visionos",
                    "android",
                    "linux",
                ],
                "capabilities": {
                    "wayland": bool(
                        (meta.get("capabilities") or {}).get("wayland")
                        if isinstance(meta.get("capabilities"), dict)
                        else False
                    ),
                    "filesystem": [],
                    "network": False,
                },
                "ci": ci,
            }
            if origin == "port":
                row["upstream_version"] = meta.get("upstream_version") or ver
                if meta.get("upstream_is_bootstrap"):
                    row["upstream_is_bootstrap"] = True
            by_name[name] = row
            changed += 1
            print(f"staged {name}@{ver} {digest} ci={ci['status']}")
        else:
            # Blob unchanged: still refresh Hydra-style CI status from this run.
            assert existing is not None
            prev_ci = existing.get("ci")
            if prev_ci != ci:
                existing["ci"] = ci
                by_name[name] = existing
                changed += 1
                print(f"ci {name}@{ver} -> {ci['status']}")
            else:
                print(f"unchanged {name}@{ver} ci={ci['status']}")

    # Ensure every remaining catalog row has a ci object (unknown if never smoked).
    for name, pkg in by_name.items():
        if "ci" not in pkg:
            abi = "wasi-p1"
            if name in recipe_by_name:
                abi = recipe_by_name[name].get("abi") or "wasi-p1"
            pkg["ci"] = {
                "status": "unknown",
                "runtime": runtime_for_abi(abi),
                "checked_at": None,
                "suites": empty_suites(),
            }
            changed += 1
            print(f"ci {name} -> unknown (no smoke artifact)")

    index["packages"] = sorted(by_name.values(), key=lambda p: p["name"])
    index_path.write_text(json.dumps(index, indent=2) + "\n")
    write_ci_summary(dest_root, index["packages"])
    print(f"changed={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
