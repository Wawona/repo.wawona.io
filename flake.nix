{
  description = "Wawona Nix flake for iOS jailbreak packages (converted from Procursus-roothide)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    inherit (nixpkgs) lib;
    darwinHost = "aarch64-darwin";
    checkSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];

    nativePkgsFor = system: import nixpkgs { inherit system; };

    # Cross recipes need Xcode / Darwin. Do not import them at flake eval for
    # Linux checks; Gate: packages uses python3 --offline instead.
    mkDarwinPackages = hostSystem:
      let
        nativePkgs = nativePkgsFor hostSystem;
        pkgsIOS = import nixpkgs {
          system = hostSystem;
          crossSystem = {
            config = "aarch64-apple-ios";
            isStatic = true;
            sdkVer = "15.5";
          };
          overlays = [
            (final: prev: {
              Libc = prev.Libc.overrideAttrs (oldAttrs: {
                preConfigure = ''
                  export SDKROOT=${prev.apple_sdk.sdkPath}
                '';
              });
            })
          ];
        };
        pkgsAndroid = import nixpkgs {
          system = hostSystem;
          crossSystem = {
            config = "aarch64-unknown-linux-android";
            androidSdkVersion = "33";
          };
        };
        iosPackages = import ./pkgs/top-level.nix {
          inherit self nativePkgs;
          pkgs = pkgsIOS;
          target = "ios";
        };
        androidPackages = import ./pkgs/top-level.nix {
          inherit self nativePkgs;
          pkgs = pkgsAndroid;
          target = "android";
        };
      in {
        ios = iosPackages.all;
        android = androidPackages.all;
        ios-pkgs = iosPackages;
        android-pkgs = androidPackages;
        hello = iosPackages.hello;
      };
  in {
    packages.${darwinHost} = mkDarwinPackages darwinHost;

    devShells.${darwinHost}.default = (nativePkgsFor darwinHost).mkShell {
      buildInputs = with (nativePkgsFor darwinHost); [
        clang
        dpkg
        gnused
        coreutils
      ];
      shellHook = ''
        echo "Wawona Multi-Platform Flake. Targets: iOS (Rootless/Roothide), Android (Termux)"
      '';
    };

    apps.${darwinHost} = {
      update = {
        type = "app";
        program = "${(nativePkgsFor darwinHost).writeShellScript "update-repo" ''
          export PATH="${(nativePkgsFor darwinHost).lib.makeBinPath (with (nativePkgsFor darwinHost); [ dpkg gnused coreutils gnugrep findutils ])}:$PATH"
          ./scripts/update.sh
        ''}";
      };
    };

    checks = lib.genAttrs checkSystems (system:
      let pkgs = nativePkgsFor system;
      in {
        packages-offline = pkgs.runCommand "repo-wawona-io-packages-offline" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
          python3 ${self}/scripts/check-packages.py --root ${self} --offline
          mkdir "$out"
        '';
      });
  };
}
