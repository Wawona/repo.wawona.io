# pixman for Termux aarch64 via Android NDK. No App Store patches.
{ nativePkgs, androidNdk }:

nativePkgs.stdenv.mkDerivation {
  pname = "pixman-android";
  inherit (nativePkgs.pixman) version src;

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
  ];

  configurePhase = ''
    runHook preConfigure
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Dopenmp=disabled \
      -Dgtk=disabled \
      -Dtests=disabled \
      -Ddemos=disabled
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
    description = "pixman for Termux (Bionic, NDK)";
    homepage = "https://pixman.org";
  };
}
