# kmscube over wwn-iland (GBM/EGL/DRM) + ANGLE — Apple mobile in-process archive.
#
# Produces libkmscube.a with kmscube_main for nested GL inside Wawona. Standalone
# kmscube binary is only built on macOS (see macos.nix).
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
  mobile = (import "${toolchainSrc}/dependencies/toolchains/apple-mobile-platform.nix") {
    inherit iosToolchain simulator;
  };
  sdkPlatform = mobile.sdkPlatform;
  minVerFlag = mobile.minVerFlag;
in
pkgs.stdenv.mkDerivation {
  pname = "kmscube-apple-mobile";
  version = "0.1.0";

  src = ../../../upstream;

  __noChroot = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    INCLUDES="-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    CFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag} -O2 -std=c11 \
      $INCLUDES -Wno-int-conversion -Wno-int-to-void-pointer-cast \
      -include kmscube_compat.h"

    echo "CC libkmscube.a (in-process kmscube_main)"
    "$CLANG" -c $CFLAGS -Dmain=kmscube_main kmscube.c -o kmscube_main.o
    "$CLANG" -c $CFLAGS esUtil.c -o esUtil.o
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
    description = "kmscube in-process archive over iland GBM/EGL/DRM + ANGLE";
    homepage = "https://github.com/Wawona/wwn-kmscube";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
