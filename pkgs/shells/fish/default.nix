{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "fish";
  version = "3.6.1";

  src = pkgs.fetchurl {
    url = "https://github.com/fish-shell/fish-shell/releases/download/${version}/fish-${version}.tar.xz";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  buildInputs = with pkgs; [ ncurses pcre2 ];

  sileo = {
    package = "io.wawona.fish";
    architecture = "iphoneos-arm64";
    description = "User-friendly command line shell for iOS";
    maintainers = [ "aspauldingcode" ];
  };
}
