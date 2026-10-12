# expat for Termux aarch64 via Android NDK (fontconfig). No App Store patches.
{ nativePkgs, androidNdk }:

let
  version = "2.7.3";
in
nativePkgs.stdenv.mkDerivation {
  pname = "expat-android";
  inherit version;

  src = nativePkgs.fetchurl {
    url = "https://github.com/libexpat/libexpat/releases/download/R_2_7_3/expat-${version}.tar.xz";
    hash = "sha256-cd+PQHBqe7CoClNnB56nXZHaT4xlxY7Fm837997Nq58=";
  };

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
      -DEXPAT_SHARED_LIBS=OFF \
      -DEXPAT_BUILD_TOOLS=OFF \
      -DEXPAT_BUILD_EXAMPLES=OFF \
      -DEXPAT_BUILD_TESTS=OFF
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
    description = "expat for Termux (Bionic, NDK)";
    homepage = "https://libexpat.github.io/";
  };
}
