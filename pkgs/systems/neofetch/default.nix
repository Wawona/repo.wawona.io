{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "neofetch";
  version = "7.1.0";

  src = pkgs.fetchurl {
    url = "https://github.com/dylanaraps/neofetch/archive/refs/tags/${version}.tar.gz";
    sha256 = "sha256-WKlea3FOQe/IBOyjiaIjMJFpst7zXlf6k0SCprR8J+c=";
  };

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp neofetch $out/bin/
    chmod +x $out/bin/neofetch
  '';

  meta = {
    description = "A command-line system information tool written in bash 3.2+";
    homepage = "https://github.com/dylanaraps/neofetch";
  };

  sileo = {
    maintainers = [ "aspauldingcode" ];
  };
}
