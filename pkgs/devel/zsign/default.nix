{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "zsign";
  version = "0.20220120.27016df";

  src = pkgs.fetchFromGitHub {
    owner = "zhlynn";
    repo = "zsign";
    rev = "27016df3328ce784407817926868af2d96929a00";
    sha256 = "sha256-DXUJ9WfRK/n+iSXOz6sly6bdZOXGzlyPj0B3pfrlX+8=";
  };

  buildInputs = [ pkgs.openssl ];

  buildPhase = ''
    $CXX $CXXFLAGS -O2 -I${pkgs.openssl.dev}/include *.cpp common/*.cpp -L${pkgs.openssl.out}/lib -lcrypto -lpthread -o zsign
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp zsign $out/bin/
  '';

  sileo = {
    package = "io.wawona.zsign";
    description = "A powerful tool for signing iOS apps";
    maintainers = [ "aspauldingcode" ];
  };
}
