# opengl-cube for Android — Wayland-EGL client over iland's AHB dmabuf winsys
# (same #86 modifier convention as Apple IOSurface). Not the KMS interim.
{
  lib,
  pkgs,
  buildModule,
  androidToolchain ? (import "${toolchainSrc}/dependencies/toolchains/android.nix" {
    inherit lib pkgs;
  }),
  toolchainSrc ? null,
  ...
}:

let
  iland = buildModule.buildForAndroid "iland" { };
  libwayland = buildModule.buildForAndroid "libwayland" { };
  waylandProtocols = pkgs.wayland-protocols;
in
pkgs.stdenv.mkDerivation {
  pname = "opengl-cube-android";
  version = "0.1.0";
  src = ../../../upstream;
  dontConfigure = true;
  nativeBuildInputs = [ pkgs.wayland-scanner ];
  buildPhase = ''
    runHook preBuild
    CC="${androidToolchain.androidCC}"
    AR="${androidToolchain.androidAR}"

    XDG_XML="${waylandProtocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    wayland-scanner client-header "$XDG_XML" xdg-shell-client-protocol.h
    wayland-scanner private-code  "$XDG_XML" xdg-shell-protocol.c

    INCLUDES="-I. -I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 \
      -I${iland}/include/GLES3 -I${libwayland}/include -I${libwayland}/include/wayland"
    CFLAGS="-fPIC -O2 -std=c11 $INCLUDES"

    echo "CC libopengl_cube.a (Wayland-EGL)"
    "$CC" -c $CFLAGS -Dmain=opengl_cube_main opengl-cube/opengl_cube.c \
      -o opengl_cube_main.o
    "$CC" -c $CFLAGS xdg-shell-protocol.c -o xdg-shell-protocol.o
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
    echo "${iland}" > $out/nix-support/iland-path
    echo "${libwayland}" > $out/nix-support/libwayland-path
  '';
  meta = with lib; {
    description = "OpenGL cube Wayland-EGL client for Android (ANGLE via iland winsys)";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
