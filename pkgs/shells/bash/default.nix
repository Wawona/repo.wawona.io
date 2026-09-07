{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "bash";
  version = "5.2.15";

  src = pkgs.fetchurl {
    url = "mirror://gnu/bash/bash-5.2.15.tar.gz";
    sha256 = "132qng0jy600mv1fs95ylnlisx2wavkkgpb19c6kmz7lnmjhjwhk";
  };

  buildInputs = with pkgs; [ ncurses readline ];

  configureFlags = [
    "--enable-static-link"
    "--disable-nls"
    "--without-bash-malloc"
  ];

  sileo = {
    package = "io.wawona.bash";
    architecture = "iphoneos-arm64";
    description = "Wawona port of GNU Bash shell for iOS";
    maintainers = [ "aspauldingcode" ];
  };
}
