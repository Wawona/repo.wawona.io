# libdisplay-info for Termux aarch64 via Android NDK (weston). No App Store patches.
{ nativePkgs, androidNdk }:

nativePkgs.stdenv.mkDerivation {
  pname = "libdisplay-info-android";
  inherit (nativePkgs.libdisplay-info) version src;

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    python3
    hwdata
  ];

  configurePhase = ''
    runHook preConfigure
    # Native hwdata for pnp.ids codegen (not Android).
    export PKG_CONFIG_PATH_FOR_BUILD="${nativePkgs.hwdata}/share/pkgconfig''${PKG_CONFIG_PATH_FOR_BUILD:+:$PKG_CONFIG_PATH_FOR_BUILD}"
    export PKG_CONFIG_PATH="${nativePkgs.hwdata}/share/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Dwerror=false
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
    description = "libdisplay-info for Termux (Bionic, NDK)";
    homepage = "https://gitlab.freedesktop.org/emersion/libdisplay-info";
  };
}
