# tllist header-only for Termux/Android foot+fcft. No App Store patches.
{ nativePkgs }:

let
  version = "1.1.0";
in
nativePkgs.stdenv.mkDerivation {
  pname = "tllist-android";
  inherit version;

  src = nativePkgs.fetchurl {
    url = "https://codeberg.org/dnkl/tllist/archive/${version}.tar.gz";
    hash = "sha256-DntwlKAlUN2AtyQ7z/w2cVULDx2LpiXk3/UlF4J9XSM=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/include $out/lib/pkgconfig
    cp tllist.h $out/include/
    cat > $out/lib/pkgconfig/tllist.pc <<EOF
prefix=$out
libdir=$out/lib
includedir=$out/include

Name: tllist
Description: Typed linked list C header library
Version: ${version}
Cflags: -I$out/include
EOF
  '';

  meta = {
    description = "tllist headers for Termux Wayland clients";
    homepage = "https://codeberg.org/dnkl/tllist";
  };
}
