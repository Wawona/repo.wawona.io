#!/usr/bin/env python3
"""Aggregate out/*/…/smoke-result.json into out/smoke-summary.json. Exit 1 if any fail."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"


def main() -> int:
    results = []
    for path in sorted(OUT.glob("*/*/smoke-result.json")):
        try:
            results.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError) as e:
            results.append(
                {
                    "name": path.parent.parent.name,
                    "status": "fail",
                    "detail": f"bad smoke-result.json: {e}",
                    "runtime": "unknown",
                }
            )

    passed = [r for r in results if r.get("status") == "pass"]
    failed = [r for r in results if r.get("status") != "pass"]
    summary = {
        "runtime_policy": {
            "wasi-p1": "wasmtime",
            "wasi-p2": "wasmtime",
            "wasix": "wasmer (wasinix repo)",
        },
        "total": len(results),
        "passed": len(passed),
        "failed": len(failed),
        "results": results,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    out_path = OUT / "smoke-summary.json"
    out_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"smoke summary: {len(passed)} pass / {len(failed)} fail / {len(results)} total")
    print(f"wrote {out_path}")
    for r in failed:
        print(
            f"FAIL {r.get('name')} runtime={r.get('runtime')} detail={r.get('detail')}",
            file=sys.stderr,
        )
    return 1 if failed or not results else 0


if __name__ == "__main__":
    raise SystemExit(main())
