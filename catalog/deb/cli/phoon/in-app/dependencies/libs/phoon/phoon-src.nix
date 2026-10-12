# Pure-source derivation for the phoon-rs crate.
#
# Stages the crate (Cargo manifest + lockfile + sources + C header) into a
# single tree consumed by the per-platform recipes, so the Nix source hash is
# independent of which platform recipe builds it. No compilation happens here.
{ pkgs }:

let
  # Repo root is three levels up from dependencies/libs/phoon/.
  root = ../../..;
  src = pkgs.lib.cleanSourceWith {
    src = root;
    filter =
      path: _type:
      let
        b = baseNameOf path;
      in
      !(b == "target" || b == ".git" || b == ".direnv" || b == ".agent-device");
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "phoon-rs-src";
  version = "0.1.0";
  inherit src;

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    mkdir -p $out/source
    cp Cargo.toml $out/source/
    cp Cargo.lock $out/source/ 2>/dev/null || true
    cp -r src $out/source/src
    cp -r tools $out/source/tools 2>/dev/null || true
    cp -r include $out/source/include 2>/dev/null || true
  '';

  meta = {
    description = "phoon-rs crate source tree (clean-room moon-phase renderer)";
    license = pkgs.lib.licenses.mit;
  };
}
