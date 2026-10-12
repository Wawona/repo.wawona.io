#!/usr/bin/env python3
"""Tolerate missing Weston PNG assets on mobile (Android + Apple)."""

from __future__ import annotations

import sys
from pathlib import Path


def patch_frame_icon_load(text: str) -> str:
    old = """\ticon = cairo_image_surface_create_from_png(icon_name);
\tif (cairo_surface_status(icon) != CAIRO_STATUS_SUCCESS)
\t\tgoto error;"""
    new = """#if defined(__ANDROID__) || (defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH))
\ticon = cairo_image_surface_create_from_png(icon_name);
\tif (cairo_surface_status(icon) != CAIRO_STATUS_SUCCESS) {
\t\tif (icon)
\t\t\tcairo_surface_destroy(icon);
\t\ticon = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
\t}
#else
\ticon = cairo_image_surface_create_from_png(icon_name);
\tif (cairo_surface_status(icon) != CAIRO_STATUS_SUCCESS)
\t\tgoto error;
#endif"""
    if old not in text:
        raise SystemExit("frame.c icon load anchor missing")
    return text.replace(old, new, 1)


def main() -> None:
    path = Path(sys.argv[1])
    text = path.read_text()
    if "#include <TargetConditionals.h>" not in text:
        text = text.replace(
            '#include "config.h"',
            '#include "config.h"\n#if defined(__APPLE__)\n#include <TargetConditionals.h>\n#endif',
            1,
        )
    path.write_text(patch_frame_icon_load(text))


if __name__ == "__main__":
    main()
