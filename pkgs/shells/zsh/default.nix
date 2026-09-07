{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "zsh";
  version = "5.9";

  src = pkgs.fetchurl {
    url = "https://www.zsh.org/pub/zsh-${version}.tar.xz";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  buildInputs = with pkgs; [ ncurses readline pcre ];

  sileo = {
    package = "io.wawona.zsh";
    architecture = "iphoneos-arm64";
    description = "Powerful shell with lots of features for iOS";
    maintainers = [ "aspauldingcode" ];
  };
}
