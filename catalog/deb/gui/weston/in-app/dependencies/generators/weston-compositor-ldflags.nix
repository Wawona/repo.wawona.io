# Link flags for the cross-compiled Weston nested compositor (libweston-compositor-13.a)
# consumed on Apple mobile and Android targets. Pass the platform nativeDeps attrset
# from flake.nix.
{ lib, deps, forceLoadCompositor ? true, linkMode ? "force_load" }:

let
  strip = d: if d == null then "" else toString d;
  libPath = name:
    if deps ? ${name} && deps.${name} != null then "-L${strip deps.${name}}/lib" else "";
  compositor = deps."weston-compositor" or deps.weston-compositor or null;
  libPaths = lib.filter (s: s != "") [
    (libPath "libwayland")
    (libPath "expat")
    (libPath "weston-compositor")
  ];
  libs =
    lib.filter (s: s != "") [
      "-lwayland-server"
      "-lwayland-cursor"
      "-lexpat"
      "-lm"
    ]
    ++ lib.optionals (deps.iland or null != null) [
      "-lwayland-egl"
    ];
  compositorArchive =
    if compositor == null then
      [ ]
    else if !forceLoadCompositor then
      # Lazy/normal archive linking: the linker only extracts objects that
      # satisfy symbols still unresolved when it reaches this archive (e.g.
      # weston_log/weston_log_set_handler from libweston/log.c, needed by
      # mobile-weston-host-clients.c). Object files that duplicate symbols
      # already pulled from a whole-archive/force_load'd client toytoolkit
      # (xdg-shell-protocol.c, shared/matrix.c, etc. - compiled into both
      # libweston-13.a and libweston-compositor-13.a) are simply never
      # extracted, avoiding "duplicate symbol" link errors.
      [ "-Wl,-u,weston_compositor_main" "${strip compositor}/lib/libweston-compositor-13.a" ]
    else if linkMode == "whole_archive" then
      [
        "-Wl,--whole-archive"
        "${strip compositor}/lib/libweston-compositor-13.a"
        "-Wl,--no-whole-archive"
      ]
    else
      [ "-force_load" "${strip compositor}/lib/libweston-compositor-13.a" ];
  # libweston-desktop-13.a and libweston-keyboard.a are force-loaded by
  # weston-toytoolkit-ldflags.nix; do not duplicate them here.
in
libPaths ++ compositorArchive ++ libs
