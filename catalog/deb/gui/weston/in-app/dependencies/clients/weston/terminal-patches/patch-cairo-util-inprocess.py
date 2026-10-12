#!/usr/bin/env python3
"""Skip cairo_debug_reset_static_data in in-process Weston compositor hosts.

Linux weston is a process. cairo_debug_reset_static_data is a Valgrind helper
that asserts if any cairo object remains (_cairo_hash_table_destroy). On
Apple mobile and Android, weston_compositor_main shares libcairo with
weston-terminal, desktop-shell, keyboard, pango, and Foot. Destroying nested
weston must not reset process-global cairo/fontconfig maps.

Toytoolkit already skips the call in clients/window.c (wwn #96). The nested
compositor wayland backend still calls cleanup_after_cairo from
wayland_destroy. Apple mobile then drops cairo-util.c.o from
libweston-compositor-13.a (duplicate-symbol split with weston-ios
libweston-13.a), so the linked definition is toytoolkit cairo-util.c.
Patch both: strip wayland_destroy calls (compositor TU) and no-op the
function (toytoolkit TU).
"""

from __future__ import annotations

from pathlib import Path

CAIRO_MARKER = "skip cairo_debug_reset_static_data: in-process host"
WAYLAND_MARKER = "skip cleanup_after_cairo: in-process host"

OLD_FN = """void
cleanup_after_cairo(void)
{
	/* some clients, particular weston-editor, still creates indirectly a
	 * new font map; this makes sure we untie that up and avoid an assert
	 * from cairo */
#ifdef HAVE_PANGO
	pango_cairo_font_map_set_default(NULL);
#endif
	cairo_debug_reset_static_data();
#ifdef HAVE_PANGO
	FcFini();
#endif
}
"""

NEW_FN = f"""void
cleanup_after_cairo(void)
{{
	/* {CAIRO_MARKER}.
	 * Nested weston teardown shares libcairo with terminals, desktop-shell,
	 * keyboard, pango, and Foot. Resetting the process-global scaled-font
	 * map aborts in _cairo_hash_table_destroy. Linux weston is a process,
	 * so this Valgrind helper stays there. */
}}
"""


def patch_cairo_util() -> None:
    path = Path("shared/cairo-util.c")
    if not path.is_file():
        raise SystemExit("shared/cairo-util.c missing")
    text = path.read_text()
    if CAIRO_MARKER in text:
        print("cairo-util.c already skips cairo_debug_reset_static_data")
        return
    if OLD_FN not in text:
        raise SystemExit("cairo-util.c cleanup_after_cairo anchor missing (in-process)")
    path.write_text(text.replace(OLD_FN, NEW_FN, 1))
    print("Patched cairo-util.c: skip cairo_debug_reset_static_data (in-process)")


def patch_wayland_backend() -> None:
    path = Path("libweston/backend-wayland/wayland.c")
    if not path.is_file():
        return
    text = path.read_text()
    old = "\tcleanup_after_cairo();\n"
    if old not in text:
        if WAYLAND_MARKER in text:
            print("wayland.c already skips cleanup_after_cairo")
            return
        raise SystemExit("wayland.c cleanup_after_cairo call missing (in-process)")
    count = text.count(old)
    path.write_text(text.replace(old, f"\t/* {WAYLAND_MARKER} */\n"))
    print(f"Patched wayland.c: skipped {count} cleanup_after_cairo calls")


def main() -> None:
    patch_cairo_util()
    patch_wayland_backend()


if __name__ == "__main__":
    main()
