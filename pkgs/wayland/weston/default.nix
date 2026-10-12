# Upstream weston compositor as a process deb. No App Store patches.
# Not apple-mobile.nix. Not weston_compositor_main. Nested on Wawona's socket.
# linux: pack nixpkgs weston. android: NDK/Bionic meson (Termux).
{ pkgs
, nativePkgs ? pkgs
, mkDebFromBins
, packProcessDeb
, target ? "linux"
, jailbreakScheme ? null
}:

assert target == "linux" || target == "android";

let
  inherit (pkgs) lib;
  isAndroid = target == "android";
  version = if isAndroid then nativePkgs.weston.version else pkgs.weston.version;

  ndkLibs = import ../ndkLibs.nix { inherit nativePkgs; };
  androidNdk = ndkLibs.ndk;
  waylandAndroid = ndkLibs.libs.wayland;
  androidPcPath = ndkLibs.pcPath [
    "wayland"
    "pixman"
    "xkbcommon"
    "cairo"
    "libdrm"
    "libinput"
    "libudev-zero"
    "libevdev"
    "freetype"
    "fontconfig"
    "expat"
    "libpng"
    "libdisplay-info"
  ];

  westonPkg =
    if !isAndroid then pkgs.weston
    else
      nativePkgs.stdenv.mkDerivation {
        pname = "weston-android";
        inherit version;
        src = nativePkgs.weston.src;
        patches = nativePkgs.weston.patches or [ ];
        dontPatchELF = true;
        dontStrip = true;
        nativeBuildInputs = with nativePkgs; [
          meson
          ninja
          pkg-config
          wayland-scanner
          python3
        ];
        # Bionic: no libutil; no glibc program_invocation_short_name / values.h.
        postPatch = ''
          sed -i "s/cc.find_library('util')/cc.find_library('c')/g" clients/meson.build
          cat > shared/android-progname.h <<'EOF'
#ifndef WESTON_ANDROID_PROGNAME_H
#define WESTON_ANDROID_PROGNAME_H
#include <stdlib.h>
#ifndef program_invocation_short_name
#define program_invocation_short_name getprogname()
#endif
#endif
EOF
          sed -i 's|#include <string.h>|#include <string.h>\n#include "android-progname.h"|' shared/xalloc.h
          mkdir -p include
          cat > include/values.h <<'EOF'
#ifndef _VALUES_H
#define _VALUES_H
#include <limits.h>
#include <float.h>
#endif
EOF
        '';
        configurePhase = ''
          runHook preConfigure
          export PKG_CONFIG_PATH="${androidPcPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
          export PKG_CONFIG_PATH_FOR_BUILD="${nativePkgs.wayland-scanner.dev}/lib/pkgconfig''${PKG_CONFIG_PATH_FOR_BUILD:+:$PKG_CONFIG_PATH_FOR_BUILD}"
          export PKG_CONFIG_ALLOW_CROSS=1
          meson setup build \
            --cross-file=${androidNdk.mesonCrossFile} \
            --prefix=$out \
            -Dc_link_args=-Wl,-rpath,/data/data/com.termux/files/usr/lib \
            -Dbackend-drm=false \
            -Dbackend-headless=true \
            -Dbackend-pipewire=false \
            -Dbackend-rdp=false \
            -Dbackend-vnc=false \
            -Dbackend-wayland=true \
            -Dbackend-x11=false \
            -Dbackend-default=wayland \
            -Drenderer-gl=false \
            -Drenderer-vulkan=false \
            -Dxwayland=false \
            -Dsystemd=false \
            -Dremoting=false \
            -Dpipewire=false \
            -Dshell-desktop=true \
            -Dshell-ivi=false \
            -Dshell-kiosk=false \
            -Dshell-lua=false \
            -Dcolor-management-lcms=false \
            -Dimage-jpeg=false \
            -Dimage-webp=false \
            -Dtools= \
            -Ddemo-clients=false \
            -Dsimple-clients=shm \
            -Dwcap-decode=false \
            -Dtests=false \
            -Ddoc=false
          runHook postConfigure
        '';
        buildPhase = ''
          runHook preBuild
          export PKG_CONFIG_PATH="${androidPcPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
          meson compile -C build
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          meson install -C build
          mkdir -p $out/lib
          for lib in libwayland-client.so libwayland-server.so libwayland-cursor.so; do
            if [ -e ${waylandAndroid}/lib/$lib ]; then
              cp -aL ${waylandAndroid}/lib/$lib $out/lib/
            fi
          done
          runHook postInstall
        '';
        meta = {
          description = "Weston Wayland compositor (Android/Termux process)";
          homepage = "https://gitlab.freedesktop.org/wayland/weston";
        };
      };

  files = {
    "bin/weston" = "${westonPkg}/bin/weston";
  } // lib.optionalAttrs isAndroid {
    "lib/libwayland-client.so" = "${westonPkg}/lib/libwayland-client.so";
    "lib/libwayland-server.so" = "${westonPkg}/lib/libwayland-server.so";
    "lib/libwayland-cursor.so" = "${westonPkg}/lib/libwayland-cursor.so";
  };
in
packProcessDeb {
  pname = "weston";
  inherit version target files;
  homepage = "https://gitlab.freedesktop.org/wayland/weston";
  description = "Weston Wayland compositor for Wawona (process deb, no App Store patches)";
}
