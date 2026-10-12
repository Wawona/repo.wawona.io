# gbm_es2_demo — DRM/KMS/GBM/GLES2 acceptance client over iland + ANGLE (macOS).
# Upstream: https://github.com/ds-hwang/gbm_es2_demo (MIT). Same packaging
# shape as kmscube (KMS presenter path, not a Wayland client).
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
  srcRoot = ../../../upstream/gbm-es2-demo;
in
pkgs.stdenv.mkDerivation {
  pname = "gbm-es2-demo-macos";
  version = "0.1.0";

  src = srcRoot;

  __noChroot = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cp ${../../../upstream/wwn_cube_hud.c} wwn_cube_hud.c
    cp ${../../../upstream/wwn_cube_hud.h} wwn_cube_hud.h

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

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi
    if [ -n "''${DEVELOPER_DIR:-}" ] && [ -x "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++" ]; then
      CLANGXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
    else
      CLANGXX="${pkgs.clang}/bin/clang++"
      AR="${pkgs.clang}/bin/ar"
    fi

    INCLUDES="-I. -Iged_lib -Idemo -I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    CXXFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -O2 -std=c++17 -fPIC $INCLUDES \
      -Wno-unused-parameter -include gbm_es2_demo_compat.h"
    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation \
      -framework CoreGraphics -framework Accelerate -framework QuartzCore -framework Metal"
    LIBS="-L${iland}/lib -liland_userland -L${angle}/lib -lEGL -lGLESv2 -lc++"

    SOURCES="ged_lib/drm_modesetter.cpp ged_lib/egl_drm_glue.cpp ged_lib/matrix.cpp \
      demo/gbm_es2_demo.cpp demo/dma_buf_mmap_demo.cpp demo/main.cpp"

    echo "CXX gbm_es2_demo (standalone binary)"
    $CLANGXX $CXXFLAGS $SOURCES $LIBS $FRAMEWORKS -Wl,-rpath,${angle}/lib -o gbm_es2_demo

    echo "CXX libgbm_es2_demo.a (in-process gbm_es2_demo_main)"
    # Standalone binary above keeps real main. The archive must not export it
    # or LC_MAIN steals Swift @main when force-loaded into Wawona.app.
    OBJS=""
    for src in $SOURCES; do
      obj="$(basename "$src" .cpp).o"
      EXTRA=""
      case "$src" in
        # Product ABI is the existing extern "C" gbm_es2_demo_main(). Rename
        # the C++ main() only so the archive never exports _main.
        demo/main.cpp) EXTRA="-Dmain=gbm_es2_demo_cli_main" ;;
      esac
      $CLANGXX -c $CXXFLAGS $EXTRA "$src" -o "$obj"
      OBJS="$OBJS $obj"
    done
    $AR rcs libgbm_es2_demo.a $OBJS

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include $out/nix-support
    cp gbm_es2_demo $out/bin/
    ln -s gbm_es2_demo $out/bin/gbm-es2-demo
    cp libgbm_es2_demo.a $out/lib/
    cat > $out/include/gbm_es2_demo.h <<'EOF'
#ifndef WAWONA_GBM_ES2_DEMO_H
#define WAWONA_GBM_ES2_DEMO_H
int gbm_es2_demo_main(int argc, char *argv[]);
#endif
EOF
    echo "${angle}" > $out/nix-support/angle-path
    echo "${iland}" > $out/nix-support/iland-path
  '';

  meta = with lib; {
    description = "gbm_es2_demo GBM/KMS/GLES2 smoke test over iland + ANGLE for macOS";
    homepage = "https://github.com/ds-hwang/gbm_es2_demo";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
