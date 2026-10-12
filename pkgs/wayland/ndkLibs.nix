# One Android NDK Wayland library set for Termux debs.
# Import this once. Do not import lib/androidNdk.nix from a package file.
# Do not import lib/termuxSysroot.nix here. That file unpacks Termux apt
# debs (pango, glib, harfbuzz). This file builds the NDK graph.
{ nativePkgs }:

let
  inherit (nativePkgs) lib;
  ndk = import ../../lib/androidNdk.nix { pkgs = nativePkgs; };
  withNdk = file: import file {
    inherit nativePkgs;
    androidNdk = ndk;
  };
  libs = {
    libffi = withNdk ./libffi-android/default.nix;
    expat = withNdk ./expat-android/default.nix;
    libpng = withNdk ./libpng-android/default.nix;
    freetype = withNdk ./freetype-android/default.nix;
    fontconfig = withNdk ./fontconfig-android/default.nix;
    pixman = withNdk ./pixman-android/default.nix;
    cairo = withNdk ./cairo-android/default.nix;
    wayland = withNdk ./wayland-android/default.nix;
    xkbcommon = withNdk ./xkbcommon-android/default.nix;
    libdrm = withNdk ./libdrm-android/default.nix;
    libevdev = withNdk ./libevdev-android/default.nix;
    libudev-zero = withNdk ./libudev-zero-android/default.nix;
    libinput = withNdk ./libinput-android/default.nix;
    libdisplay-info = withNdk ./libdisplay-info-android/default.nix;
    tllist = import ./tllist-android/default.nix { inherit nativePkgs; };
    fcft = withNdk ./fcft-android/default.nix;
    rustStd = import ./rust-std-android/default.nix { inherit nativePkgs; };
  };
  hostPc = [
    "${nativePkgs.wayland-scanner.dev}/lib/pkgconfig"
    "${nativePkgs.wayland-protocols}/share/pkgconfig"
  ];
  # PKG_CONFIG_PATH for the named libs, plus the host wayland scanner.
  pcPath = names:
    lib.concatStringsSep ":" (
      map (name: "${libs.${name}}/lib/pkgconfig") names ++ hostPc
    );
  termuxLib = "/data/data/com.termux/files/usr/lib";
  # Rust (niri) link line. Package passes include and -L dirs. Do not paste
  # CC_aarch64_linux_android in the package file.
  cargoEnv = { cflagsIncludes, cIncludePath, libraryDirs, sharedLibs }:
    let
      incFlags = lib.concatMapStringsSep " " (dir: "-I${dir}") cflagsIncludes;
      cInc = lib.concatStringsSep ":" (cIncludePath ++ [
        "${ndk.sysroot}/usr/include"
        "${ndk.sysroot}/usr/include/aarch64-linux-android"
      ]);
      libPath = lib.concatStringsSep ":" libraryDirs;
      lDirs = lib.concatMapStrings (dir: "-C link-arg=-L${dir} ") libraryDirs;
      lLibs = lib.concatMapStrings (name: "-C link-arg=-l${name} ") sharedLibs;
      bindgenInc = lib.concatMapStringsSep " " (dir: "-I${dir}") cIncludePath;
    in ''
      export CC_aarch64_linux_android=${ndk.cc}
      export CXX_aarch64_linux_android=${ndk.cxx}
      export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=${ndk.cc}
      export C_INCLUDE_PATH="${cInc}"
      export LIBRARY_PATH="${libPath}"
      export CFLAGS_aarch64_linux_android="--target=aarch64-linux-android${ndk.apiLevel} --sysroot=${ndk.sysroot} -fPIC ${incFlags}"
      export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${ndk.sysroot} ${bindgenInc} -I${ndk.sysroot}/usr/include -I${ndk.sysroot}/usr/include/aarch64-linux-android"
      export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C linker=${ndk.cc} -C link-arg=--sysroot=${ndk.sysroot} ${lDirs}-C link-arg=-Wl,-rpath,${termuxLib} -C link-arg=-Wl,--push-state,--no-as-needed ${lLibs}-C link-arg=-Wl,--pop-state"
    '';
in {
  inherit ndk libs pcPath termuxLib cargoEnv;
}
