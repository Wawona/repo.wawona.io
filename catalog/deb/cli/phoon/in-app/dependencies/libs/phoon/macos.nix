# phoon-rs for macOS — builds the crate as a static lib (libphoon_rs.a)
# exporting the C ABI (phoon_main) plus the standalone `phoon` CLI binary.
# macOS may use its unrestricted native process model, so the binary ships too;
# the static lib is what the in-process shell dispatcher links.
{
  lib,
  pkgs,
  common ? null,
  buildModule ? null,
  xcodeUtils,
  ...
}:

let
  phoonSrc = import ./phoon-src.nix { inherit pkgs; };
  cargoTarget = pkgs.stdenv.hostPlatform.rust.rustcTarget;
in
pkgs.rustPlatform.buildRustPackage {
  pname = "phoon-rs";
  version = "0.1.0";
  src = "${phoonSrc}/source";

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ xcodeUtils.findXcodeScript ];

  CARGO_BUILD_TARGET = cargoTarget;
  doCheck = false;

  meta = {
    mainProgram = "phoon";
    description = "Clean-room Rust phoon (ASCII moon phase)";
    license = lib.licenses.mit;
  };

  preConfigure = ''
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
    export RUSTFLAGS="-A warnings $RUSTFLAGS"
  '';

  postInstall = ''
    mkdir -p $out/lib $out/include
    found=""
    for cand in \
      "target/${cargoTarget}/release/libphoon_rs.a" \
      "target/release/libphoon_rs.a"; do
      if [ -f "$cand" ]; then found="$cand"; break; fi
    done
    if [ -z "$found" ]; then found=$(find target -name libphoon_rs.a 2>/dev/null | head -1); fi
    if [ -n "$found" ]; then
      cp "$found" $out/lib/libphoon_rs.a
    else
      echo "ERROR: libphoon_rs.a not found" >&2
      exit 1
    fi
    cp ${phoonSrc}/source/include/phoon.h $out/include/ 2>/dev/null || true
  '';
}
