args@{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildPackages,
  buildModule,
  androidToolchain,
  androidMesonSandbox,
  ...
}:
import ./compositor-android.nix (
  args
  // {
    enableIlandDrm = true;
    enableBackendDrm = false;
  }
)
