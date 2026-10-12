# Standalone kmscube binary + in-process libkmscube.a for macOS (iland + ANGLE).
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
in
pkgs.stdenv.mkDerivation {
  pname = "kmscube-macos";
  version = "0.1.0";

  src = ../../../upstream;

  __noChroot = true;
  dontConfigure = true;

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

    INCLUDES="-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -O2 -std=c11 $INCLUDES \
      -Wno-int-conversion -Wno-int-to-void-pointer-cast -include kmscube_compat.h"

    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation \
      -framework CoreGraphics -framework Accelerate -framework QuartzCore -framework Metal"
    LIBS="-L${iland}/lib -liland_userland -L${angle}/lib -lEGL -lGLESv2"

    echo "CC kmscube (standalone binary)"
    "$CLANG" $CFLAGS kmscube.c esUtil.c $LIBS $FRAMEWORKS \
      -Wl,-rpath,${angle}/lib -o kmscube

    echo "CC libkmscube.a (in-process kmscube_main)"
    "$CLANG" -c $CFLAGS -Dmain=kmscube_main kmscube.c -o kmscube_main.o
    "$CLANG" -c $CFLAGS esUtil.c -o esUtil.o
    ar rcs libkmscube.a kmscube_main.o esUtil.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include $out/nix-support
    cp kmscube $out/bin/
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
    description = "kmscube GL smoke test over iland + ANGLE for macOS";
    homepage = "https://github.com/Wawona/wwn-kmscube";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
