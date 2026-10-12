# cairo for Termux aarch64 via Android NDK. No App Store patches.
{ nativePkgs, androidNdk }:

let
  inherit (nativePkgs) lib;
  pixmanAndroid = import ../pixman-android/default.nix {
    inherit nativePkgs androidNdk;
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
  libpngAndroid = import ../libpng-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  pcPath = lib.concatStringsSep ":" [
    "${pixmanAndroid}/lib/pkgconfig"
    "${freetypeAndroid}/lib/pkgconfig"
    "${fontconfigAndroid}/lib/pkgconfig"
    "${expatAndroid}/lib/pkgconfig"
    "${libpngAndroid}/lib/pkgconfig"
  ];
in
nativePkgs.stdenv.mkDerivation {
  pname = "cairo-android";
  inherit (nativePkgs.cairo) version src;

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    python3
  ];

  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH="${pcPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PKG_CONFIG_ALLOW_CROSS=1
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Dtests=disabled \
      -Dxlib=disabled \
      -Dxcb=disabled \
      -Dquartz=disabled \
      -Dpng=enabled \
      -Dglib=disabled \
      -Dtee=disabled \
      -Dspectre=disabled \
      -Dsymbol-lookup=disabled \
      -Dfreetype=enabled \
      -Dfontconfig=enabled \
      -Dzlib=enabled
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
    description = "cairo for Termux (Bionic, NDK)";
    homepage = "https://www.cairographics.org/";
  };
}
