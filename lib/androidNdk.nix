# Android NDK helpers for Termux aarch64 process debs.
# Uses google NDK via androidenv (darwin-x86_64 prebuilt folder works on
# Apple Silicon). Avoids nixpkgs aarch64-unknown-linux-android GCC bootstrap.
{ pkgs # native pkgs; must allowUnfree + android_sdk.accept_license
, apiLevel ? "33"
, ndkVersion ? "27.0.12077973"
}:

let
  inherit (pkgs) lib stdenv;
  composition = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    inherit ndkVersion;
  };
  ndkRoot = "${composition.ndk-bundle}/libexec/android-sdk/ndk/${ndkVersion}";

  # NDK still ships Darwin hosts under darwin-x86_64 (universal / arm64 Mach-O).
  hostDouble =
    if stdenv.buildPlatform.isDarwin then "darwin-x86_64"
    else if stdenv.buildPlatform.isLinux && stdenv.buildPlatform.isx86_64 then "linux-x86_64"
    else if stdenv.buildPlatform.isLinux && stdenv.buildPlatform.isAarch64 then "linux-aarch64"
    else throw "androidNdk: unsupported build platform ${stdenv.buildPlatform.config}";

  prebuilt = "${ndkRoot}/toolchains/llvm/prebuilt/${hostDouble}";
  triple = "aarch64-linux-android";
  cc = "${prebuilt}/bin/${triple}${apiLevel}-clang";
  cxx = "${prebuilt}/bin/${triple}${apiLevel}-clang++";
  ar = "${prebuilt}/bin/llvm-ar";
  strip = "${prebuilt}/bin/llvm-strip";
  sysroot = "${prebuilt}/sysroot";
in
{
  inherit ndkRoot prebuilt hostDouble triple apiLevel cc cxx ar strip sysroot composition;
  mesonCrossFile = pkgs.writeText "android-ndk-cross.ini" ''
    [binaries]
    c = '${cc}'
    cpp = '${cxx}'
    ar = '${ar}'
    strip = '${strip}'
    pkg-config = '${pkgs.pkg-config}/bin/pkg-config'
    wayland_scanner = '${pkgs.wayland-scanner.bin}/bin/wayland-scanner'

    [host_machine]
    system = 'android'
    cpu_family = 'aarch64'
    cpu = 'aarch64'
    endian = 'little'

    [built-in options]
    prefix = '/data/data/com.termux/files/usr'
    # Bionic wchar_t is 32-bit; foot/fcft require ISO 10646 UTF-32 assert.
    c_args = ['-fPIC', '-D__STDC_ISO_10646__=201103L']
    cpp_args = ['-fPIC', '-D__STDC_ISO_10646__=201103L']
  '';
}
