#!/usr/bin/env python3
"""Print GitHub Actions matrix JSON for active (non-skip) smokes.toml rows."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from read_smokes import main

if __name__ == "__main__":
    raise SystemExit(main(["read_smokes.py", "matrix"]))
