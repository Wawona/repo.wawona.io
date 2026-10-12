# libffi for Termux aarch64 via Android NDK.
{ nativePkgs, androidNdk }:

let
  version = "3.4.6";
in
nativePkgs.stdenv.mkDerivation {
  pname = "libffi-android";
  inherit version;

  # Release tarball has configure; git/nixpkgs src needs autogen + hits
  # Darwin host multilib confusion.
  src = nativePkgs.fetchurl {
    url = "https://github.com/libffi/libffi/releases/download/v${version}/libffi-${version}.tar.gz";
    hash = "sha256-sN6p3yPIY6elDoJUQPPr/6vWXfFJcQjl1Dd0eEOJWk4=";
  };

  strictDeps = true;
  nativeBuildInputs = [ nativePkgs.pkg-config ];

  dontAddPrefix = true;
  configurePhase = ''
    runHook preConfigure
    mkdir -p build && cd build
    ../configure \
      --build=aarch64-apple-darwin \
      --host=aarch64-linux-android \
      --prefix=$out \
      --disable-multi-os-directory \
      --disable-docs \
      --disable-shared \
      --enable-static \
      CC=${androidNdk.cc} \
      AR=${androidNdk.ar} \
      RANLIB=${androidNdk.prebuilt}/bin/llvm-ranlib \
      STRIP=${androidNdk.strip} \
      CFLAGS="--sysroot=${androidNdk.sysroot} -fPIC" \
      LDFLAGS="--sysroot=${androidNdk.sysroot}"
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install
    runHook postInstall
  '';

  meta = {
    description = "libffi for Termux (Bionic, NDK)";
    homepage = "https://sourceware.org/libffi/";
  };
}
