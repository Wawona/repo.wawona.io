# opengl-cube as a Wayland client — Apple mobile in-process archive.
#
# Renders c2d7fa/opengl-cube (CC0), ported off GLFW/GLEW onto Wayland + EGL:
# xdg-shell toplevel + wl_egl_window on Wawona's compositor, via iland's
# Wayland-EGL winsys. This is NOT the iland KMS path — that one is kmscube.
# Needs GLES3 (VAOs, GLSL ES 300) where kmscube only needs GLES2.
{
  lib,
  pkgs,
  buildModule,
  simulator ? false,
  iosToolchain,
  xcodeUtils ? iosToolchain,
  toolchainSrc ? null,
  ...
}:

let
  iland = buildModule.buildForIOS "iland" { inherit simulator; };
  angle = buildModule.buildForIOS "angle" { inherit simulator; };
  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  waylandProtocols = pkgs.wayland-protocols;
  mobile = (import "${toolchainSrc}/dependencies/toolchains/apple-mobile-platform.nix") {
    inherit iosToolchain simulator;
  };
  sdkPlatform = mobile.sdkPlatform;
  minVerFlag = mobile.minVerFlag;
in
pkgs.stdenv.mkDerivation {
  pname = "opengl-cube-apple-mobile";
  version = "0.1.0";

  src = ../../../upstream;

  __noChroot = true;
  dontConfigure = true;

  nativeBuildInputs = [ pkgs.wayland-scanner ];

  buildPhase = ''
    runHook preBuild

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    # xdg-shell client bindings: this client owns its own toplevel.
    XDG_XML="${waylandProtocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    wayland-scanner client-header "$XDG_XML" xdg-shell-client-protocol.h
    wayland-scanner private-code  "$XDG_XML" xdg-shell-protocol.c

    INCLUDES="-I. -I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 \
      -I${iland}/include/GLES3 -I${angle}/include \
      -I${libwayland}/include -I${libwayland}/include/wayland"
    CFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag} -O2 -std=c11 $INCLUDES"

    echo "CC libopengl_cube.a (in-process opengl_cube_main)"
    "$CLANG" -c $CFLAGS -Dmain=opengl_cube_main opengl-cube/opengl_cube.c \
      -o opengl_cube_main.o
    "$CLANG" -c $CFLAGS xdg-shell-protocol.c -o xdg-shell-protocol.o
    "$AR" rcs libopengl_cube.a opengl_cube_main.o xdg-shell-protocol.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include $out/nix-support
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
    description = "OpenGL cube Wayland-EGL client archive (ANGLE via iland winsys)";
    homepage = "https://github.com/Wawona/wwn-kmscube";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
