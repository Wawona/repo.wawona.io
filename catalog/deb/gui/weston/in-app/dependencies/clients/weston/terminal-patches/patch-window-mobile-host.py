#!/usr/bin/env python3
"""Patch weston clients/window.c for in-process host compositor on Android."""

from __future__ import annotations

import sys
from pathlib import Path


def patch_includes(text: str) -> str:
    anchor = '#include <wayland-client.h>'
    block = anchor + """
#if defined(__ANDROID__)
#include <sched.h>
#include "wwn-mobile-clients.h"
#define WWN_DISPLAY_LOG(...) ((void)0)
#define wl_display_roundtrip(display) wwn_mobile_display_roundtrip(display)
#define wl_display_dispatch(display) wwn_mobile_display_dispatch(display)
#endif"""
    if "wwn-mobile-clients.h" in text:
        return text
    if anchor not in text:
        raise SystemExit("window.c wayland-client include missing")
    return text.replace(anchor, block, 1)


def patch_roundtrip(text: str) -> str:
    old = """\tif (wl_display_roundtrip(d->display) < 0) {
\t\tfprintf(stderr, "Failed to process Wayland connection: %s\\n",
\t\t\tstrerror(errno));
\t\tdisplay_destroy(d);
\t\treturn NULL;
\t}"""
    new = """\tif (wwn_mobile_display_roundtrip(d->display) < 0) {
\t\tfprintf(stderr, "Failed to process Wayland connection: %s\\n",
\t\t\tstrerror(errno));
\t\tdisplay_destroy(d);
\t\treturn NULL;
\t}"""
    if "wwn_mobile_display_roundtrip(d->display)" in text:
        return text
    if old not in text:
        raise SystemExit("window.c display_create roundtrip anchor missing")
    return text.replace(old, new, 1)


def patch_display_run_epoll(text: str) -> str:
    old = """\t\tcount = epoll_wait(display->epoll_fd,
\t\t\t\t   ep, ARRAY_LENGTH(ep), -1);"""
    new = """#if defined(__ANDROID__)
\t\t/* Timed wait yields to host compositor render thread (same process). */
\t\tcount = epoll_wait(display->epoll_fd,
\t\t\t\t   ep, ARRAY_LENGTH(ep), 1);
\t\tif (count == 0) {
\t\t\twwn_ios_pump_host_compositor();
\t\t\tsched_yield();
\t\t\tcontinue;
\t\t}
\t\twwn_ios_pump_host_compositor();
#else
\t\tcount = epoll_wait(display->epoll_fd,
\t\t\t\t   ep, ARRAY_LENGTH(ep), -1);
#endif"""
    if "wwn_ios_pump_host_compositor();" in text:
        return text
    if old not in text:
        raise SystemExit("window.c display_run epoll anchor missing")
    return text.replace(old, new, 1)


def patch_cairo_refcount(text: str) -> str:
    """wwn #96: track live toytoolkit displays. Do not call
    cleanup_after_cairo / cairo_debug_reset_static_data / FcFini: Foot (fcft)
    and other in-process clients keep cairo scaled fonts. A last-display
    check still fires while Foot is drawing (Foot is not toytoolkit) and
    aborts in _cairo_hash_table_destroy."""
    if "wwn_toytoolkit_live_displays" in text:
        return text

    counter_anchor = (
        "struct display *\n"
        "display_create(int *argc, char *argv[])\n"
        "{\n"
        "\tstruct display *d;\n"
    )
    if counter_anchor not in text:
        raise SystemExit("window.c display_create definition anchor missing (refcount)")
    text = text.replace(
        counter_anchor,
        "/* wwn #96: live toytoolkit displays across all in-process clients. */\n"
        "static int wwn_toytoolkit_live_displays;\n\n"
        + counter_anchor,
        1,
    )

    # Increment after the last free(d) early-exit and before the roundtrip path
    # that can call display_destroy(d), keeping the count balanced on success and
    # roundtrip-failure paths.
    incr_anchor = (
        "\td->registry = wl_display_get_registry(d->display);\n"
        "\twl_registry_add_listener(d->registry, &registry_listener, d);\n"
    )
    if incr_anchor not in text:
        raise SystemExit("window.c display_create registry anchor missing (refcount)")
    text = text.replace(
        incr_anchor,
        incr_anchor + "\n\twwn_toytoolkit_live_displays++;\n",
        1,
    )

    cleanup_anchor = "\tcleanup_after_cairo();\n"
    if cleanup_anchor not in text:
        raise SystemExit("window.c cleanup_after_cairo anchor missing (refcount)")
    text = text.replace(
        cleanup_anchor,
        "\tif (wwn_toytoolkit_live_displays > 0)\n"
        "\t\twwn_toytoolkit_live_displays--;\n"
        "\t/* skip cleanup_after_cairo: Foot/fcft share libcairo in-process */\n",
        1,
    )
    return text


def main() -> None:
    path = Path(sys.argv[1])
    text = path.read_text()
    text = patch_includes(text)
    text = patch_roundtrip(text)
    text = patch_display_run_epoll(text)
    text = patch_cairo_refcount(text)
    path.write_text(text)


if __name__ == "__main__":
    main()
