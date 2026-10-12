{
  description = "wwn-phoon-rs: clean-room Rust reimplementation reproducing the terminal output of the historical `phoon` moon-phase utility. Ships an in-process static lib (libphoon_rs.a / .so) exporting a C ABI (phoon_main) plus a standalone `phoon` CLI, cross-compiled for Apple platforms and Android.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.url = "https://flakehub.com/f/Wawona/wwn-toolchain/*";
    wwn-toolchain.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.inputs.rust-overlay.follows = "rust-overlay";
  };

  outputs = { self, nixpkgs, rust-overlay, wwn-toolchain, ... }:
    let
      # Nixpkgs 26.11 throws on x86_64-darwin eval; flakehub-push always runs
      # `nix flake show --all-systems`. Intel Mac still builds via Wawona's
      # registry merge with its own pkgs.
      darwinSystems = [ "aarch64-darwin" ];
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      allSystems = darwinSystems ++ linuxSystems;
      forAll = nixpkgs.lib.genAttrs allSystems;
      inherit (wwn-toolchain.lib) withPlatformVariants baseRegistry mkToolchains;

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = { allowUnfree = true; allowUnsupportedSystem = true; android_sdk.accept_license = true; };
      };

      phDir = ./dependencies/libs/phoon;
    in
    {
      registryFragment = {
        phoon = withPlatformVariants {
          android = phDir + "/android.nix";
          wearos = phDir + "/wearos.nix";
          ios = phDir + "/ios.nix";
          tvos = phDir + "/tvos.nix";
          ipados = phDir + "/ipados.nix";
          visionos = phDir + "/visionos.nix";
          watchos = phDir + "/watchos.nix";
          macos = phDir + "/macos.nix";
          linux = phDir + "/linux.nix";
        };
      };

      # Consumed by Wawona's flake to link the in-process phoon lib.
      lib = {
        phoonSrc = pkgs: import (phDir + "/phoon-src.nix") { inherit pkgs; };
        srcRecipe = phDir + "/phoon-src.nix";
        # Convenience wrapper: builds the platform static lib via the toolchain.
        mkPhoon = { pkgs, platform ? "macos", extraArgs ? { } }:
          let
            tc = mkToolchains { inherit pkgs; registry = baseRegistry // self.registryFragment; inherit extraArgs; };
            fn = {
              macos = tc.buildForMacOS;
              ios = tc.buildForIOS;
              ipados = tc.buildForIPadOS;
              tvos = tc.buildForTVOS;
              watchos = tc.buildForWatchOS;
              visionos = tc.buildForVisionOS;
              android = tc.buildForAndroid;
              wearos = tc.buildForWearOS;
              linux = tc.buildForLinux;
            }.${platform};
          in
          fn "phoon" { };
      };

      packages = forAll (system:
        let
          pkgs = pkgsFor system;
          tc = mkToolchains { inherit pkgs; registry = baseRegistry // self.registryFragment; };
          isDarwin = builtins.elem system darwinSystems;
          # Host-native CLI: macOS on Darwin, Linux elsewhere. Use this for
          # `nix run .#phoon` / `nix run .` — Nix already knows the host.
          # Mobile cross targets stay under their explicit attrs.
          hostPhoon =
            if isDarwin then tc.buildForMacOS "phoon" { }
            else tc.buildForLinux "phoon" { };
        in {
          phoon = hostPhoon;
          default = hostPhoon;
        } // (if isDarwin then {
          phoon-macos = hostPhoon;
          phoon-ios = tc.buildForIOS "phoon" { };
        } else {
          phoon-linux = hostPhoon;
        }));

      apps = forAll (system: {
        phoon = {
          type = "app";
          program = "${self.packages.${system}.phoon}/bin/phoon";
        };
        default = self.apps.${system}.phoon;
      });

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
