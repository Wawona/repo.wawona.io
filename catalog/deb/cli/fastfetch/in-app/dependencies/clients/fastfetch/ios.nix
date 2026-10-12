args:
let
  fastfetchSrc = import ./common.nix { pkgs = args.pkgs; };
in
import ./apple-mobile.nix (args // { inherit fastfetchSrc; })
