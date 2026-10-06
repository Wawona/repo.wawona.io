{ self, pkgs, nativePkgs, target ? "ios" }:

let
  mkWawonaPackage = import ../lib/mkWawonaPackage.nix {
    inherit (pkgs) lib stdenv;
    inherit (nativePkgs) dpkg coreutils;
  };

  # Xcode iphoneos compile (xcrun). Do not use the iOS-cross stdenv: it
  # rebuilds a Darwin bootstrap just to run clang that we already replace.
  mkHostWawonaPackage = import ../lib/mkWawonaPackage.nix {
    inherit (nativePkgs) lib stdenv dpkg coreutils;
  };

  # Common packages
  packages = rec {
    hello = import ./devel/hello/default.nix { inherit pkgs mkWawonaPackage target; };
    libiosexec = import ./systems/libiosexec/default.nix { inherit pkgs mkWawonaPackage target; };
    bash = import ./shells/bash/default.nix { inherit pkgs mkWawonaPackage target; };
    fish = import ./shells/fish/default.nix { inherit pkgs mkWawonaPackage target; };
    zsh = import ./shells/zsh/default.nix { inherit pkgs mkWawonaPackage target; };
    neovim = import ./devel/neovim/default.nix { inherit pkgs mkWawonaPackage target; };
    curl = import ./systems/curl/default.nix { inherit pkgs mkWawonaPackage target; };
    neofetch = import ./systems/neofetch/default.nix { inherit pkgs mkWawonaPackage target; };
    system-cmds = import ./systems/system-cmds/default.nix { 
      inherit pkgs mkWawonaPackage libiosexec target;
    };
    apr = import ./devel/apr/default.nix { inherit pkgs mkWawonaPackage target; };
    zip = import ./devel/zip/default.nix { inherit pkgs mkWawonaPackage target; };
    zsign = import ./devel/zsign/default.nix { inherit pkgs mkWawonaPackage target; };
    xorg-server = import ./x11/xorg-server/default.nix { inherit pkgs mkWawonaPackage target; };
  } // pkgs.lib.optionalAttrs (target == "ios") {
    launchctl = import ./systems/launchctl/default.nix {
      inherit target;
      pkgs = nativePkgs;
      mkWawonaPackage = mkHostWawonaPackage;
      jailbreakScheme = "rootless";
    };
    launchctl-rootful = import ./systems/launchctl/default.nix {
      inherit target;
      pkgs = nativePkgs;
      mkWawonaPackage = mkHostWawonaPackage;
      jailbreakScheme = "rootful";
    };
  };

  # Aggregate all packages into a single derivation for easy "build everything"
  all = pkgs.linkFarm "${target}-all-packages" (
    pkgs.lib.mapAttrsToList (name: drv: { name = name; path = drv; }) packages
  );

in
packages // { inherit all; }
