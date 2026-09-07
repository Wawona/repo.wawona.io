{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "xorg-server";
  version = pkgs.xorg.xorgserver.version;
  src = pkgs.xorg.xorgserver.src;
  
  buildInputs = pkgs.xorg.xorgserver.buildInputs;

  sileo = {
    maintainers = [ "aspauldingcode" ];
  };
}
