# phoon-rs for watchOS — the iOS recipe, told (via iosToolchain) to target
# aarch64-apple-watchos. watchOS is store-safe static-only; no GPU is pulled in
# (phoon has no graphics deps), so nothing here conflicts with the watchOS GPU
# block. See wawona-platform-targets.
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
  ...
}:

let
  iosModule = import ./ios.nix;
  forwarded = {
    inherit lib pkgs buildPackages common buildModule simulator iosToolchain;
  };
in
iosModule (builtins.intersectAttrs (builtins.functionArgs iosModule) forwarded)
