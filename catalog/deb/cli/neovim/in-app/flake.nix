{
  description = "wwn-neovim: Wawona's Neovim port — App Store–safe in-process on Apple mobile, binaries on macOS/Android.";

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
        config = {
          allowUnfree = true;
          allowUnsupportedSystem = true;
          android_sdk.accept_license = true;
        };
      };

      mkAndroidSDK = system: pkgs:
        let
          androidConfig = import "${wwn-toolchain}/dependencies/android/sdk-config.nix" {
            inherit system;
            lib = pkgs.lib;
          };
          androidComposition = pkgs.androidenv.composeAndroidPackages {
            cmdLineToolsVersion = "latest";
            platformToolsVersion = "latest";
            buildToolsVersions = [ androidConfig.buildToolsVersion ];
            platformVersions = [ (toString androidConfig.compileSdk) ];
            abiVersions = [ androidConfig.hostEmulatorAbi ];
            systemImageTypes = [ "google_apis_playstore" ];
            includeEmulator = androidConfig.emulatorSupported;
            includeSystemImages = androidConfig.emulatorSupported;
            includeNDK = true;
            includeCmake = true;
            ndkVersions = [ androidConfig.ndkVersion ];
            cmakeVersions = [ androidConfig.cmakeVersion ];
            useGoogleAPIs = false;
          };
          sdkRoot = "${androidComposition.androidsdk}/libexec/android-sdk";
        in {
          androidsdk = androidComposition.androidsdk;
          inherit sdkRoot;
          platformTools = androidComposition.platform-tools;
          cmdlineTools = androidComposition.androidsdk;
          buildTools = "${sdkRoot}/build-tools/${androidConfig.buildToolsVersion}";
          cmake = "${sdkRoot}/cmake/${androidConfig.cmakeVersion}";
          ndk = "${sdkRoot}/ndk/${androidConfig.ndkVersion}";
          emulator =
            if androidConfig.emulatorSupported then
              androidComposition.emulator
            else
              androidComposition.androidsdk;
          systemImage =
            "${sdkRoot}/system-images/android-${toString androidConfig.compileSdk}/google_apis_playstore/${androidConfig.hostEmulatorAbi}";
          androidSdkPackages = { };
          inherit androidConfig;
        };

      neovimDir = ./dependencies/libs/neovim;
    in
    {
      registryFragment = {
        neovim = withPlatformVariants {
          android = neovimDir + "/android.nix";
          wearos = neovimDir + "/wearos.nix";
          ios = neovimDir + "/ios.nix";
          tvos = neovimDir + "/tvos.nix";
          ipados = neovimDir + "/ipados.nix";
          visionos = neovimDir + "/visionos.nix";
          watchos = neovimDir + "/watchos.nix";
          macos = neovimDir + "/macos.nix";
          linux = neovimDir + "/linux.nix";
        };
        "neovim-rootfs" = withPlatformVariants {
          android = null;
          wearos = null;
          ios = ./dependencies/wawona/neovim-rootfs.nix;
          tvos = ./dependencies/wawona/neovim-rootfs.nix;
          ipados = ./dependencies/wawona/neovim-rootfs.nix;
          visionos = ./dependencies/wawona/neovim-rootfs.nix;
          watchos = ./dependencies/wawona/neovim-rootfs.nix;
          macos = null;
        };
      };

      packages = forAll (system:
        let
          pkgs = pkgsFor system;
          androidSDK = mkAndroidSDK system pkgs;
          androidAllowExperimentalFallback =
            (builtins.getEnv "WAWONA_ANDROID_EXPERIMENTAL_FALLBACK") == "1"
            || builtins.elem system [ "aarch64-darwin" "aarch64-linux" ];
          tc = mkToolchains {
            inherit pkgs androidSDK androidAllowExperimentalFallback;
            pkgsAndroid = pkgs.pkgsCross.aarch64-android;
            registry = baseRegistry // self.registryFragment;
          };
          isDarwin = builtins.elem system darwinSystems;
        in
        {
          neovim-android = tc.buildForAndroid "neovim" { };
        } // (if isDarwin then {
          neovim-ios = tc.buildForIOS "neovim" { };
          neovim-ios-sim = tc.buildForIOS "neovim" { simulator = true; };
          neovim-visionos = tc.buildForVisionOS "neovim" { };
          neovim-visionos-sim = tc.buildForVisionOS "neovim" { simulator = true; };
          neovim-macos = tc.buildForMacOS "neovim" { };
          neovim-rootfs-ios = tc.buildForIOS "neovim-rootfs" { };
          neovim-rootfs-visionos = tc.buildForVisionOS "neovim-rootfs" { };
        } else { }));

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
