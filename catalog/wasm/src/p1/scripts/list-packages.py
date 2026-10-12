#!/usr/bin/env python3
"""Emit package names for GHA matrix JSON (delegates to select-build-packages)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
mode = sys.argv[1] if len(sys.argv) > 1 else "all"
raise SystemExit(
    subprocess.call([sys.executable, str(root / "scripts" / "select-build-packages.py"), mode])
)
