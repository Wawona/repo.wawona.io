# libwayland (client) for Termux aarch64 via Android NDK. No App Store patches.
{ nativePkgs, androidNdk }:

let
  inherit (nativePkgs) lib;
  waylandSrc = nativePkgs.wayland.src;
  version = nativePkgs.wayland.version;
  libffiAndroid = import ../libffi-android/default.nix {
    inherit nativePkgs androidNdk;
  };
in
nativePkgs.stdenv.mkDerivation {
  pname = "wayland-android";
  inherit version;
  src = waylandSrc;

  # Android ELF; Darwin host patchelf/strip are wrong tools.
  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    wayland-scanner # Darwin-safe; full wayland is badPlatforms on Darwin
    python3
  ];

  # Host scanner only. Link against NDK Bionic; do not use Darwin libs.
  depsBuildBuild = [ nativePkgs.buildPackages.stdenv.cc ];

  configurePhase = ''
    runHook preConfigure
    mkdir -p build
    # Target libffi + native wayland-scanner.pc (meson native: true dep).
    export PKG_CONFIG_PATH="${libffiAndroid}/lib/pkgconfig:${nativePkgs.wayland-scanner.dev}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PKG_CONFIG_PATH_FOR_BUILD="${nativePkgs.wayland-scanner.dev}/lib/pkgconfig''${PKG_CONFIG_PATH_FOR_BUILD:+:$PKG_CONFIG_PATH_FOR_BUILD}"
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      -Ddocumentation=false \
      -Dtests=false \
      -Ddtd_validation=false \
      -Dscanner=false
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
    description = "Wayland client libraries for Termux (Bionic, NDK)";
    homepage = "https://wayland.freedesktop.org";
  };
}
