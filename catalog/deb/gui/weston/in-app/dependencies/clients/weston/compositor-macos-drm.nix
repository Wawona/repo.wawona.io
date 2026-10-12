args@{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildPackages,
  buildModule,
  xcodeUtils,
  ilandSrc,
  ...
}: import ./compositor-apple-mobile.nix (args // {
  enableIlandDrm = true;
  macos = true;
})
