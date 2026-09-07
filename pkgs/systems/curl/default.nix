{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "curl";
  version = "8.4.0";

  src = pkgs.fetchurl {
    url = "https://curl.se/download/curl-${version}.tar.xz";
    sha256 = "16c3761ad383fa3e30f0d7e6717a6a48d88e70a39ab99eb4e24eb2e3a17e0e7a";
  };

  buildInputs = with pkgs; [ openssl zlib ];

  meta = {
    description = "Command line tool for transferring data with URL syntax";
    homepage = "https://curl.se";
  };

  sileo = {
    maintainers = [ "aspauldingcode" ];
  };
}
