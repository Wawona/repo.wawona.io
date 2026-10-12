#!/usr/bin/env python3
"""Load allowlist.toml without requiring Python 3.11 tomllib.

Supports the curated shape used by this repo: [meta], [[packages]],
string/int/list values. Not a general TOML parser.
"""
from __future__ import annotations

import ast
import pathlib
import re
from typing import Any, Dict, List, Optional


def _parse_value(raw: str) -> Any:
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1].strip()
        if not inner:
            return []
        parts = [p.strip() for p in inner.split(",")]
        return [_parse_value(p) for p in parts]
    if (raw.startswith('"') and raw.endswith('"')) or (
        raw.startswith("'") and raw.endswith("'")
    ):
        return ast.literal_eval(raw)
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    if raw in ("true", "false"):
        return raw == "true"
    return raw


def load_allowlist(path: pathlib.Path) -> Dict[str, Any]:
    text = path.read_text()
    meta: Dict[str, Any] = {}
    packages: List[Dict[str, Any]] = []
    section: Optional[str] = None
    current: Optional[Dict[str, Any]] = None

    for line in text.splitlines():
        line = line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        s = line.strip()
        if s == "[meta]":
            section = "meta"
            current = meta
            continue
        if s == "[[packages]]":
            section = "packages"
            current = {}
            packages.append(current)
            continue
        if "=" not in s or current is None:
            continue
        key, val = s.split("=", 1)
        current[key.strip()] = _parse_value(val)

    return {"meta": meta, "packages": packages}
