#!/usr/bin/env python3
"""Rename Neovim globals that collide with zsh in the Wawona iOS link."""
from __future__ import annotations

import re
import sys
from pathlib import Path

RENAMES: list[tuple[str, list[tuple[str, str]]]] = [
    ("src/nvim/eval.c", [("pattern_match", "nvim_pattern_match")]),
]


def rename_identifiers(text: str, pairs: list[tuple[str, str]]) -> str:
    for old, new in pairs:
        text = re.sub(rf"\b{re.escape(old)}\b", new, text)
    return text


def main() -> int:
    changed = 0
    for rel, pairs in RENAMES:
        path = Path(rel)
        if not path.is_file():
            print(f"warning: {rel} missing; skipping", file=sys.stderr)
            continue
        original = path.read_text(encoding="utf-8")
        patched = rename_identifiers(original, pairs)
        if patched != original:
            path.write_text(patched, encoding="utf-8")
            changed += 1
            print(f"patched {rel}", file=sys.stderr)
    if changed == 0:
        print("no neovim link-collision patches applied", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
