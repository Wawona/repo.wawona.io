# libxkbcommon for Termux aarch64 via Android NDK. No App Store patches.
# No X11 / Wayland / xkbregistry (no libxml2). Foot only needs xkbcommon core.
{ nativePkgs, androidNdk }:

let
  version = "1.11.0";
in
nativePkgs.stdenv.mkDerivation {
  pname = "xkbcommon-android";
  inherit version;

  src = nativePkgs.libxkbcommon.src;

  dontPatchELF = true;
  dontStrip = true;

  postPatch = ''
    # Bionic has strndup; meson probe can miss it under NDK cross.
    if [ -f src/utils.h ]; then
      substituteInPlace src/utils.h \
        --replace-fail \
          '#if !(defined(HAVE_STRNDUP) && HAVE_STRNDUP)' \
          '#if !(defined(HAVE_STRNDUP) && HAVE_STRNDUP) && !defined(__BIONIC__)' \
        || true
    fi
  '';

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    python3
    bison
  ];

  configurePhase = ''
    runHook preConfigure
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Denable-docs=false \
      -Denable-tools=false \
      -Denable-x11=false \
      -Denable-wayland=false \
      -Denable-xkbregistry=false
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
    description = "libxkbcommon for Termux (Bionic, NDK)";
    homepage = "https://xkbcommon.org/";
  };
}
