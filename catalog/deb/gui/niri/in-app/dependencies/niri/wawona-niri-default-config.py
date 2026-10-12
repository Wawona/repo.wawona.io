#!/usr/bin/env python3
"""Tune bundled niri default-config.kdl for Wawona (no waybar, Adwaita cursors, no X11)."""
import os
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    'spawn-at-startup "waybar"',
    '/-spawn-at-startup "waybar"',
    1,
)
if "xcursor-theme" not in text:
    text += """

// Wawona: bundled Adwaita Xcursor theme. Stock niri uses theme name "default".
cursor {
    xcursor-theme "Adwaita"
    xcursor-size 24
}

// Wawona Mode A has no X11 session and does not ship xwayland-satellite.
xwayland-satellite {
    off
}
"""
os.chmod(path, path.stat().st_mode | stat.S_IWRITE)
path.write_text(text)
