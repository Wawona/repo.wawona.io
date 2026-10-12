# libevdev for Termux aarch64 via Android NDK (libinput). No App Store patches.
{ nativePkgs, androidNdk }:

nativePkgs.stdenv.mkDerivation {
  pname = "libevdev-android";
  inherit (nativePkgs.libevdev) version src;

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [
    meson
    ninja
    pkg-config
    python3
  ];

  # Bionic folds librt into libc; meson still probes -lrt.
  # host_machine.system()=android picks broken android/input.h; use Linux UAPI.
  postPatch = ''
    substituteInPlace meson.build \
      --replace-fail "cc.find_library('rt')" "cc.find_library('c')" \
      || sed -i "s/find_library('rt')/find_library('c')/g" meson.build
    mkdir -p include/linux/android
    cp include/linux/linux/input.h include/linux/android/
    cp include/linux/linux/input-event-codes.h include/linux/android/
  '';

  configurePhase = ''
    runHook preConfigure
    meson setup build \
      --cross-file=${androidNdk.mesonCrossFile} \
      --prefix=$out \
      --buildtype=release \
      -Ddefault_library=static \
      -Dtests=disabled \
      -Ddocumentation=disabled
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
    description = "libevdev for Termux (Bionic, NDK)";
    homepage = "https://www.freedesktop.org/wiki/Software/libevdev/";
  };
}
