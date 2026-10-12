# fcft for Termux aarch64 via Android NDK (foot). No App Store patches.
# Graphem/run shaping off: no harfbuzz in this Termux leaf.
{ nativePkgs, androidNdk }:

let
  inherit (nativePkgs) lib;
  version = "3.3.3";
  pixmanAndroid = import ../pixman-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  tllistAndroid = import ../tllist-android/default.nix {
    inherit nativePkgs;
  };
  freetypeAndroid = import ../freetype-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  fontconfigAndroid = import ../fontconfig-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  expatAndroid = import ../expat-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  pcPath = lib.concatStringsSep ":" [
    "${pixmanAndroid}/lib/pkgconfig"
    "${tllistAndroid}/lib/pkgconfig"
    "${freetypeAndroid}/lib/pkgconfig"
    "${fontconfigAndroid}/lib/pkgconfig"
    "${expatAndroid}/lib/pkgconfig"
  ];
  nativeFile = nativePkgs.writeText "fcft-native.ini" ''
    [binaries]
    c = '${nativePkgs.stdenv.cc}/bin/cc'
    cpp = '${nativePkgs.stdenv.cc}/bin/c++'
    ar = '${nativePkgs.stdenv.cc}/bin/ar'
    strip = 'strip'
    pkg-config = '${nativePkgs.pkg-config}/bin/pkg-config'
  '';
in
nativePkgs.stdenv.mkDerivation {
  pname = "fcft-android";
  inherit version;

  src = nativePkgs.fetchurl {
    url = "https://codeberg.org/dnkl/fcft/archive/${version}.tar.gz";
    hash = "sha256-sMD0pZn0NyNzbIVluLhDN8QZUHfwfxu4uzJSuxOiMGo=";
  };

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    scdoc
  ];

  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH="${pcPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PKG_CONFIG_ALLOW_CROSS=1
    meson setup build \
      --native-file=${nativeFile} \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Ddocs=disabled \
      -Dtest-text-shaping=false \
      -Dgrapheme-shaping=disabled \
      -Drun-shaping=disabled
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
    runHook postInstall
  '';

  meta = {
    description = "fcft for Termux (Bionic, NDK)";
    homepage = "https://codeberg.org/dnkl/fcft";
  };
}
