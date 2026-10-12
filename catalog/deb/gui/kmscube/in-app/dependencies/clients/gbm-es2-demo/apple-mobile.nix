# gbm_es2_demo over wwn-iland + ANGLE — Apple mobile in-process archive.
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
  srcRoot = ../../../upstream/gbm-es2-demo;
in
pkgs.stdenv.mkDerivation {
  pname = "gbm-es2-demo-apple-mobile";
  version = "0.1.0";

  src = srcRoot;

  __noChroot = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cp ${../../../upstream/wwn_cube_hud.c} wwn_cube_hud.c
    cp ${../../../upstream/wwn_cube_hud.h} wwn_cube_hud.h

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANGXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    INCLUDES="-I. -Iged_lib -Idemo -I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    CXXFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag} -O2 -std=c++17 -fPIC \
      $INCLUDES -Wno-unused-parameter -include gbm_es2_demo_compat.h"

    SOURCES="ged_lib/drm_modesetter.cpp ged_lib/egl_drm_glue.cpp ged_lib/matrix.cpp \
      demo/gbm_es2_demo.cpp demo/dma_buf_mmap_demo.cpp demo/main.cpp"

    echo "CXX libgbm_es2_demo.a (in-process gbm_es2_demo_main)"
    # Never export C main into the archive. A linked _main steals LC_MAIN from
    # Swift @main on iOS/tvOS/visionOS and the host app dies in the cube demo.
    OBJS=""
    for src in $SOURCES; do
      obj="$(basename "$src" .cpp).o"
      EXTRA=""
      case "$src" in
        # Product ABI is the existing extern "C" gbm_es2_demo_main(). Rename
        # the C++ main() only so the archive never exports _main.
        demo/main.cpp) EXTRA="-Dmain=gbm_es2_demo_cli_main" ;;
      esac
      "$CLANGXX" -c $CXXFLAGS $EXTRA "$src" -o "$obj"
      OBJS="$OBJS $obj"
    done
    "$AR" rcs libgbm_es2_demo.a $OBJS

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include $out/nix-support
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
    description = "gbm_es2_demo in-process archive over iland GBM/EGL/DRM + ANGLE";
    homepage = "https://github.com/ds-hwang/gbm_es2_demo";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
