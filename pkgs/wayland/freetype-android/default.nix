# freetype for Termux aarch64 via Android NDK. No App Store patches.
# harfbuzz/png/brotli off to keep the leaf small; zlib from NDK sysroot.
{ nativePkgs, androidNdk }:

nativePkgs.stdenv.mkDerivation {
  pname = "freetype-android";
  inherit (nativePkgs.freetype) version src;

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
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Dharfbuzz=disabled \
      -Dbrotli=disabled \
      -Dbzip2=disabled \
      -Dpng=disabled \
      -Dzlib=system \
      -Dtests=disabled
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
    description = "freetype for Termux (Bionic, NDK)";
    homepage = "https://freetype.org/";
  };
}
