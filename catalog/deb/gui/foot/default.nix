# Upstream foot terminal as a process deb. No App Store patches.
# Not foot_main in-process archive.
# linux: pack nixpkgs foot. android: NDK/Bionic meson (Termux).
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
  version = if isAndroid then nativePkgs.foot.version else pkgs.foot.version;

  ndkLibs = import ../../../../pkgs/wayland/ndkLibs.nix { inherit nativePkgs; };
  androidNdk = ndkLibs.ndk;
  waylandAndroid = ndkLibs.libs.wayland;
  androidPcPath = ndkLibs.pcPath [
    "wayland"
    "pixman"
    "tllist"
    "freetype"
    "fontconfig"
    "expat"
    "fcft"
    "xkbcommon"
  ];

  footBin =
    if !isAndroid then pkgs.foot
    else
      nativePkgs.stdenv.mkDerivation {
        pname = "foot-android";
        inherit version;
        src = nativePkgs.foot.src;
        patches = nativePkgs.foot.patches or [ ];
        dontPatchELF = true;
        dontStrip = true;
        nativeBuildInputs = with nativePkgs; [
          meson
          ninja
          pkg-config
          wayland-scanner
          scdoc
        ];
        configurePhase = ''
          runHook preConfigure
          export PKG_CONFIG_PATH="${androidPcPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
          export PKG_CONFIG_PATH_FOR_BUILD="${nativePkgs.wayland-scanner.dev}/lib/pkgconfig''${PKG_CONFIG_PATH_FOR_BUILD:+:$PKG_CONFIG_PATH_FOR_BUILD}"
          export PKG_CONFIG_ALLOW_CROSS=1
          export WAYLAND_PROTOCOLS_DATADIR=${nativePkgs.wayland-protocols}/share/wayland-protocols
          meson setup build \
            --cross-file=${androidNdk.mesonCrossFile} \
            --prefix=$out \
            -Dc_link_args=-Wl,-rpath,/data/data/com.termux/files/usr/lib \
            -Ddocs=disabled \
            -Dthemes=false \
            -Dtests=false \
            -Dgrapheme-clustering=disabled \
            -Dutmp-backend=none \
            -Dterminfo=disabled
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
          # Ship shared Wayland client/cursor for Termux rpath.
          mkdir -p $out/lib
          for lib in libwayland-client.so libwayland-cursor.so; do
            if [ -e ${waylandAndroid}/lib/$lib ]; then
              cp -aL ${waylandAndroid}/lib/$lib $out/lib/
            fi
          done
          runHook postInstall
        '';
        meta = {
          description = "Foot Wayland terminal (Android/Termux process)";
          homepage = "https://codeberg.org/dnkl/foot";
        };
      };

  files = {
    "bin/foot" = "${footBin}/bin/foot";
  } // lib.optionalAttrs isAndroid {
    "lib/libwayland-client.so" = "${footBin}/lib/libwayland-client.so";
    "lib/libwayland-cursor.so" = "${footBin}/lib/libwayland-cursor.so";
  };
in
packProcessDeb {
  pname = "foot";
  inherit version target files;
  homepage = "https://codeberg.org/dnkl/foot";
  description = "Foot Wayland terminal for Wawona (process deb, no App Store patches)";
}
