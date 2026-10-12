# Upstream niri compositor as a process deb. No App Store patches.
# Not niri_main in-process archive. Nested on Wawona with NIRI_BACKEND=nested.
# linux: pack nixpkgs niri. android: cargo + NDK linker + Termux sysroot (Bionic).
#
# Termux: target aarch64-linux-android (Bionic rust-std). Patch winit so
# feature=wayland takes free_unix Wayland nest (not android-activity). Drop
# smithay's winit x11 feature. SCTK/wayland-cursor use memfd on Android.
# No -Zbuild-std / custom linux+gnu target (glibc std symbols).
{ pkgs
, nativePkgs ? pkgs
, mkDebFromBins
, packProcessDeb
, target ? "linux"
, jailbreakScheme ? null
}:

assert target == "linux" || target == "android";

let
  inherit (pkgs) lib;
  isAndroid = target == "android";
  version = if isAndroid then nativePkgs.niri.version else pkgs.niri.version;

  ndkLibs = import ../ndkLibs.nix { inherit nativePkgs; };
  androidNdk = ndkLibs.ndk;
  rustToolchainAndroid = ndkLibs.libs.rustStd;
  # libinput is not in Termux apt; NDK static build + udev-zero.
  # libdisplay-info: Termux ships 0.4.0; libdisplay-info-sys 0.3 wants < 0.4.
  libinputAndroid = ndkLibs.libs.libinput;
  libudevZero = ndkLibs.libs.libudev-zero;
  libdisplayInfoAndroid = ndkLibs.libs.libdisplay-info;

  termuxDeb = { name, url, hash }: nativePkgs.fetchurl {
    inherit url hash;
    name = "termux-${name}.deb";
  };

  main = "https://packages.termux.dev/apt/termux-main";
  x11 = "https://packages.termux.dev/apt/termux-x11";

  termuxSysroot = import ../../../lib/termuxSysroot.nix {
    pkgs = nativePkgs;
    debs = [
      (termuxDeb { name = "pango"; url = "${main}/pool/main/p/pango/pango_1.58.2_aarch64.deb"; hash = "sha256-MIni3lBfOu2QtgI1r3cjvcbpC9DdlUvNgIOEil2cGek="; })
      (termuxDeb { name = "glib"; url = "${main}/pool/main/g/glib/glib_2.90.1_aarch64.deb"; hash = "sha256-Ey2M6WHZanJS/UvCIovd04WxsXtwakbKrm1UGuDkssA="; })
      (termuxDeb { name = "harfbuzz"; url = "${main}/pool/main/h/harfbuzz/harfbuzz_14.6.0_aarch64.deb"; hash = "sha256-7u68PLHRBhLvXlPB7N8bFfNoiVkuhH0Qd081C6B+z3Q="; })
      (termuxDeb { name = "fribidi"; url = "${main}/pool/main/f/fribidi/fribidi_1.0.17_aarch64.deb"; hash = "sha256-h5oYCxDhBWAPtgM/Fe/wmH60iuEfG4e+7KgDqrhLhmY="; })
      (termuxDeb { name = "libcairo"; url = "${main}/pool/main/libc/libcairo/libcairo_1.18.6_aarch64.deb"; hash = "sha256-wsrrvXpeLHeHKYaP265U+HoyTMy1rSVLyuBQpBLZzVc="; })
      (termuxDeb { name = "libpixman"; url = "${main}/pool/main/libp/libpixman/libpixman_0.46.4-1_aarch64.deb"; hash = "sha256-NkuMgv9o+FE5MOXUE0Wft8UuzMe6dal6jFo4dg7ujTM="; })
      (termuxDeb { name = "libwayland"; url = "${main}/pool/main/libw/libwayland/libwayland_1.26.0_aarch64.deb"; hash = "sha256-8D6gL31SM5lRTiRjxUWdqyNLgCu9pBphwDQLQBHcdz0="; })
      (termuxDeb { name = "mesa"; url = "${main}/pool/main/m/mesa/mesa_26.2.4_aarch64.deb"; hash = "sha256-0HKwFEqab0+AvQh5eJOqN9S3Ugmq6BDy6EhDqPojNC4="; })
      (termuxDeb { name = "mesa-dev"; url = "${main}/pool/main/m/mesa-dev/mesa-dev_26.2.4_all.deb"; hash = "sha256-lh0ubsudqyPgClb1AGPaPM3ZrgFA0swMDahqCYwudXY="; })
      (termuxDeb { name = "libglvnd"; url = "${main}/pool/main/libg/libglvnd/libglvnd_1.7.0-1_aarch64.deb"; hash = "sha256-Z/P9JH5Ceaf87dvSkp+LU+h8JV7fycB9De599f4kPSw="; })
      (termuxDeb { name = "libdrm"; url = "${main}/pool/main/libd/libdrm/libdrm_2.4.134_aarch64.deb"; hash = "sha256-DL6CFAzzJcFUc/v1OjcR/HovuI42o+6lijJnxGGrShc="; })
      (termuxDeb { name = "libseat"; url = "${main}/pool/main/libs/libseat/libseat_0.9.3_aarch64.deb"; hash = "sha256-ESF4u7NiKeoKEgrj9erCMRwr4pZyphhJr6brnKRzYC8="; })
      (termuxDeb { name = "fontconfig"; url = "${main}/pool/main/f/fontconfig/fontconfig_2.18.3_aarch64.deb"; hash = "sha256-f4tw3XyoWx58uxShHp5r1M4xiauYWqevURRUhNhfLGE="; })
      (termuxDeb { name = "freetype"; url = "${main}/pool/main/f/freetype/freetype_2.14.3_aarch64.deb"; hash = "sha256-Zw0n2PU+8tiHtn+LgvpID3EytlrCJko5s8W022N+4oU="; })
      (termuxDeb { name = "libpng"; url = "${main}/pool/main/libp/libpng/libpng_1.6.59_aarch64.deb"; hash = "sha256-MtYfCxpgz3KDqjqA4ohzdJPfLGuEyMdJYGt3yUoQ8rI="; })
      (termuxDeb { name = "libffi"; url = "${main}/pool/main/libf/libffi/libffi_3.8.0_aarch64.deb"; hash = "sha256-TyVbrfdM0x9qKAHBf6FEQZnITINLUXt8hD4v6evpHXc="; })
      (termuxDeb { name = "pcre2"; url = "${main}/pool/main/p/pcre2/pcre2_10.49_aarch64.deb"; hash = "sha256-wnmV5fUrjsybiz5mLrCOSfgqGL/T80NDk2rMeyOWRyQ="; })
      (termuxDeb { name = "libandroid-support"; url = "${main}/pool/main/liba/libandroid-support/libandroid-support_29-1_aarch64.deb"; hash = "sha256-8vFF1hNa1IQ6yWcBU74+OUTcHm8XNtRtIwbCjyuG9Rc="; })
      (termuxDeb { name = "libxkbcommon"; url = "${x11}/pool/main/libx/libxkbcommon/libxkbcommon_1.13.2_aarch64.deb"; hash = "sha256-In84la84pJ5BoGJiuDdguydkcRghhIy3tYO81C2GVdM="; })
      (termuxDeb { name = "libevdev"; url = "${x11}/pool/main/libe/libevdev/libevdev_1.14.0_aarch64.deb"; hash = "sha256-IVL6szuBzARzQ1K6RxPn3VeFnz0sv1F6fQEnAGyp+NI="; })
    ];
  };

  androidPcPath = lib.concatStringsSep ":" [
    "${libdisplayInfoAndroid}/lib/pkgconfig"
    "${libinputAndroid}/lib/pkgconfig"
    "${libudevZero}/lib/pkgconfig"
    "${termuxSysroot}/lib/pkgconfig"
  ];

  androidCargoEnv = ndkLibs.cargoEnv {
    cflagsIncludes = [ "${termuxSysroot}/include" ];
    cIncludePath = [
      "${termuxSysroot}/include"
      "${libdisplayInfoAndroid}/include"
    ];
    libraryDirs = [
      "${termuxSysroot}/lib"
      "${libdisplayInfoAndroid}/lib"
      "${libinputAndroid}/lib"
      "${libudevZero}/lib"
    ];
    sharedLibs = [ "EGL" "wayland-client" ];
  };

  androidTriple = "aarch64-linux-android";

  niriPkg =
    if !isAndroid then pkgs.niri
    else
      nativePkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "niri-android";
        inherit version;
        src = nativePkgs.niri.src;

        cargoDeps = nativePkgs.rustPlatform.fetchCargoVendor {
          inherit (finalAttrs) src;
          name = "${finalAttrs.pname}-${finalAttrs.version}";
          hash = "sha256-X28M0jyhUtVtMQAYdxIPQF9mJ5a77v8jw1LKaXSjy7E=";
        };

        dontPatchELF = true;
        dontStrip = true;

        nativeBuildInputs = with nativePkgs; [
          pkg-config
          rustPlatform.cargoSetupHook
          rustPlatform.bindgenHook
        ];

        buildPhase = ''
          runHook preBuild
          export PATH=${rustToolchainAndroid}/bin:$PATH
          export RUSTC=${rustToolchainAndroid}/bin/rustc
          export CARGO=${rustToolchainAndroid}/bin/cargo
          export PKG_CONFIG_PATH="${androidPcPath}"
          export PKG_CONFIG_PATH_aarch64_linux_android="${androidPcPath}"
          export PKG_CONFIG_ALLOW_CROSS=1
          export PKG_CONFIG_ALLOW_CROSS_aarch64_linux_android=1
          export NIRI_BUILD_COMMIT=repo.wawona.io
          # Host build scripts (libudev-sys hwdb probe) must use Darwin cc.
          # Only the Android target linker/CC is NDK.
          ${androidCargoEnv}

          # Each script is a separate store path; do not resolve siblings via __file__.
          ${nativePkgs.python3}/bin/python3 ${./patch-winit-termux-wayland.py}
          ${nativePkgs.python3}/bin/python3 ${./patch-smithay-winit-nox11.py}
          ${nativePkgs.python3}/bin/python3 ${./patch-wayland-cursor-android.py}
          ${nativePkgs.python3}/bin/python3 ${./patch-sctk-shm-android.py}
          ${nativePkgs.python3}/bin/python3 ${./patch-smithay-asdfd-android.py}

          ulimit -u 2048 || true
          export CARGO_BUILD_JOBS=1
          cargo build --release --offline -j 1 \
            --target ${androidTriple} \
            --no-default-features
          runHook postBuild
        '';

        doCheck = false;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          test -x target/${androidTriple}/release/niri
          cp target/${androidTriple}/release/niri $out/bin/niri
          runHook postInstall
        '';

        meta = {
          description = "Niri Wayland compositor (Android/Termux process)";
          homepage = "https://github.com/niri-wm/niri";
        };
      });

  files = {
    "bin/niri" = "${niriPkg}/bin/niri";
  };
in
packProcessDeb {
  pname = "niri";
  inherit version target files;
  homepage = "https://github.com/niri-wm/niri";
  description = "Niri scrollable-tiling compositor for Wawona (process deb, no App Store patches)";
  depends = if isAndroid then
    "libwayland, pango, glib, harfbuzz, fribidi, libcairo, mesa, libglvnd, libdrm, libseat, fontconfig, freetype, libpng, libandroid-support, libxkbcommon"
  else null;
}
