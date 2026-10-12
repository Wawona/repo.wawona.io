# libdrm for Termux aarch64 via Android NDK (headers + core). No App Store patches.
# GPU ICDs off: Weston needs drm headers even for nested Wayland backend.
{ nativePkgs, androidNdk }:

nativePkgs.stdenv.mkDerivation {
  pname = "libdrm-android";
  inherit (nativePkgs.libdrm) version src;

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
      -Dintel=disabled \
      -Dradeon=disabled \
      -Damdgpu=disabled \
      -Dnouveau=disabled \
      -Dvmwgfx=disabled \
      -Dfreedreno=disabled \
      -Detnaviv=disabled \
      -Dvc4=disabled \
      -Dcairo-tests=disabled \
      -Dman-pages=disabled \
      -Dvalgrind=disabled \
      -Dtests=false \
      -Dudev=false
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
    description = "libdrm for Termux (Bionic, NDK)";
    homepage = "https://gitlab.freedesktop.org/mesa/drm";
  };
}
