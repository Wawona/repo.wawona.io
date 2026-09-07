{ pkgs, mkWawonaPackage, target ? "ios" }:

let
  prefix = if target == "android" then "/data/data/com.termux/files/usr" else "/var/jb";
in
mkWawonaPackage rec {
  pname = "libiosexec";
  version = "1.3.1";

  src = pkgs.fetchFromGitHub {
    owner = "roothide";
    repo = "libiosexec";
    rev = "54a0866ed9b25adf252d20b9e0366280be4e29d3";
    sha256 = "008k883yvk9kkljk62jz4v49phr0cad5ky6c4vdxazgxz0lv4vbr";
  };

  preBuild = ''
    sed -i 's/$(shell uname -s)/Darwin/g' Makefile
  '';

  installPhase = if target == "ios" then ''
    make install DESTDIR=$out \
      SHEBANG_REDIRECT_PATH="${prefix}" \
      LIBIOSEXEC_PREFIXED_ROOT=1 \
      DEFAULT_PATH_PREFIX="${prefix}" \
      DEFAULT_INTERPRETER="${prefix}/bin/sh"
  '' else ''
    make install DESTDIR=$out \
      DEFAULT_PATH_PREFIX="${prefix}"
  '';

  sileo = {
    package = "io.wawona.libiosexec";
    architecture = "iphoneos-arm64e"; # RootHide compatible
    description = "Library for iOS shebang execution and process management";
    maintainers = [ "aspauldingcode" ];
  };
}
