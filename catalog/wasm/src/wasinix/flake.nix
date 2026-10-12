{
  description = "WASIX package repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    wasix = import ./pkgs {
      inherit system nixpkgs;
    };
  in {
    wasix = {
      inherit (wasix) toolchains libraries programs defaultProfileName;
    };

    wasmer = wasix.wasmer.packages;
    legacyPackages.${system} = {
      pkgsCross = {
        wasix = wasix.pkgsCross;
      };
    };

    devShells.${system}.default = wasix.pkgs.mkShell {
      packages = [
        wasix.toolchains.${wasix.defaultProfileName}.wasixcc
        wasix.toolchains.${wasix.defaultProfileName}.cargoWasix
        wasix.libraries.${wasix.defaultProfileName}.ncurses
        wasix.pkgs.gnumake
        wasix.pkgs.pkg-config
      ];
      shellHook = ''
        ${wasix.toolchains.${wasix.defaultProfileName}.toolchainEnv}
        ${wasix.toolchains.${wasix.defaultProfileName}.ccEnv}
        echo "WASIX shell ready. Build with: nix build"
      '';
    };

    packages.${system} = {
      wasixAll = wasix.allWasm;
      wasmerAll = wasix.wasmer.allWasmer;
      # Alias used by CI / docs (`nix build .#all`).
      all = wasix.wasmer.allWasmer;
      default = wasix.allWasm;

      cargo-wasix = wasix.toolchains.${wasix.defaultProfileName}.cargoWasix;
      wasixcc = wasix.toolchains.${wasix.defaultProfileName}.wasixcc;
      php83ZTS = wasix.libraries.${wasix.defaultProfileName}.php83ZTS;
      php85ZTS = wasix.libraries.${wasix.defaultProfileName}.php85ZTS;
      phpixPhp83 = wasix.programs.phpixPhp83;
      phpixPhp85 = wasix.programs.phpixPhp85;
    };
  };
}
