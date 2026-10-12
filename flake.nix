{
  description = "Wawona package host: Mode A wasm (/wasm/v1) plus Mode B Sileo APT at repo root";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    inherit (nixpkgs) lib;
    darwinHost = "aarch64-darwin";
    checkSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];

    nativePkgsFor = system: import nixpkgs { inherit system; };

    packageDoctor = system:
      let
        nativePkgs = nativePkgsFor system;
      in
      nativePkgs.writeShellScriptBin "package-doctor" ''
        exec ${nativePkgs.python3}/bin/python3 ${./scripts/package-doctor.py} "$@"
      '';

    # Termux / androidenv NDK needs the SDK license on the native package set.
    nativePkgsForAndroid = system: import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        android_sdk.accept_license = true;
      };
    };

    # Cross recipes need Xcode / Darwin. Do not import them at flake eval for
    # Linux checks; Gate: packages uses python3 --offline instead.
    mkDarwinPackages = hostSystem:
      let
        nativePkgs = nativePkgsFor hostSystem;
        nativePkgsAndroid = nativePkgsForAndroid hostSystem;
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
        iosPackages = import ./pkgs/top-level.nix {
          inherit self nativePkgs;
          pkgs = pkgsIOS;
          target = "ios";
        };
        # Termux Wayland debs: native pkgs + Google NDK clang (Bionic).
        # Do not use nixpkgs aarch64-unknown-linux-android GCC bootstrap on
        # Darwin (hours of binutils/gcc). See lib/androidNdk.nix.
        androidPackages = import ./pkgs/top-level.nix {
          inherit self;
          nativePkgs = nativePkgsAndroid;
          pkgs = nativePkgsAndroid;
          target = "android";
        };
        # Termux Bionic debs (NDK). Farm grows as each NDK recipe lands.
        # Never mix glibc Linux ELFs here.
        # Termux Bionic Wayland process debs (NDK). Includes niri via
        # aarch64-linux-android + winit Wayland Termux patches.
        androidWayland = nativePkgsAndroid.linkFarm "android-wayland-debs" [
          { name = "weston-simple-shm"; path = androidPackages.weston-simple-shm; }
          { name = "foot"; path = androidPackages.foot; }
          { name = "weston"; path = androidPackages.weston; }
          { name = "niri"; path = androidPackages.niri; }
        ];
      in {
        package-doctor = packageDoctor hostSystem;
        ios = iosPackages.all;
        android = androidPackages.all;
        ios-pkgs = iosPackages;
        android-pkgs = androidPackages;
        hello = iosPackages.hello;
        launchctl = iosPackages.launchctl;
        launchctl-rootful = iosPackages.launchctl-rootful;
        # Termux aarch64 process debs (Bionic). Not Play. Not glibc Linux.
        android-wayland = androidWayland;
        weston-android = androidPackages.weston;
        niri-android = androidPackages.niri;
        foot-android = androidPackages.foot;
        weston-simple-shm-android = androidPackages.weston-simple-shm;
      };

    # Linux process debs for optional Wayland clients (no App Store patches).
    mkLinuxPackages = hostSystem:
      let
        nativePkgs = nativePkgsFor hostSystem;
        linuxPackages = import ./pkgs/top-level.nix {
          inherit self nativePkgs;
          pkgs = nativePkgs;
          target = "linux";
        };
      in {
        package-doctor = packageDoctor hostSystem;
        linux-pkgs = linuxPackages;
        weston = linuxPackages.weston;
        niri = linuxPackages.niri;
        foot = linuxPackages.foot;
        weston-simple-shm = linuxPackages.weston-simple-shm;
        linux-wayland = nativePkgs.linkFarm "linux-wayland-debs" [
          { name = "weston"; path = linuxPackages.weston; }
          { name = "niri"; path = linuxPackages.niri; }
          { name = "foot"; path = linuxPackages.foot; }
          { name = "weston-simple-shm"; path = linuxPackages.weston-simple-shm; }
        ];
      };
  in {
    packages =
      (lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] mkLinuxPackages)
      // {
        ${darwinHost} = mkDarwinPackages darwinHost;
      };

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
          python3 ${self}/scripts/check-wayland-ndk-imports.py
          mkdir "$out"
        '';
      });
  };
}
