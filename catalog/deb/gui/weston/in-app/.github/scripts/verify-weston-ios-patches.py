#!/usr/bin/env python3
"""Verify Weston iOS patch anchors and compositor archive expectations."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS_NIX = ROOT / "dependencies/clients/weston/ios.nix"
COMPOSITOR_NIX = ROOT / "dependencies/clients/weston/compositor-apple-mobile.nix"
XCODEGEN = ROOT / "dependencies/generators/xcodegen.nix"
PATCH_TERMINAL = ROOT / "dependencies/clients/weston/terminal-patches/patch-terminal.py"
WWN_PTY = ROOT / "dependencies/libs/wawona-pty/src/wwn_pty.c"
WWN_PTY_LDFLAGS = ROOT / "dependencies/generators/weston-toytoolkit-ldflags.nix"
WAYPIPE_RUNNER = ROOT / "src/platform/macos/ui/Settings/WWNWaypipeRunner.m"

FORBIDDEN_TERMINAL_PATCH_MARKERS = [
    "patch_ios_borderless_terminal",
    "window_add_widget(terminal->window, terminal)",
    "terminal->margin = 0;",
]

REQUIRED_TERMINAL_PATCH_MARKERS = [
    "ios_configure_count",
    "terminal->ios_configure_count++",
    "defer shell unblock",
    "wwn_pty_ios_signal_shells();",
    "wwn_term_log_enabled",
    "if (attr.attr.fg == 0)",
    "cairo_set_source_rgb(cr, 0.92, 0.92, 0.92)",
    "cairo_set_source_rgb(cr, 0.12, 0.12, 0.14)",
    "scheduled initial redraw",
    "patch_ios_max_escape",
    'new = "#define MAX_ESCAPE',
    "wwn_ios_terminal_inject(data, length)",
    "patch_ios_lf_newline",
    "patch_ios_lf_newline: fake PTY shell output uses LF-only newlines",
]

REQUIRED_PTY_MARKERS = [
    "dup2(app_log_fd, STDERR_FILENO)",
    "ios_pty_input_write",
    "wwn_ios_terminal_inject",
    "wawona_zsh_main",
    "wwn_interpose_write",
    "WAWONA_PTY_DEBUG",
]

REQUIRED_PTY_LDFLAGS_MARKERS = [
    "-force_load",
    "libwwn-pty.a",
]

REQUIRED_IOS_PATCH_MARKERS = [
    "wwn_mobile_display_roundtrip",
    "wwn_mobile_pump_client_display_for_ms",
    "background_draw color",
    "output_init skipped (no shell global)",
    "patch-cairo-util-inprocess.py",
]

REQUIRED_COMPOSITOR_MARKERS = [
    "wwn_static_module_lookup",
    "wwn_weston_wayland_backend_init",
    "mobile-weston-client-launch.c",
    "patch-cairo-util-inprocess.py",
    "wayland_destroy must not cairo_debug_reset_static_data",
    "wwn_weston_inject_touch",
    "wwn_weston_input_ready",
    "synthetic seat ready",
]

REQUIRED_XCODEGEN_MARKERS = [
    "westonDataIosEmbedScript",
    "westonTerminalPng",
    "westonPatternPng",
    "13.0.0/data/terminal.png",
    "13.0.0/data/pattern.png",
    "Embed Weston data (icons, cursors)",
]


def read(path: Path) -> str:
    if not path.is_file():
        print(f"FAIL missing file: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


def check_forbidden_markers(label: str, text: str, markers: list[str]) -> None:
    present = [m for m in markers if m in text]
    if present:
        print(f"FAIL {label} forbidden markers present:", file=sys.stderr)
        for m in present:
            print(f"  - {m}", file=sys.stderr)
        sys.exit(1)
    print(f"OK {label} forbidden markers absent ({len(markers)} checks)")


def check_markers(label: str, text: str, markers: list[str]) -> None:
    missing = [m for m in markers if m not in text]
    if missing:
        print(f"FAIL {label} missing markers:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        sys.exit(1)
    print(f"OK {label} patch anchors present ({len(markers)} checks)")


def check_archive_symbols(archive: Path) -> None:
    if not archive.is_file():
        print(f"SKIP symbol check (archive not built): {archive}")
        return
    out = subprocess.run(
        ["nm", "-g", str(archive)],
        check=False,
        capture_output=True,
        text=True,
    )
    symbols = out.stdout
    for sym in ("weston_compositor_main", "wwn_static_module_lookup"):
        if sym not in symbols and f"_{sym}" not in symbols:
            print(f"WARN archive missing symbol {sym}: {archive}", file=sys.stderr)


def main() -> None:
    ios_text = read(IOS_NIX)
    compositor_text = read(COMPOSITOR_NIX)
    xcodegen_text = read(XCODEGEN)

    check_markers("ios.nix", ios_text, REQUIRED_IOS_PATCH_MARKERS)
    check_markers("compositor-apple-mobile.nix", compositor_text, REQUIRED_COMPOSITOR_MARKERS)
    check_markers("xcodegen.nix", xcodegen_text, REQUIRED_XCODEGEN_MARKERS)

    if "enableIlandDrm" not in compositor_text:
        print("FAIL compositor-apple-mobile.nix missing enableIlandDrm flag", file=sys.stderr)
        sys.exit(1)
    print("OK compositor enableIlandDrm flag present")

    if not re.search(r"NestedWestonBackend", (ROOT / "src/platform/macos/ui/Settings/WWNPreferencesManager.m").read_text()):
        print("FAIL NestedWestonBackend preference missing", file=sys.stderr)
        sys.exit(1)
    print("OK NestedWestonBackend runtime preference present")

    patch_terminal_text = read(PATCH_TERMINAL)
    check_forbidden_markers(
        "patch-terminal.py", patch_terminal_text, FORBIDDEN_TERMINAL_PATCH_MARKERS
    )
    check_markers("patch-terminal.py", patch_terminal_text, REQUIRED_TERMINAL_PATCH_MARKERS)
    check_markers("wwn_pty.c", read(WWN_PTY), REQUIRED_PTY_MARKERS)
    check_markers("weston-toytoolkit-ldflags.nix", read(WWN_PTY_LDFLAGS), REQUIRED_PTY_LDFLAGS_MARKERS)

    pty_archive = ROOT / "result-wawona-pty-ios/lib/libwwn-pty.a"
    if not pty_archive.is_file():
        try:
            store_path = subprocess.run(
                ["nix", "path-info", f"{ROOT}#wawona-pty-ios"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            pty_archive = Path(store_path) / "lib/libwwn-pty.a"
        except subprocess.CalledProcessError:
            pty_archive = Path("/nonexistent")
    if pty_archive.is_file():
        nm_out = subprocess.run(
            ["nm", str(pty_archive)],
            check=False,
            capture_output=True,
            text=True,
        ).stdout
        if "_wwn_read" not in nm_out:
            print("FAIL libwwn-pty.a missing _wwn_read interpose symbol", file=sys.stderr)
            sys.exit(1)
        print("OK libwwn-pty.a exports _wwn_read interpose")
    else:
        print("SKIP libwwn-pty.a symbol check (not built locally)")

    runner_text = read(WAYPIPE_RUNNER)
    if "unsigned launchScale = hostScale;" not in runner_text:
        print(
            "FAIL WWNWaypipeRunner missing unified hostScale launch policy",
            file=sys.stderr,
        )
        sys.exit(1)
    if "prepareIland ? hostScale : 1u" in runner_text:
        print(
            "FAIL WWNWaypipeRunner still uses nested --scale=1 mismatch policy",
            file=sys.stderr,
        )
        sys.exit(1)
    if "Launch argv:" not in runner_text:
        print("FAIL WWNWaypipeRunner missing Launch argv log", file=sys.stderr)
        sys.exit(1)
    print("OK nested Weston hostScale launch policy present")

    print("verify-weston-ios-patches: all static checks passed")


if __name__ == "__main__":
    main()
