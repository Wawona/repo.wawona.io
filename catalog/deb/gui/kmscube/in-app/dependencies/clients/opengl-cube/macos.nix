# Standalone opengl-cube binary + in-process libopengl_cube.a for macOS.
# Renders c2d7fa/opengl-cube as a real Wayland client on Wawona's compositor:
# xdg-shell + wl_egl_window + EGL/GLES3 via iland's Wayland-EGL winsys (which
# posts the IOSurface ANGLE renders into as a linux-dmabuf wl_buffer). This is
# NOT the iland KMS path — that one is kmscube.
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
  pname = "opengl-cube-macos";
  version = "0.1.0";

  src = ../../../upstream;

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

    # xdg-shell client bindings: this client owns its own toplevel.
    XDG_XML="${waylandProtocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    wayland-scanner client-header "$XDG_XML" xdg-shell-client-protocol.h
    wayland-scanner private-code  "$XDG_XML" xdg-shell-protocol.c

    INCLUDES="-I. -I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 \
      -I${iland}/include/GLES3 -I${angle}/include -I${libwayland}/include"
    CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -O2 -std=c11 $INCLUDES"

    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation \
      -framework CoreGraphics -framework Accelerate -framework QuartzCore -framework Metal"
    # wl_egl_window_* and EGL_PLATFORM_WAYLAND come from libiland_wayland_egl,
    # never from libwayland-egl (that one is an abort-on-call vendor stub). It
    # is a separate archive from libiland_userland so KMS-only clients are not
    # forced to link Wayland; order matters, it depends on the core.
    LIBS="-L${iland}/lib -liland_wayland_egl -liland_userland \
      -L${angle}/lib -lEGL -lGLESv2 \
      -L${libwayland}/lib -lwayland-client"

    # Output name differs from the source dir (./opengl-cube) so ld does not try
    # to overwrite a directory; installed as bin/opengl-cube below.
    echo "CC opengl-cube (standalone binary)"
    "$CLANG" $CFLAGS opengl-cube/opengl_cube.c xdg-shell-protocol.c \
      $LIBS $FRAMEWORKS \
      -Wl,-rpath,${angle}/lib -Wl,-rpath,${libwayland}/lib -o opengl_cube_bin

    echo "CC libopengl_cube.a (in-process opengl_cube_main)"
    "$CLANG" -c $CFLAGS -Dmain=opengl_cube_main opengl-cube/opengl_cube.c \
      -o opengl_cube_main.o
    "$CLANG" -c $CFLAGS xdg-shell-protocol.c -o xdg-shell-protocol.o
    ar rcs libopengl_cube.a opengl_cube_main.o xdg-shell-protocol.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include $out/nix-support
    cp opengl_cube_bin $out/bin/opengl-cube
    cp libopengl_cube.a $out/lib/
    cat > $out/include/opengl_cube.h <<'EOF'
#ifndef WAWONA_OPENGL_CUBE_H
#define WAWONA_OPENGL_CUBE_H
int opengl_cube_main(int argc, char *argv[]);
#endif
EOF
    echo "${angle}" > $out/nix-support/angle-path
    echo "${iland}" > $out/nix-support/iland-path
    echo "${libwayland}" > $out/nix-support/libwayland-path
  '';

  meta = with lib; {
    description = "OpenGL cube Wayland-EGL client for macOS (ANGLE via iland winsys)";
    homepage = "https://github.com/Wawona/wwn-kmscube";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
