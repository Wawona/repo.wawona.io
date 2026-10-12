# Upstream weston-simple-egl for macOS, built outside weston's meson.
#
# Meson would resolve wayland-egl to the vendored abort-on-call stub and needs a
# GL renderer it does not have here, so the client is compiled directly against
# iland's Wayland-EGL winsys (wl_egl_window + EGL_PLATFORM_WAYLAND over ANGLE,
# posting the rendered IOSurface as a linux-dmabuf wl_buffer). The sources are
# upstream's, unpatched: this client is the reference for whether Wawona's
# Wayland-EGL path behaves like a Linux host's.
{
  lib,
  pkgs,
  buildModule,
  xcodeUtils,
  ...
}:

let
  iland = buildModule.buildForMacOS "iland" { };
  angle = buildModule.buildForMacOS "angle" { };
  libwayland = buildModule.buildForMacOS "libwayland" { };
  waylandProtocols = pkgs.wayland-protocols;
in
pkgs.stdenv.mkDerivation {
  pname = "weston-simple-egl-macos";
  version = "13.0.0";

  src = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/13.0.0/downloads/weston-13.0.0.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  __noChroot = true;
  dontConfigure = true;

  nativeBuildInputs = [ pkgs.wayland-scanner ];

  buildPhase = ''
    runHook preBuild

    unset DEVELOPER_DIR
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      echo "ERROR: MacOSX SDK not found." >&2
      exit 1
    fi
    export SDKROOT="$MACOS_SDK"

    CLANG="${pkgs.clang}/bin/clang"

    # macOS has no linux/input.h, and upstream's pulls in linux/types.h and the
    # ioctl structs none of which exist here. simple-egl only wants three
    # evdev codes, and their values are ABI — the compositor sends them over the
    # wire, so they have to be the Linux numbers, not local inventions.
    mkdir -p compat/linux
    cat > compat/linux/input.h <<'EOF'
#pragma once
/* From include/uapi/linux/input-event-codes.h; the wire values libinput and
 * every Wayland compositor send. */
#define KEY_ESC   1
#define KEY_F11  87
#define BTN_LEFT 0x110
EOF

    # Client-side bindings for the four protocols simple-egl binds. Nothing here
    # is weston-specific, so they all come from wayland-protocols.
    gen() {
      wayland-scanner client-header "$1" "$2-client-protocol.h"
      wayland-scanner private-code  "$1" "$2-protocol.c"
    }
    P="${waylandProtocols}/share/wayland-protocols"
    gen "$P/stable/xdg-shell/xdg-shell.xml"                        xdg-shell
    gen "$P/stable/viewporter/viewporter.xml"                      viewporter
    gen "$P/staging/fractional-scale/fractional-scale-v1.xml"      fractional-scale-v1
    gen "$P/staging/tearing-control/tearing-control-v1.xml"        tearing-control-v1

    # meson would generate this. shared/xalloc.h is header-only but names
    # glibc's program_invocation_short_name; a literal keeps libSystem's
    # ___progname out, matching the polyfill the main weston recipe uses.
    cat > config.h <<'EOF'
#pragma once
#define PACKAGE_STRING "weston 13.0.0"
#define PACKAGE_VERSION "13.0.0"
/* Unlocks the EGL half of shared/platform.h — weston_check_egl_extension and
 * weston_platform_get_egl_display, which is how this client reaches
 * eglGetPlatformDisplayEXT(EGL_PLATFORM_WAYLAND). */
#define ENABLE_EGL 1
#ifndef program_invocation_short_name
#define program_invocation_short_name "weston-simple-egl"
#endif
EOF

    # No -Ishared: weston has its own shared/signal.h, and putting that
    # directory on the search path makes <signal.h> resolve to it, taking
    # sigaction() with it. The sources spell these "shared/platform.h", so -I.
    # is what they actually need.
    INCLUDES="-I. -Icompat -Iinclude \
      -I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 \
      -I${iland}/include/GLES3 -I${angle}/include -I${libwayland}/include"
    # sys/time.h for gettimeofday: on glibc it arrives through another header.
    CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -O2 -std=gnu11 \
      -Wno-unused-parameter -include sys/time.h $INCLUDES"

    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation \
      -framework CoreGraphics -framework Accelerate -framework QuartzCore -framework Metal"
    # force_load the winsys so the constructor sets iland_wl_ops (EGL_PLATFORM_WAYLAND).
    # GLES comes from ANGLE's libGLESv2. Do not -lEGL from ANGLE: that LC_LOADs
    # ANGLE as the public EGL ABI, and weston_platform_get_egl_display then
    # eglGetProcAddress's into ANGLE, which has no Wayland platform on Apple.
    # Never -lwayland-egl: that dylib is a stub whose entry points abort.
    LIBS="-L${iland}/lib \
      -Wl,-force_load,${iland}/lib/libiland_wayland_egl.a \
      -Wl,-force_load,${iland}/lib/libiland_userland.a \
      -L${angle}/lib -lGLESv2 \
      -L${libwayland}/lib -lwayland-client -lwayland-cursor"

    SUPPORT="shared/matrix.c \
      xdg-shell-protocol.c viewporter-protocol.c \
      fractional-scale-v1-protocol.c tearing-control-v1-protocol.c"

    echo "CC weston-simple-egl (standalone binary)"
    "$CLANG" $CFLAGS clients/simple-egl.c $SUPPORT \
      $LIBS $FRAMEWORKS \
      -Wl,-rpath,${angle}/lib -Wl,-rpath,${libwayland}/lib \
      -o weston_simple_egl_bin

    echo "CC libweston_simple_egl.a (in-process simple_egl_main)"
    objs=""
    "$CLANG" -c $CFLAGS -Dmain=simple_egl_main clients/simple-egl.c \
      -o simple_egl_main.o
    objs="simple_egl_main.o"
    for src in $SUPPORT; do
      obj="$(basename "$src" .c).o"
      "$CLANG" -c $CFLAGS "$src" -o "$obj"
      objs="$objs $obj"
    done
    ar rcs libweston_simple_egl.a $objs

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include $out/nix-support
    cp weston_simple_egl_bin $out/bin/weston-simple-egl
    cp libweston_simple_egl.a $out/lib/
    cat > $out/include/weston_simple_egl.h <<'EOF'
#ifndef WAWONA_WESTON_SIMPLE_EGL_H
#define WAWONA_WESTON_SIMPLE_EGL_H
int simple_egl_main(int argc, char *argv[]);
#endif
EOF
    echo "${angle}" > $out/nix-support/angle-path
    echo "${iland}" > $out/nix-support/iland-path
    echo "${libwayland}" > $out/nix-support/libwayland-path
  '';

  meta = with lib; {
    description = "weston-simple-egl for macOS (Wayland-EGL via iland winsys + ANGLE)";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
