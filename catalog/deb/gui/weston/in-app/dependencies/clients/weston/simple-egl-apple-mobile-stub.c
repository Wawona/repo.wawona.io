/*
 * Fallback only: compiled when clients/simple-egl.c fails against the iland
 * Wayland-EGL stack in ios.nix. Prefer the real upstream client — the winsys
 * (wl_egl_window + EGL_PLATFORM_WAYLAND) ships in libiland_wayland_egl.a.
 *
 * Keep simple_egl_main for link compatibility; return nonzero so Machines can
 * surface launch-failed without aborting the host.
 */
#include <stdio.h>

int simple_egl_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  fprintf(stderr,
          "weston-simple-egl: real client failed to build; stub linked "
          "(rebuild weston with enableGlClients + iland Wayland-EGL)\n");
  return 127;
}
