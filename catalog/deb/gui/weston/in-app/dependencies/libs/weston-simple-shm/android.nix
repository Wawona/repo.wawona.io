# libweston_simple_shm.a for Android (mirrors ios.nix). os-compatibility.c is
# already in libweston-13.a when weston-android is linked.
{
  lib,
  pkgs,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  westonSimpleShmSrc = pkgs.callPackage ./patched-src.nix { };
  libwayland = buildModule.buildForAndroid "libwayland" { };
  westonAndroid = buildModule.buildForAndroid "weston" { };
  androidSignalPolyfill = ./../../toolchains/wwn-android-signal-polyfill.h;
in
pkgs.stdenv.mkDerivation {
  pname = "weston-simple-shm-android";
  version = "13.0.0";
  src = westonSimpleShmSrc;

  # Host fixup corrupts Android ELF static archives on Darwin (macOS ar format).
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    cp ${androidSignalPolyfill} wwn-android-signal-polyfill.h
    sed -i 's|^#include <unistd.h>|#if defined(__ANDROID__)\n#include <signal.h>\n#endif\n#include <unistd.h>|' clients/simple-shm.c
    CC="${androidToolchain.androidCC}"
    AR="${androidToolchain.androidAR}"
    CFLAGS="-fPIC -O2 \
      -DWWN_ANDROID_SHM_POLYFILL \
      -include $PWD/wwn-android-signal-polyfill.h \
      -I. -Ishared -Iinclude \
      -I${libwayland}/include -I${libwayland}/include/wayland \
      -I${westonAndroid}/include -I${westonAndroid}/include/weston-gen \
      -D_GNU_SOURCE"
    objs=()
    for src in clients/simple-shm.c xdg-shell-protocol.c fullscreen-shell-unstable-v1-protocol.c; do
      obj="''${src%.c}.o"
      "$CC" -c "$src" $CFLAGS -o "$obj"
      objs+=("$obj")
    done
    "$AR" rcs libweston_simple_shm.a "''${objs[@]}"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp libweston_simple_shm.a $out/lib/
    runHook postInstall
  '';
}
