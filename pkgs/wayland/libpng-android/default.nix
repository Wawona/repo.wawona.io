# libpng for Termux aarch64 via Android NDK. No App Store patches.
{ nativePkgs, androidNdk }:

nativePkgs.stdenv.mkDerivation {
  pname = "libpng-android";
  inherit (nativePkgs.libpng) version src;

  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = with nativePkgs; [ cmake pkg-config ];

  dontUseCmakeConfigure = true;

  configurePhase = ''
    runHook preConfigure
    cmake -S . -B build \
      -DCMAKE_SYSTEM_NAME=Android \
      -DCMAKE_SYSTEM_VERSION=${androidNdk.apiLevel} \
      -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
      -DCMAKE_ANDROID_NDK=${androidNdk.ndkRoot} \
      -DCMAKE_C_COMPILER=${androidNdk.cc} \
      -DCMAKE_CXX_COMPILER=${androidNdk.cxx} \
      -DCMAKE_AR=${androidNdk.ar} \
      -DCMAKE_STRIP=${androidNdk.strip} \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-fPIC" \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DPNG_SHARED=OFF \
      -DPNG_STATIC=ON \
      -DPNG_TESTS=OFF \
      -DPNG_TOOLS=OFF \
      -DPNG_EXECUTABLES=OFF \
      -DPNG_ARM_NEON=off \
      -DZLIB_INCLUDE_DIR=${androidNdk.sysroot}/usr/include \
      -DZLIB_LIBRARY=${androidNdk.sysroot}/usr/lib/aarch64-linux-android/libz.a
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build
    runHook postInstall
  '';

  meta = {
    description = "libpng for Termux (Bionic, NDK)";
    homepage = "http://www.libpng.org/pub/png/libpng.html";
  };
}
