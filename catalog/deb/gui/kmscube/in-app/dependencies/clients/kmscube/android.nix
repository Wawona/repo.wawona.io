# kmscube for Android NDK — in-process libkmscube.a over wwn-iland + ANGLE.
# Requires iland Android port (wwn-iland); archive-only build (no standalone APK).
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
  angle = buildModule.buildForAndroid "angle" { };
in
pkgs.stdenv.mkDerivation {
  pname = "kmscube-android";
  version = "0.1.0";

  src = ../../../upstream;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    CC="${androidToolchain.androidCC}"
    AR="${androidToolchain.androidAR}"

    INCLUDES="-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    CFLAGS="-fPIC -O2 -std=c11 $INCLUDES -Wno-int-conversion -Wno-int-to-void-pointer-cast \
      -include ${iland}/include/iland_drm_open_compat.h"

    echo "CC libkmscube.a (in-process kmscube_main)"
    "$CC" -c $CFLAGS -Dmain=kmscube_main kmscube.c -o kmscube_main.o
    "$CC" -c $CFLAGS esUtil.c -o esUtil.o
    "$AR" rcs libkmscube.a kmscube_main.o esUtil.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include $out/nix-support
    cp libkmscube.a $out/lib/
    cat > $out/include/kmscube.h <<'EOF'
#ifndef WAWONA_KMSCUBE_H
#define WAWONA_KMSCUBE_H
int kmscube_main(int argc, char *argv[]);
#endif
EOF
    echo "${angle}" > $out/nix-support/angle-path
    echo "${iland}" > $out/nix-support/iland-path
  '';

  meta = with lib; {
    description = "kmscube in-process archive over iland + ANGLE for Android";
    homepage = "https://github.com/Wawona/wwn-kmscube";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
