#!/usr/bin/env python3
"""Aggregate out/smoke/*.json. Exit 1 if any active smoke failed. Skips are OK."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out" / "smoke"


def main() -> int:
    results = []
    for path in sorted(OUT.glob("*.json")):
        if path.name == "summary.json":
            continue
        try:
            results.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError) as e:
            results.append(
                {
                    "name": path.stem,
                    "status": "fail",
                    "detail": f"bad result json: {e}",
                    "runtime": "wasmer",
                }
            )

    passed = [r for r in results if r.get("status") == "pass"]
    skipped = [r for r in results if r.get("status") == "skip"]
    failed = [r for r in results if r.get("status") not in ("pass", "skip")]
    summary = {
        "runtime_policy": {"wasix": "wasmer", "wasi-p1": "wasmtime (wasm-packages)", "wasi-p2": "wasmtime (wasm-packages)"},
        "total": len(results),
        "passed": len(passed),
        "skipped": len(skipped),
        "failed": len(failed),
        "results": results,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    out_path = OUT / "summary.json"
    out_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(
        f"wasix smoke: {len(passed)} pass / {len(failed)} fail / {len(skipped)} skip / {len(results)} total"
    )
    print(f"wrote {out_path}")
    for r in failed:
        print(
            f"FAIL {r.get('name')} detail={r.get('detail')}",
            file=sys.stderr,
        )
    # Require at least one pass so an empty matrix cannot go green.
    if failed:
        return 1
    if not passed:
        print("no passing Wasmer smokes", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
