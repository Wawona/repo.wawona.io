#!/usr/bin/env python3
"""Minimal semver helpers for upstream freshness (no external deps)."""
from __future__ import annotations

import re
from typing import Optional, Tuple


def parse_semver(raw: str) -> Optional[Tuple[int, int, int]]:
    s = raw.strip().lstrip("v")
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", s)
    if not m:
        m = re.match(r"^(\d+)\.(\d+)$", s)
        if not m:
            m = re.match(r"^(\d+)$", s)
            if not m:
                return None
            return int(m.group(1)), 0, 0
        return int(m.group(1)), int(m.group(2)), 0
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def cmp_semver(a: str, b: str) -> int:
    """Return -1 if a<b, 0 if equal/unparseable tie, 1 if a>b."""
    pa, pb = parse_semver(a), parse_semver(b)
    if pa is None or pb is None:
        if a == b:
            return 0
        return -1 if a < b else 1
    if pa < pb:
        return -1
    if pa > pb:
        return 1
    return 0


def bump_patch(version: str) -> str:
    p = parse_semver(version)
    if p is None:
        return version + ".1"
    return f"{p[0]}.{p[1]}.{p[2] + 1}"
