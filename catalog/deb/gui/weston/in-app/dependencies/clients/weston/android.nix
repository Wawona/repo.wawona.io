# Weston real toytoolkit + demo clients, cross-compiled for Android (NDK) as in-process
# static libraries (mirrors ios.nix; not the old placeholder .so shim).
#
# Output archives (mirrors ios.nix link contract):
#   libweston-13.a        -> toytoolkit + demo clients (flower_main, etc.)
#   libweston-terminal.a  -> real clients/terminal.c + wawona-pty spawn
#   libweston-desktop-13.a-> real clients/desktop-shell.c (fork/exec OK)
#   libweston-keyboard.a  -> on-screen keyboard (input-method protocol)
{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildPackages,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  enableGlClients ? false,
  ...
}:

let
  libwayland = buildModule.buildForAndroid "libwayland" { };
  # Real weston-terminal drives a local zsh over the PTY shim on Android too.
  wawonaPty = buildModule.buildForAndroid "wawona-pty" { };
  xkbcommon = buildModule.buildForAndroid "xkbcommon" { };
  cairo = buildModule.buildForAndroid "cairo" { };
  pango = buildModule.buildForAndroid "pango" { };
  fontconfig = buildModule.buildForAndroid "fontconfig" { };
  freetype = buildModule.buildForAndroid "freetype" { };
  glib = buildModule.buildForAndroid "glib" { };
  harfbuzz = buildModule.buildForAndroid "harfbuzz" { };
  fribidi = buildModule.buildForAndroid "fribidi" { };
  pixman = buildModule.buildForAndroid "pixman" { };
  libpng = buildModule.buildForAndroid "libpng" { };
  expat = buildModule.buildForAndroid "expat" { };
  libffi = buildModule.buildForAndroid "libffi" { };
  pcre2 = buildModule.buildForAndroid "pcre2" { };
  libintl = buildModule.buildForAndroid "libintl" { };

  glClients = if enableGlClients then buildModule.buildForAndroid "kmscube" { } else null;
  iland = if enableGlClients then buildModule.buildForAndroid "iland" { } else null;
  angle = if enableGlClients then buildModule.buildForAndroid "angle" { } else null;
  glIncludeFlags = if enableGlClients then
    "-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
  else "";

  pkgConfigPath = lib.concatStringsSep ":" (map (d: "${d}/lib/pkgconfig") [
    cairo pango fontconfig freetype glib harfbuzz fribidi pixman libpng
    expat libffi pcre2 libintl xkbcommon libwayland
  ]);

  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host-weston-android";
    src = pkgs.wayland.src;
    depsBuildBuild = with buildPackages; [ libxml2 expat ];
    nativeBuildInputs = with buildPackages; [
      meson
      ninja
      pkg-config
      python3
      libxml2
      expat
    ];
    configurePhase = ''
      export PKG_CONFIG_PATH="${buildPackages.libxml2.dev}/lib/pkgconfig:${buildPackages.expat.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
      meson setup build \
        --prefix=$out \
        -Dlibraries=false \
        -Ddocumentation=false \
        -Dtests=false
    '';
    buildPhase = ''
      meson compile -C build wayland-scanner
    '';
    installPhase = ''
      mkdir -p $out/bin
      SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
      [ -n "$SCANNER_BIN" ] || { echo "wayland-scanner not found" >&2; exit 1; }
      cp "$SCANNER_BIN" $out/bin/wayland-scanner
    '';
  };

  clients = [
    "flower" "clickdot" "smoke" "eventdemo" "resizor" "cliptest"
    "transformed" "stacking" "dnd" "image" "scaler"
    "editor" "constraints"
  ];

  linuxHeadersRef = "45dcf5e28813954da4150e7260ccb61e95856176";
  linux_input_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input.h";
    sha256 = "sha256-ciO4IN6ANMgnw/yBe2dApcUcqDMkgLhtagwUJzD7I54=";
  };
  linux_input_event_codes_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-CqF1r2sCoJbn3Bcr0x6B1JnrqQg3d1FejCCqkVq3new=";
  };
in
pkgs.stdenv.mkDerivation rec {
  pname = "weston-android";
  version = "13.0.0";

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  waylandSrc = pkgs.wayland.src;

  nativeBuildInputs = [
    waylandScanner
    buildPackages.wayland-protocols
    buildPackages.pkg-config
    buildPackages.python3
  ];

  buildPhase = ''
    runHook preBuild

    CC="${androidToolchain.androidCC}"
    AR="${androidToolchain.androidAR}"
    RANLIB="${androidToolchain.androidRANLIB}"
    export PKG_CONFIG_PATH="${pkgConfigPath}"
    PKGCONF="${buildPackages.pkg-config}/bin/pkg-config"
    DEP_CFLAGS=$($PKGCONF --cflags cairo pango pangocairo fontconfig freetype2 harfbuzz fribidi glib-2.0 gobject-2.0 libpng pixman-1 xkbcommon wayland-client wayland-cursor)

    mkdir -p gen include/linux
    SCANNER="${waylandScanner}/bin/wayland-scanner"
    WP="${buildPackages.wayland-protocols}/share/wayland-protocols"
    gen_proto() {
      local name="$1" xml="$2"
      "$SCANNER" client-header "$xml" "gen/$name-client-protocol.h"
      "$SCANNER" private-code  "$xml" "gen/$name-protocol.c"
    }
    gen_proto xdg-shell                      "$WP/stable/xdg-shell/xdg-shell.xml"
    gen_proto viewporter                     "$WP/stable/viewporter/viewporter.xml"
    gen_proto presentation-time              "$WP/stable/presentation-time/presentation-time.xml"
    gen_proto relative-pointer-unstable-v1   "$WP/unstable/relative-pointer/relative-pointer-unstable-v1.xml"
    gen_proto pointer-constraints-unstable-v1 "$WP/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml"
    gen_proto tablet-unstable-v2             "$WP/unstable/tablet/tablet-unstable-v2.xml"
    gen_proto text-input-unstable-v1         "$WP/unstable/text-input/text-input-unstable-v1.xml"
    gen_proto text-cursor-position           "protocol/text-cursor-position.xml"
    gen_proto ivi-application                "protocol/ivi-application.xml"
    gen_proto input-method-unstable-v1       "$WP/unstable/input-method/input-method-unstable-v1.xml"
    gen_proto weston-desktop-shell           "protocol/weston-desktop-shell.xml"
    # simple-egl (enableGlClients) needs these staging protocols.
    gen_proto fractional-scale-v1            "$WP/staging/fractional-scale/fractional-scale-v1.xml"
    gen_proto tearing-control-v1             "$WP/staging/tearing-control/tearing-control-v1.xml"

    cat > config.h <<'EOF'
#ifndef WESTON_CONFIG_H
#define WESTON_CONFIG_H
#define PACKAGE_STRING "weston 13.0.0"
#define PACKAGE_VERSION "13.0.0"
#define HAVE_PANGO 1
#define HAVE_XKBCOMMON_COMPOSE 1
#define DATADIR "/usr/share"
#define BINDIR "/usr/bin"
#define LIBEXECDIR "/usr/libexec"
#define MODULEDIR "/usr/lib/weston"
#define LIBWESTON_MODULEDIR "/usr/lib/libweston"
#endif
EOF

    cat > include/android-polyfills.h <<'EOF'
#ifndef WESTON_ANDROID_POLYFILLS_H
#define WESTON_ANDROID_POLYFILLS_H
#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#ifndef WESTON_HOWMANY
#define WESTON_HOWMANY(x, y) (((int)(x) + (int)(y) - 1) / (int)(y))
#endif
#endif
EOF

    cp ${linux_input_h} include/linux/input.h
    cp ${linux_input_event_codes_h} include/linux/input-event-codes.h

    mkdir -p wlsrc && tar xf ${waylandSrc} -C wlsrc
    WLCURSOR=$(echo wlsrc/wayland-*/cursor)

    POLYFILLS="$PWD/include/android-polyfills.h"
    CFLAGS="-fPIC -O2 \
      -I. -Iinclude -Igen \
      -idirafter shared \
      -I$WLCURSOR \
      -I${libwayland}/include \
      -I${libintl}/include \
      -Dprogram_invocation_short_name=getprogname() \
      -DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC -DCLOCK_REALTIME_COARSE=CLOCK_REALTIME \
      $DEP_CFLAGS"

    objs=()
    compile() {
      local src="$1"; shift
      local obj="$(echo "$src" | tr '/.' '__').o"
      echo "CC $src"
      "$CC" -c "$src" -include "$POLYFILLS" $CFLAGS "$@" -o "$obj"
      objs+=("$obj")
    }
    # Like iOS: only append the object when the compile succeeds (simple-egl
    # is optional and must not poison the archive on failure).
    try_compile() {
      local src="$1"; shift
      local obj="$(echo "$src" | tr '/.' '__').o"
      echo "CC $src"
      if "$CC" -c "$src" -include "$POLYFILLS" $CFLAGS "$@" -o "$obj"; then
        objs+=("$obj")
        return 0
      fi
      rm -f "$obj"
      return 1
    }

    # frame_create loads PNGs from WESTON_DATA_DIR; tolerate missing assets on
    # Android so clients degrade to 1×1 placeholders instead of SIGSEGV.
    cp shared/frame.c shared/mobile-frame.c
    cp ${./terminal-patches/patch-frame-mobile.py} ./patch-frame-mobile.py
    python3 patch-frame-mobile.py shared/mobile-frame.c
    python3 ${./terminal-patches/patch-cairo-util-inprocess.py}

    for s in shared/config-parser.c shared/option-parser.c shared/signal.c \
             shared/file-util.c shared/os-compatibility.c shared/process-util.c \
             shared/hash.c shared/image-loader.c shared/cairo-util.c \
             shared/mobile-frame.c \
             shared/matrix.c libweston/vertex-clipping.c; do
      compile "$s"
    done

    compile "$WLCURSOR/wayland-cursor.c"
    compile "$WLCURSOR/xcursor.c"

    # Protocol private-code for desktop-shell and input-method lives only in
    # libweston-desktop-13.a / libweston-keyboard.a (mirrors ios.nix + compositor dedupe).
    for p in gen/*-protocol.c; do
      case "$(basename "$p")" in
        weston-desktop-shell-protocol.c|input-method-unstable-v1-protocol.c)
          continue
          ;;
      esac
      compile "$p"
    done
    cp clients/window.c clients/mobile-window.c
    cp ${./wwn-mobile-clients.h} ./wwn-mobile-clients.h
    cp ${./terminal-patches/patch-window-csd.py} ./patch-window-csd.py
    python3 patch-window-csd.py clients/mobile-window.c clients/window.h
    cp ${./terminal-patches/patch-window-mobile-host.py} ./patch-window-mobile-host.py
    python3 patch-window-mobile-host.py clients/mobile-window.c
    compile clients/mobile-window.c

    # Standalone weston_log()/weston_log_set_handler() for the client-only
    # toytoolkit archive. The real nested compositor is linked separately by
    # Wawona via weston-compositor-ldflags.nix.
    compile ${./wwn-client-weston-log-shim.c}
    compile ${./wwn-weston-log.c}
    compile ${./mobile-weston-host-clients.c}

    for c in ${lib.concatStringsSep " " clients}; do
      sym=$(echo "$c" | tr '-' '_')
      compile "clients/$c.c" -Dmain="''${sym}_main"
    done

    if [ "${if enableGlClients then "1" else "0"}" = "1" ] && [ -n "${if enableGlClients then "${glClients}" else ""}" ]; then
      sym=simple_egl
      echo "CC clients/simple-egl.c (iland GL stack)"
      try_compile "clients/simple-egl.c" -Dmain="''${sym}_main" -DENABLE_EGL=1 ${glIncludeFlags} || {
        echo "ERROR: weston-simple-egl failed to compile against the iland GL stack" >&2
        echo "Do not skip this client. Keep upstream square size (no resize patches)." >&2
        exit 1
      }
    fi

    cat > weston_main.c <<'EOF'
extern int flower_main(int argc, char **argv);
int wwn_weston_is_compat_shim(void) { return 0; }
int wwn_weston_is_real_toytoolkit(void) { return 1; }
int weston_main(int argc, char **argv) {
  (void)argc; (void)argv;
  char *a[] = { "weston-flower", 0 };
  return flower_main(1, a);
}
EOF
    compile weston_main.c
    "$AR" rcs libweston-13.a "''${objs[@]}"
    if command -v "$RANLIB" >/dev/null 2>&1; then
      "$RANLIB" libweston-13.a
    fi

    # Real weston-terminal (drives a local zsh). The iOS-specific resize/PTY
    # blocks in patch-terminal.py are Apple-guarded #if's, so on Android the
    # generic upstream forkpty/spawn path is what compiles.
    cp clients/terminal.c clients/mobile-terminal.c
    cp ${./terminal-patches/patch-terminal.py} ./patch-terminal.py
    cp ${wawonaPty}/include/wwn_pty.h ./wwn_pty.h
    python3 patch-terminal.py clients/mobile-terminal.c
    compile clients/mobile-terminal.c "-Dmain=weston_terminal_main" "-I${wawonaPty}/include"
    term_obj="$(echo clients/mobile-terminal.c | tr '/.' '__').o"
    "$AR" rcs libweston-terminal.a "$term_obj"

    # Real weston-desktop-shell (fork/exec panel launchers are allowed on Android).
    echo "CC gen/weston-desktop-shell-protocol.c"
    "$CC" -c gen/weston-desktop-shell-protocol.c -include "$POLYFILLS" $CFLAGS \
      -o gen_weston_desktop_shell_protocol_c.o
    cp clients/desktop-shell.c clients/mobile-desktop-shell.c
    python3 <<'PY'
from pathlib import Path
p = Path("clients/mobile-desktop-shell.c")
text = p.read_text()
old = """\tweston_config_section_get_string(s, "background-image",
\t\t\t\t\t &background->image, NULL);
\tweston_config_section_get_color(s, "background-color",
\t\t\t\t\t&background->color, 0x00000000);

\tweston_config_section_get_string(s, "background-type",
\t\t\t\t\t &type, "tile");"""
new = """\t{
\t\tstatic char wwn_default_bg[512];
\t\tconst char *wwn_data = getenv("WESTON_DATA_DIR");
\t\twwn_default_bg[0] = '\\0';
\t\tif (wwn_data && wwn_data[0])
\t\t\tsnprintf(wwn_default_bg, sizeof wwn_default_bg,
\t\t\t\t "%s/background.png", wwn_data);
\t\tweston_config_section_get_string(s, "background-image",
\t\t\t\t\t\t &background->image,
\t\t\t\t\t\t wwn_default_bg[0] ? wwn_default_bg : NULL);
\t}
\tweston_config_section_get_color(s, "background-color",
\t\t\t\t\t&background->color, 0x00000000);

\tweston_config_section_get_string(s, "background-type",
\t\t\t\t\t &type, "scale");"""
if old not in text:
    raise SystemExit("android desktop-shell background-image default anchor missing")
p.write_text(text.replace(old, new, 1))
PY
    echo "CC clients/mobile-desktop-shell.c"
    "$CC" -c clients/mobile-desktop-shell.c -include "$POLYFILLS" $CFLAGS \
      -Dmain=weston_desktop_shell_main -o clients_mobile_desktop_shell_c.o
    "$AR" rcs libweston-desktop-13.a gen_weston_desktop_shell_protocol_c.o clients_mobile_desktop_shell_c.o

    # On-screen keyboard client for text-input protocol.
    echo "CC gen/input-method-unstable-v1-protocol.c"
    "$CC" -c gen/input-method-unstable-v1-protocol.c -include "$POLYFILLS" $CFLAGS \
      -o gen_input_method_unstable_v1_protocol_c.o
    echo "CC clients/keyboard.c"
    "$CC" -c clients/keyboard.c -include "$POLYFILLS" $CFLAGS \
      -Dmain=weston_keyboard_main -o clients_keyboard_c.o
    "$AR" rcs libweston-keyboard.a gen_input_method_unstable_v1_protocol_c.o clients_keyboard_c.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    cp libweston-13.a $out/lib/
    cp libweston-terminal.a $out/lib/
    cp libweston-desktop-13.a $out/lib/
    cp libweston-keyboard.a $out/lib/
    if [ -d gen ]; then cp -r gen $out/include/weston-gen; fi

    echo "Verifying in-process Weston demo client symbols..."
    NM="${androidToolchain.androidNdkToolchainBase}/bin/llvm-nm"
    missing=0
    for c in ${lib.concatStringsSep " " clients}; do
      sym="$(echo "$c" | tr '-' '_')_main"
      obj="clients_''${c}_c.o"
      if "$NM" -g "$obj" 2>/dev/null | awk '{print $NF}' | grep -Fxq "$sym"; then
        echo "✓ $sym"
      else
        echo "ERROR: missing $sym in $obj" >&2
        missing=1
      fi
    done
    if ! "$NM" -g libweston-terminal.a 2>/dev/null | awk '{print $NF}' | grep -Fxq weston_terminal_main; then
      echo "ERROR: missing weston_terminal_main in libweston-terminal.a" >&2
      missing=1
    fi
    if ! "$NM" -g libweston-desktop-13.a 2>/dev/null | awk '{print $NF}' | grep -Fxq weston_desktop_shell_main; then
      echo "ERROR: missing weston_desktop_shell_main in libweston-desktop-13.a" >&2
      missing=1
    fi
    if ! "$NM" -g libweston-keyboard.a 2>/dev/null | awk '{print $NF}' | grep -Fxq weston_keyboard_main; then
      echo "ERROR: missing weston_keyboard_main in libweston-keyboard.a" >&2
      missing=1
    fi
    [ "$missing" -eq 0 ] || exit 1

    runHook postInstall
  '';

  meta = with lib; {
    description = "Weston real toytoolkit + demo clients (Android NDK static libs)";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
