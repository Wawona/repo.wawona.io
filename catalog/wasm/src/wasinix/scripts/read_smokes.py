#!/usr/bin/env python3
"""Read wasinix/smokes.toml. Prefer tomllib; fall back to a minimal parser for our shape."""
from __future__ import annotations

import ast
import io
import json
import sys
from pathlib import Path


def _load_tomllib(path: Path) -> dict:
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib  # type: ignore
        except ImportError:
            return {}
    return tomllib.load(io.BytesIO(path.read_bytes()))


def _parse_scalar(raw: str):
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        return json.loads(raw.replace("'", '"')) if "'" in raw else json.loads(raw)
    if (raw.startswith('"') and raw.endswith('"')) or (
        raw.startswith("'") and raw.endswith("'")
    ):
        return ast.literal_eval(raw)
    if raw in ("true", "false"):
        return raw == "true"
    try:
        return int(raw)
    except ValueError:
        return raw


def _load_minimal(path: Path) -> dict:
    """Enough for [[packages]] tables with string/int/array fields."""
    meta: dict = {}
    packages: list[dict] = []
    cur: dict | None = None
    section = None
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s == "[meta]":
            section = "meta"
            cur = None
            continue
        if s == "[[packages]]":
            section = "packages"
            cur = {}
            packages.append(cur)
            continue
        if "=" not in s:
            continue
        key, val = s.split("=", 1)
        key = key.strip()
        parsed = _parse_scalar(val)
        if section == "meta":
            meta[key] = parsed
        elif section == "packages" and cur is not None:
            cur[key] = parsed
    return {"meta": meta, "packages": packages}


def load_smokes(path: Path | None = None) -> dict:
    root = Path(__file__).resolve().parents[1]
    path = path or (root / "smokes.toml")
    data = _load_tomllib(path)
    if data:
        return data
    return _load_minimal(path)


def _sh_quote(s: str) -> str:
    return "'" + s.replace("'", "'\"'\"'") + "'"


def _b64(s: str) -> str:
    import base64

    return base64.b64encode(s.encode("utf-8")).decode("ascii")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: read_smokes.py matrix|package|env <name>", file=sys.stderr)
        return 2
    data = load_smokes()
    cmd = argv[1]
    if cmd == "matrix":
        names = [
            p["name"]
            for p in data.get("packages") or []
            if (p.get("status") or "active") == "active"
        ]
        print(json.dumps({"include": [{"package": n} for n in names]}))
        return 0
    if cmd in ("package", "env"):
        if len(argv) < 3:
            print(f"usage: read_smokes.py {cmd} <name>", file=sys.stderr)
            return 2
        name = argv[2]
        for p in data.get("packages") or []:
            if p.get("name") == name:
                if cmd == "package":
                    print(json.dumps(p))
                    return 0
                status = p.get("status") or "active"
                wasm = p.get("wasm") or (name + ".wasm")
                exit_code = p.get("exit")
                print(f"smoke_status={_sh_quote(status)}")
                print(f"smoke_reason={_sh_quote(str(p.get('reason') or ''))}")
                print(f"wasm_name={_sh_quote(wasm)}")
                print(f"smoke_args_json={_sh_quote(json.dumps(list(p.get('args') or [])))}")
                # Base64 avoids multiline shell eval breakage for stdin fixtures.
                print(f"smoke_stdin_b64={_sh_quote(_b64(str(p.get('stdin') or '')))}")
                print(f"smoke_expect={_sh_quote(str(p.get('expect') or ''))}")
                print(f"smoke_exit={int(0 if exit_code is None else exit_code)}")
                return 0
        print(f"unknown package: {name}", file=sys.stderr)
        return 1
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
