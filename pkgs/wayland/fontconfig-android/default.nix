# fontconfig for Termux aarch64 via Android NDK. No App Store patches.
# Pin 2.17.1: 2.18 needs meson >= 1.11; nixpkgs meson is still 1.10.x.
{ nativePkgs, androidNdk }:

let
  version = "2.17.1";
  freetypeAndroid = import ../freetype-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  expatAndroid = import ../expat-android/default.nix {
    inherit nativePkgs androidNdk;
  };
  nativeFile = nativePkgs.writeText "fontconfig-native.ini" ''
    [binaries]
    c = '${nativePkgs.stdenv.cc}/bin/cc'
    cpp = '${nativePkgs.stdenv.cc}/bin/c++'
    ar = '${nativePkgs.stdenv.cc}/bin/ar'
    strip = 'strip'
    pkg-config = '${nativePkgs.pkg-config}/bin/pkg-config'
  '';
in
nativePkgs.stdenv.mkDerivation {
  pname = "fontconfig-android";
  inherit version;

  src = nativePkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/${version}/fontconfig-${version}.tar.xz";
    hash = "sha256-n1yuk/T//B+8Ba6ZzfxwjNYN/WYS/8BRKCcCXAJvpUE=";
  };

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    python3
    gperf
  ];

  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH="${freetypeAndroid}/lib/pkgconfig:${expatAndroid}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    meson setup build \
      --native-file=${nativeFile} \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Ddoc=disabled \
      -Dnls=disabled \
      -Dtests=disabled \
      -Dtools=disabled \
      -Dcache-build=disabled
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    meson install -C build
    runHook postInstall
  '';

  meta = {
    description = "fontconfig for Termux (Bionic, NDK)";
    homepage = "https://www.freedesktop.org/wiki/Software/fontconfig/";
  };
}
