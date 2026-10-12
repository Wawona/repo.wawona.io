#!/usr/bin/env python3
"""Wawona fork: show Wayland WM when WAYLAND_DISPLAY is set on macOS."""
from pathlib import Path

path = Path("src/detection/displayserver/displayserver_apple.c")
text = path.read_text()
old = """void ffConnectDisplayServerImpl(FFDisplayServerResult* ds) {
    {
        FF_CFTYPE_AUTO_RELEASE CFMachPortRef port = CGWindowServerCreateServerPort();
        if (port) {
            ffStrbufSetStatic(&ds->wmProcessName, "WindowServer");
            ffStrbufSetStatic(&ds->wmPrettyName, "Quartz Compositor");
        }
    }

    detectDisplays(ds);
}"""
new = """void ffConnectDisplayServerImpl(FFDisplayServerResult* ds) {
    {
        FF_CFTYPE_AUTO_RELEASE CFMachPortRef port = CGWindowServerCreateServerPort();
        if (port) {
            ffStrbufSetStatic(&ds->wmProcessName, "WindowServer");
            ffStrbufSetStatic(&ds->wmPrettyName, "Quartz Compositor");
        }
        if (getenv("WAYLAND_DISPLAY")) {
            const char *desktop = getenv("XDG_CURRENT_DESKTOP");

            ffStrbufSetStatic(&ds->wmProcessName, "Wayland");
            if (desktop && *desktop) {
                ffStrbufSetStatic(&ds->wmPrettyName, desktop);
            }
            ffStrbufSetS(&ds->wmProtocolName, FF_WM_PROTOCOL_WAYLAND);
        }
    }

    detectDisplays(ds);
}"""
if old not in text:
    raise SystemExit("displayserver_apple.c anchor missing (already patched or upstream drift)")
path.write_text(text.replace(old, new, 1))
