# phoon-rs for Android — builds the crate as a shared lib (libphoon_rs.so)
# exporting the C ABI (phoon_main), loaded in-process by the Wawona Android app
# the same way the other native cores are. Falls back to the static archive if
# the cdylib was not produced. No external deps (phoon is pure Rust + std).
{
  lib,
  pkgs,
  buildPackages,
  common ? null,
  buildModule ? null,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  phoonSrc = import ./phoon-src.nix { inherit pkgs; };

  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ "aarch64-linux-android" ];
  };
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  androidLinkerWrapper = pkgs.writeShellScript "android-linker-wrapper" ''
    exec ${androidToolchain.androidCC} "$@"
  '';
in
rustPlatform.buildRustPackage {
  pname = "phoon-rs";
  version = "0.1.0";
  src = "${phoonSrc}/source";

  cargoLock.lockFile = ./Cargo.lock;

  CARGO_BUILD_TARGET = "aarch64-linux-android";
  CC_aarch64_linux_android = "${androidLinkerWrapper}";
  CXX_aarch64_linux_android = androidToolchain.androidCXX;
  AR_aarch64_linux_android = androidToolchain.androidAR;
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${androidLinkerWrapper}";

  cargoBuildFlags = [
    "--target"
    "aarch64-linux-android"
  ];
  doCheck = false;
  dontFixup = true;

  preConfigure = ''
    export RUSTFLAGS="-A warnings $RUSTFLAGS"
  '';

  postInstall = ''
    mkdir -p $out/lib $out/include $out/bin
    search_roots="''${CARGO_TARGET_DIR:-target} target"

    # In-process C-ABI shared lib (for JNI callers that link phoon_main).
    found=$(find $search_roots -name "libphoon_rs.so" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
      echo "installing $found -> $out/lib/libphoon_rs.so"
      cp "$found" $out/lib/libphoon_rs.so
    else
      found=$(find $search_roots -name "libphoon_rs.a" 2>/dev/null | head -1)
      if [ -n "$found" ]; then
        echo "installing $found -> $out/lib/libphoon_rs.a"
        cp "$found" $out/lib/libphoon_rs.a
      else
        echo "ERROR: libphoon_rs.so/libphoon_rs.a not found" >&2
        find $search_roots -maxdepth 5 -type f -name "libphoon_rs*" 2>/dev/null >&2 || true
        exit 1
      fi
    fi

    # Standalone CLI ELF (Android uses the fork/exec spawn model like fastfetch;
    # the APK ships this as libphoon_bin.so and posix_spawn()s it).
    binf=$(find $search_roots -type f -name "phoon" -perm -u+x 2>/dev/null | head -1)
    if [ -n "$binf" ]; then
      echo "installing $binf -> $out/bin/phoon"
      cp "$binf" $out/bin/phoon
    else
      echo "WARNING: phoon CLI binary not found; only the lib is installed" >&2
    fi

    cp ${phoonSrc}/source/include/phoon.h $out/include/ 2>/dev/null || true
  '';
}
