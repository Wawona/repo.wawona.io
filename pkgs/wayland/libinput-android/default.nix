# libinput for Termux aarch64 via Android NDK. No App Store patches.
# Uses libudev-zero (no systemd). mtdev/libwacom off.
{ nativePkgs, androidNdk }:

let
  inherit (nativePkgs) lib;
  libudevZero = import ../libudev-zero-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  libevdevAndroid = import ../libevdev-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  pcPath = lib.concatStringsSep ":" [
    "${libudevZero}/lib/pkgconfig"
    "${libevdevAndroid}/lib/pkgconfig"
  ];
in
nativePkgs.stdenv.mkDerivation {
  pname = "libinput-android";
  inherit (nativePkgs.libinput) version src;

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    python3
  ];

  # Bionic: index/rindex are not in the default C library headers.
  postPatch = ''
    sed -i 's/\brindex(/strrchr(/g; s/\bindex(/strchr(/g' \
      src/util-strings.c src/util-prop-parsers.c
  '';

  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH="${pcPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PKG_CONFIG_ALLOW_CROSS=1
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Dlibwacom=false \
      -Dmtdev=false \
      -Ddebug-gui=false \
      -Dtests=false \
      -Ddocumentation=false \
      -Dcoverity=false
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export PKG_CONFIG_PATH="${pcPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    meson install -C build
    # libinput.h includes <libudev.h>; ship a copy so consumers need no extra -I.
    cp ${libudevZero}/include/libudev.h $out/include/libudev.h
    runHook postInstall
  '';

  meta = {
    description = "libinput for Termux (Bionic, NDK, libudev-zero)";
    homepage = "https://www.freedesktop.org/wiki/Software/libinput/";
  };
}
