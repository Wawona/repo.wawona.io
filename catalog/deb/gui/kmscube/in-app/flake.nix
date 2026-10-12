{
  description = "wwn-kmscube: native OpenGL and Vulkan acceptance clients over wwn-iland KMS/GBM for Apple and Android.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.url = "https://flakehub.com/f/Wawona/wwn-toolchain/*";
    wwn-toolchain.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.inputs.rust-overlay.follows = "rust-overlay";
    # L2 -> L1 edge; see Wawona/docs/wwn-repo-dag.md. FlakeHub rolling follows
    # the published L1 tip (MoltenVK/SwiftShader provider registry).
    wwn-iland.url = "github:Wawona/wwn-iland/tvos-gpu";
    wwn-iland.inputs.nixpkgs.follows = "nixpkgs";
    wwn-iland.inputs.wwn-toolchain.follows = "wwn-toolchain";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      wwn-toolchain,
      wwn-iland,
      ...
    }:
    let
      darwinSystems = [
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      allSystems = darwinSystems ++ linuxSystems;
      forAll = nixpkgs.lib.genAttrs allSystems;
      inherit (wwn-toolchain.lib) withPlatformVariants baseRegistry mkToolchains;

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
          config = {
            allowUnfree = true;
            allowUnsupportedSystem = true;
            android_sdk.accept_license = true;
          };
        };

      mkAndroidSDK =
        system: pkgs:
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
        in
        {
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
          systemImage = "${sdkRoot}/system-images/android-${toString androidConfig.compileSdk}/google_apis_playstore/${androidConfig.hostEmulatorAbi}";
          androidSdkPackages = { };
          inherit androidConfig;
        };

      kmscubeDir = ./dependencies/clients/kmscube;
      gbmEs2DemoDir = ./dependencies/clients/gbm-es2-demo;
    in
    {
      registryFragment = {
        kmscube = withPlatformVariants {
          android = kmscubeDir + "/android.nix";
          wearos = kmscubeDir + "/wearos.nix";
          ios = kmscubeDir + "/ios.nix";
          tvos = kmscubeDir + "/tvos.nix";
          ipados = kmscubeDir + "/ipados.nix";
          visionos = kmscubeDir + "/visionos.nix";
          watchos = kmscubeDir + "/watchos.nix";
          macos = kmscubeDir + "/macos.nix";
          linux = kmscubeDir + "/linux.nix";
        };
        "gbm-es2-demo" = withPlatformVariants {
          android = gbmEs2DemoDir + "/android.nix";
          wearos = gbmEs2DemoDir + "/wearos.nix";
          ios = gbmEs2DemoDir + "/ios.nix";
          tvos = gbmEs2DemoDir + "/tvos.nix";
          ipados = gbmEs2DemoDir + "/ipados.nix";
          visionos = gbmEs2DemoDir + "/visionos.nix";
          watchos = gbmEs2DemoDir + "/watchos.nix";
          macos = gbmEs2DemoDir + "/macos.nix";
          linux = null;
        };
        vkcube = withPlatformVariants {
          android = ./dependencies/clients/vkcube/android.nix;
          wearos = ./dependencies/clients/vkcube/wearos.nix;
          ios = ./dependencies/clients/vkcube/ios.nix;
          ipados = ./dependencies/clients/vkcube/ipados.nix;
          visionos = ./dependencies/clients/vkcube/visionos.nix;
          macos = ./dependencies/clients/vkcube/macos.nix;
          # tvOS: MoltenVK (Vulkan to Metal). watchOS is blocked (no Metal).
          tvos = ./dependencies/clients/vkcube/tvos.nix;
          watchos = null;
          linux = null;
        };
        "opengl-cube" = withPlatformVariants {
          android = ./dependencies/clients/opengl-cube/android.nix;
          wearos = ./dependencies/clients/opengl-cube/wearos.nix;
          ios = ./dependencies/clients/opengl-cube/ios.nix;
          ipados = ./dependencies/clients/opengl-cube/ipados.nix;
          visionos = ./dependencies/clients/opengl-cube/visionos.nix;
          macos = ./dependencies/clients/opengl-cube/macos.nix;
          # tvOS: Wayland-EGL cube over iland + ANGLE (same apple-mobile.nix
          # as iOS/visionOS). watchOS stays null: no Metal in the SDK.
          # Cited: Wawona/docs/wwn-repo-dag.md.
          tvos = ./dependencies/clients/opengl-cube/ios.nix;
          watchos = null;
          linux = null;
        };
        # Backward-compatible alias for flakes that still key nativeDeps on this name.
        "iland-gl-clients" = withPlatformVariants {
          android = kmscubeDir + "/android.nix";
          wearos = kmscubeDir + "/wearos.nix";
          ios = kmscubeDir + "/ios.nix";
          tvos = kmscubeDir + "/tvos.nix";
          ipados = kmscubeDir + "/ipados.nix";
          visionos = kmscubeDir + "/visionos.nix";
          watchos = kmscubeDir + "/watchos.nix";
          macos = kmscubeDir + "/macos.nix";
          linux = null;
        };
      };

      packages = forAll (
        system:
        let
          pkgs = pkgsFor system;
          androidSDK = mkAndroidSDK system pkgs;
          tc = mkToolchains {
            inherit pkgs androidSDK;
            pkgsAndroid = pkgs.pkgsCross.aarch64-android;
            androidAllowExperimentalFallback = builtins.elem system [
              "aarch64-darwin"
              "aarch64-linux"
            ];
            registry = baseRegistry // wwn-iland.registryFragment // self.registryFragment;
          };
          isDarwin = builtins.elem system darwinSystems;
        in
        (
          if isDarwin then
            {
              kmscube-ios = tc.buildForIOS "kmscube" { };
              kmscube-macos = tc.buildForMacOS "kmscube" { };
              gbm-es2-demo-ios = tc.buildForIOS "gbm-es2-demo" { };
              gbm-es2-demo-macos = tc.buildForMacOS "gbm-es2-demo" { };
              vkcube-ios = tc.buildForIOS "vkcube" { };
              vkcube-ios-sim = tc.buildForIOS "vkcube" { simulator = true; };
              vkcube-ipados = tc.buildForIPadOS "vkcube" { };
              vkcube-visionos = tc.buildForVisionOS "vkcube" { };
              vkcube-visionos-sim = tc.buildForVisionOS "vkcube" { simulator = true; };
              vkcube-macos = tc.buildForMacOS "vkcube" { };
              vkcube-tvos = tc.buildForTVOS "vkcube" { };
              vkcube-tvos-sim = tc.buildForTVOS "vkcube" { simulator = true; };
              opengl-cube-ios = tc.buildForIOS "opengl-cube" { };
              opengl-cube-ios-sim = tc.buildForIOS "opengl-cube" { simulator = true; };
              opengl-cube-ipados = tc.buildForIPadOS "opengl-cube" { };
              opengl-cube-visionos = tc.buildForVisionOS "opengl-cube" { };
              opengl-cube-tvos = tc.buildForTVOS "opengl-cube" { };
              opengl-cube-tvos-sim = tc.buildForTVOS "opengl-cube" { simulator = true; };
              opengl-cube-macos = tc.buildForMacOS "opengl-cube" { };
            }
          else
            { }
        )
        // {
          vkcube-android = tc.buildForAndroid "vkcube" { };
          opengl-cube-android = tc.buildForAndroid "opengl-cube" { };
          gbm-es2-demo-android = tc.buildForAndroid "gbm-es2-demo" { };
          kmscube-android = tc.buildForAndroid "kmscube" { };
        }
      );

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
