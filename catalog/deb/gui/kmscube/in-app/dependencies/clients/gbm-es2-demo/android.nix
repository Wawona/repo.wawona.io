# gbm_es2_demo for Android NDK — in-process libgbm_es2_demo.a over wwn-iland + ANGLE.
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
  srcRoot = ../../../upstream/gbm-es2-demo;
in
pkgs.stdenv.mkDerivation {
  pname = "gbm-es2-demo-android";
  version = "0.1.0";

  src = srcRoot;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cp ${../../../upstream/wwn_cube_hud.c} wwn_cube_hud.c
    cp ${../../../upstream/wwn_cube_hud.h} wwn_cube_hud.h

    CXX="${androidToolchain.androidCXX}"
    AR="${androidToolchain.androidAR}"

    INCLUDES="-I. -Iged_lib -Idemo -I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    CXXFLAGS="-fPIC -O2 -std=c++17 $INCLUDES -Wno-unused-parameter \
      -include ${iland}/include/iland_drm_open_compat.h \
      -include gbm_es2_demo_compat.h"

    # Android compat header still pulls EGL; strip Apple eglGetDisplay cast if unused.
    SOURCES="ged_lib/drm_modesetter.cpp ged_lib/egl_drm_glue.cpp ged_lib/matrix.cpp \
      demo/gbm_es2_demo.cpp demo/dma_buf_mmap_demo.cpp demo/main.cpp"

    echo "CXX libgbm_es2_demo.a (in-process gbm_es2_demo_main)"
    # Never export C main into the archive (same LC_MAIN steal as Apple mobile).
    OBJS=""
    for src in $SOURCES; do
      obj="$(basename "$src" .cpp).o"
      EXTRA=""
      case "$src" in
        # Product ABI is the existing extern "C" gbm_es2_demo_main(). Rename
        # the C++ main() only so the archive never exports _main.
        demo/main.cpp) EXTRA="-Dmain=gbm_es2_demo_cli_main" ;;
      esac
      "$CXX" -c $CXXFLAGS $EXTRA "$src" -o "$obj"
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
    description = "gbm_es2_demo in-process archive over iland + ANGLE for Android";
    homepage = "https://github.com/ds-hwang/gbm_es2_demo";
    license = licenses.mit;
    # Host platforms that cross-build this Android package (not the Android ABI).
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
