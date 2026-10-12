# phoon-rs for Linux — native host build. Produces the static lib
# (libphoon_rs.a) with the C ABI plus the standalone `phoon` CLI. Used for
# Linux hosts and as the reference-parity build target in CI.
{
  lib,
  pkgs,
  common ? null,
  buildModule ? null,
  ...
}:

let
  phoonSrc = import ./phoon-src.nix { inherit pkgs; };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "phoon-rs";
  version = "0.1.0";
  src = "${phoonSrc}/source";

  cargoLock.lockFile = ./Cargo.lock;
  doCheck = false;

  meta = {
    mainProgram = "phoon";
    description = "Clean-room Rust phoon (ASCII moon phase)";
    license = lib.licenses.mit;
  };

  preConfigure = ''
    export RUSTFLAGS="-A warnings $RUSTFLAGS"
  '';

  postInstall = ''
    mkdir -p $out/lib $out/include
    found=$(find target -name "libphoon_rs.a" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
      cp "$found" $out/lib/libphoon_rs.a
    else
      echo "ERROR: libphoon_rs.a not found" >&2
      exit 1
    fi
    cp ${phoonSrc}/source/include/phoon.h $out/include/ 2>/dev/null || true
  '';
}
