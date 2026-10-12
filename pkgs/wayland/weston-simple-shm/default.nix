# Minimal wl_shm Wayland client as a process deb. No App Store patches.
# No renamed weston_simple_shm_main. Connects to WAYLAND_DISPLAY / Wawona.
# Targets: linux (/usr) and android Termux (/data/data/com.termux/files/usr).
# Android uses Google NDK clang (Bionic). Never pack a glibc Linux ELF.
{ pkgs
, nativePkgs
, mkDebFromBins
, packProcessDeb
, target ? "linux"
, jailbreakScheme ? null
}:

assert target == "linux" || target == "android";

let
  inherit (pkgs) lib;
  version = "1.0.0";
  srcDir = ./.;
  isAndroid = target == "android";

  buildPkgs = if isAndroid then nativePkgs else (pkgs.buildPackages or pkgs);

  ndkLibs = import ../ndkLibs.nix { inherit nativePkgs; };
  androidNdk = ndkLibs.ndk;
  waylandAndroid = ndkLibs.libs.wayland;

  # Host wayland-scanner + protocols for codegen. Target wayland for link.
  simpleShmBin =
    if !isAndroid then
      pkgs.stdenv.mkDerivation {
        pname = "weston-simple-shm";
        inherit version;
        src = srcDir;
        strictDeps = true;
        nativeBuildInputs = with buildPkgs; [ pkg-config wayland-scanner ];
        buildInputs = with pkgs; [ wayland wayland-protocols ];
        NIX_LDFLAGS = "-lrt";
        buildPhase = ''
          runHook preBuild
          wayland-scanner client-header \
            ${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
            xdg-shell-client-protocol.h
          wayland-scanner private-code \
            ${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
            xdg-shell-protocol.c
          $CC -O2 -Wall -o weston-simple-shm \
            simple-shm.c xdg-shell-protocol.c \
            $(pkg-config --cflags --libs wayland-client)
          runHook postBuild
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp weston-simple-shm $out/bin/
        '';
        meta = {
          description = "Minimal wl_shm Wayland client for Wawona (process)";
          homepage = "https://wayland.freedesktop.org";
        };
      }
    else
      nativePkgs.stdenv.mkDerivation {
        pname = "weston-simple-shm-android";
        inherit version;
        src = srcDir;
        strictDeps = true;
        dontPatchELF = true;
        dontStrip = true;
        nativeBuildInputs = with nativePkgs; [ pkg-config wayland-scanner ];
        # Headers/libs from NDK-built wayland. Scanner from host nixpkgs.
        buildPhase = ''
          runHook preBuild
          wayland-scanner client-header \
            ${nativePkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
            xdg-shell-client-protocol.h
          wayland-scanner private-code \
            ${nativePkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
            xdg-shell-protocol.c
          ${androidNdk.cc} -O2 -Wall -o weston-simple-shm \
            simple-shm.c xdg-shell-protocol.c \
            -I${waylandAndroid}/include \
            -L${waylandAndroid}/lib \
            -lwayland-client \
            -Wl,-rpath,/data/data/com.termux/files/usr/lib
          runHook postBuild
        '';
        installPhase = ''
          mkdir -p $out/bin $out/lib
          cp weston-simple-shm $out/bin/
          # Ship Bionic libwayland-client (real file or symlink target).
          if [ -e ${waylandAndroid}/lib/libwayland-client.so ]; then
            cp -aL ${waylandAndroid}/lib/libwayland-client.so $out/lib/
          else
            real=$(ls ${waylandAndroid}/lib/libwayland-client.so.* | head -1)
            cp -aL "$real" $out/lib/libwayland-client.so
          fi
        '';
        meta = {
          description = "Minimal wl_shm Wayland client for Termux (Bionic process)";
          homepage = "https://wayland.freedesktop.org";
        };
      };

  binDest = "bin/weston-simple-shm";
  # Avoid IFD on $out/lib. Ship the unversioned .so; ELF DT_NEEDED resolves it.
  files = {
    "${binDest}" = "${simpleShmBin}/bin/weston-simple-shm";
  } // lib.optionalAttrs isAndroid {
    "lib/libwayland-client.so" = "${simpleShmBin}/lib/libwayland-client.so";
  };
in
packProcessDeb {
  pname = "weston-simple-shm";
  inherit version target files;
  homepage = "https://wayland.freedesktop.org";
  description = "weston-simple-shm Wayland client for Wawona (process deb, no App Store patches)";
}
