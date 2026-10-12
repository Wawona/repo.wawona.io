# Link flags for the cross-compiled weston toytoolkit (cairo/pango stack) consumed
# by libweston-13.a on Apple mobile and Android targets. Pass the platform's
# nativeDeps attrset from flake.nix.
{ lib, deps, forceLoadWeston ? false, linkMode ? "force_load", linkWestonSimpleShm ? true
  # macOS in-process compositor is self-contained (helpers kept in
  # libweston-compositor-13.a). Linking -lweston-13 (shared demo build) then
  # duplicates libweston core symbols. Set false on that target.
, linkWestonLib ? true }:

let
  strip = d: if d == null then "" else toString d;
  libPath = name:
    if deps ? ${name} && deps.${name} != null then "-L${strip deps.${name}}/lib" else "";
  libPaths = lib.filter (s: s != "") [
    (libPath "cairo")
    (libPath "pango")
    (libPath "harfbuzz")
    (libPath "fontconfig")
    (libPath "freetype")
    (libPath "fribidi")
    (libPath "glib")
    (libPath "libpng")
    (libPath "pcre2")
    (libPath "expat")
    (libPath "libintl")
    (libPath "weston")
    (libPath "wawona-pty")
  ];
  libs = lib.filter (s: s != "") [
    "-lcairo"
    "-lpangocairo-1.0"
    "-lpangoft2-1.0"
    "-lpango-1.0"
    "-lharfbuzz"
    "-lfontconfig"
    "-lfreetype"
    "-lfribidi"
    "-lgobject-2.0"
    "-lglib-2.0"
    "-lgmodule-2.0"
    "-lgio-2.0"
    "-lpng16"
    "-lpcre2-8"
    (if deps ? libintl && deps.libintl != null then "-lintl" else "")
  ];
  westonLibDir = strip (deps.weston or null) + "/lib";
  westonArchives =
    let
      archiveNames = [
        "libweston-13.a"
        "libweston-terminal.a"
        "libweston-desktop-13.a"
        "libweston-keyboard.a"
      ];
      existingArchives =
        if forceLoadWeston && linkWestonLib && deps ? weston && deps.weston != null then
          lib.filter (name: builtins.pathExists "${westonLibDir}/${name}") archiveNames
        else
          [ ];
    in
    if !linkWestonLib then
      [ ]
    else if existingArchives == [ ] then
      # Dylib fallback when no static toytoolkit archives exist. Do not use on
      # macOS app link when compositor already embeds libweston (see linkWestonLib).
      lib.filter (s: s != "") [
        "-lweston-13"
        (if builtins.pathExists "${westonLibDir}/libweston-desktop-13.dylib" then "-lweston-desktop-13" else "")
        (if builtins.pathExists "${westonLibDir}/libweston-terminal.dylib" then "-lweston-terminal" else "")
      ]
    else if linkMode == "whole_archive" then
      [
        "-Wl,--whole-archive"
      ]
      ++ (map (name: "${westonLibDir}/${name}") existingArchives)
      ++ [
        "-Wl,--no-whole-archive"
      ]
    else
      lib.concatLists (map (name: [ "-force_load" "${westonLibDir}/${name}" ]) existingArchives);
  wawonaPtyArchive =
    let
      ptyDir = strip (deps."wawona-pty" or null);
    in
    if ptyDir != "" && builtins.pathExists "${ptyDir}/lib/libwwn-pty.a" then
      [ "-force_load" "${ptyDir}/lib/libwwn-pty.a" ]
    else
      [ ];
  westonSimpleShmArchive =
    let
      shmDir = strip (deps."weston-simple-shm" or null);
    in
    if !linkWestonSimpleShm || shmDir == "" || !builtins.pathExists "${shmDir}/lib/libweston_simple_shm.a" then
      [ ]
    else if linkMode == "whole_archive" then
      [ "-Wl,--whole-archive" "${shmDir}/lib/libweston_simple_shm.a" "-Wl,--no-whole-archive" ]
    else
      [ "-force_load" "${shmDir}/lib/libweston_simple_shm.a" ];
in
libPaths ++ westonArchives ++ wawonaPtyArchive ++ westonSimpleShmArchive ++ libs
