{
  description = "wwn-foot: Wawona's foot terminal port, cross-compiled in-process for Apple platforms and Android.";

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
      darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      allSystems = darwinSystems ++ linuxSystems;
      forAll = nixpkgs.lib.genAttrs allSystems;
      inherit (wwn-toolchain.lib) withPlatformVariants baseRegistry mkToolchains;

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = { allowUnfree = true; allowUnsupportedSystem = true; android_sdk.accept_license = true; };
      };

      footDir = ./dependencies/clients/foot;
    in
    {
      registryFragment = {
        foot = withPlatformVariants {
          android = footDir + "/android.nix";
          wearos = footDir + "/wearos.nix";
          # All Apple mobile targets share apple-mobile.nix (real foot_main +
          # wawona-pty). No weston-terminal shim.
          ios = footDir + "/ios.nix";
          tvos = footDir + "/tvos.nix";
          ipados = footDir + "/ipados.nix";
          visionos = footDir + "/visionos.nix";
          watchos = footDir + "/watchos.nix";
          macos = footDir + "/macos.nix";
        };
      };

      packages = forAll (system:
        let
          pkgs = pkgsFor system;
          tc = mkToolchains { inherit pkgs; registry = baseRegistry // self.registryFragment; };
          isDarwin = builtins.elem system darwinSystems;
        in
        (if isDarwin then {
          foot-ios = tc.buildForIOS "foot" { };
          foot-ios-sim = tc.buildForIOS "foot" { simulator = true; };
          foot-macos = tc.buildForMacOS "foot" { };
          # Android/wearOS need androidSDK via Wawona's mkToolchains
          # (packages.*.foot-android). Match wwn-niri: do not expose here.
        } else { }));

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
