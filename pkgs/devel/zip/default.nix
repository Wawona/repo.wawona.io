{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "zip";
  version = "3.0";

  src = pkgs.fetchurl {
    url = "https://deb.debian.org/debian/pool/main/z/zip/zip_3.0.orig.tar.gz";
    sha256 = "sha256-8Oi7H5t+sLAShUlaJpnfOkt2Z4TBdlqPGu7fY8CAY2k=";
  };

  buildInputs = [ pkgs.bzip2 ];
  nativeBuildInputs = [ pkgs.buildPackages.clang ];

  makeFlags = [ "-f" "unix/Makefile" "generic" "LFLAGS2=-lbz2" "CFLAGS=-I. -DUNIX -DBZIP2_SUPPORT -Wno-deprecated-non-prototype" ];

  installPhase = ''
    make -f unix/Makefile install prefix=$out
  '';

  sileo = {
    maintainers = [ "aspauldingcode" ];
  };
}
