# phoon-rs for the Apple mobile family (iOS/iPadOS/tvOS/watchOS/visionOS).
#
# One recipe, parameterised by `iosToolchain` exactly like wwn-waypipe: the
# toolchain's `is{WatchOS,TVOS,VisionOS}Toolchain` flags select the real Rust
# target, so tvOS/watchOS/visionOS build their OWN slices (never an iOS archive
# reused across platforms). Produces the static lib (libphoon_rs.a) with
# `phoon_main` for App-Store-safe in-process linking; no dylib, no subprocess.
{
  lib,
  pkgs,
  buildPackages ? pkgs.buildPackages,
  common ? null,
  buildModule ? null,
  simulator ? false,
  iosToolchain,
  ...
}:

let
  xcodeUtils = iosToolchain;
  isWatchOS = iosToolchain.isWatchOSToolchain or false;
  isTVOS = iosToolchain.isTVOSToolchain or false;
  isVisionOS = iosToolchain.isVisionOSToolchain or false;

  cargoTarget =
    if isWatchOS then
      (if simulator then "aarch64-apple-watchos-sim" else "aarch64-apple-watchos")
    else if isTVOS then
      (if simulator then "aarch64-apple-tvos-sim" else "aarch64-apple-tvos")
    else if isVisionOS then
      (if simulator then "aarch64-apple-visionos-sim" else "aarch64-apple-visionos")
    else if simulator then
      "aarch64-apple-ios-sim"
    else
      "aarch64-apple-ios";

  deploymentTargetEnv =
    if isWatchOS then ''
      export WATCHOS_DEPLOYMENT_TARGET="${iosToolchain.deploymentTarget}"
      unset IPHONEOS_DEPLOYMENT_TARGET
    ''
    else if isTVOS then ''
      export TVOS_DEPLOYMENT_TARGET="${iosToolchain.deploymentTarget}"
      unset IPHONEOS_DEPLOYMENT_TARGET
    ''
    else if isVisionOS then ''
      export XROS_DEPLOYMENT_TARGET="${iosToolchain.deploymentTarget}"
      unset IPHONEOS_DEPLOYMENT_TARGET
    ''
    else ''
      export IPHONEOS_DEPLOYMENT_TARGET="${iosToolchain.deploymentTarget}"
    '';

  phoonSrc = import ./phoon-src.nix { inherit pkgs; };
  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ cargoTarget ];
  };
  myRustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
myRustPlatform.buildRustPackage {
  pname = "phoon-rs";
  version = "0.1.0";
  src = "${phoonSrc}/source";
  __noChroot = true;

  cargoLock.lockFile = ./Cargo.lock;

  CARGO_BUILD_TARGET = cargoTarget;
  doCheck = false;

  preConfigure = ''
    ${xcodeUtils.mkIOSBuildEnv { inherit simulator; }}
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    ${deploymentTargetEnv}

    export RUSTFLAGS="-A warnings -C linker=$XCODE_CLANG -C link-arg=-isysroot -C link-arg=$SDKROOT -C link-arg=$APPLE_DEPLOYMENT_FLAG $RUSTFLAGS"

    target_underscore=$(echo "${cargoTarget}" | tr '-' '_')
    export "CC_''${target_underscore}"="$XCODE_CLANG"
    export "CXX_''${target_underscore}"="$XCODE_CLANGXX"
    export "AR_''${target_underscore}"="ar"
    export "CARGO_TARGET_''${target_underscore^^}_LINKER"="$XCODE_CLANG"

    # Host-side build tools still need a macOS SDK.
    export MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    export HOST_CC="/usr/bin/clang"
  '';

  buildPhase = ''
    runHook preBuild
    # Force native objects into libphoon_rs.a. Cargo.toml sets `lto = true`,
    # which leaves LLVM bitcode in the archive; Rust's LLVM is far newer than
    # Xcode's ld64/nm, so bitcode breaks nmedit privatization AND the final
    # -force_load in-process link ("Unknown attribute kind"). wwn-niri disables
    # LTO for the exact same reason.
    export CARGO_PROFILE_RELEASE_LTO=false
    cargo build --lib --target ${cargoTarget} --release
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    if [ -f target/${cargoTarget}/release/libphoon_rs.a ]; then
      cp target/${cargoTarget}/release/libphoon_rs.a $out/lib/
    else
      echo "ERROR: libphoon_rs.a not found for ${cargoTarget}" >&2
      find target -name 'libphoon_rs*' 2>/dev/null >&2 || true
      exit 1
    fi
    cp ${phoonSrc}/source/include/phoon.h $out/include/ 2>/dev/null || true
  '';
}
