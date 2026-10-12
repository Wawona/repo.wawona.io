# Copy this file to catalog/deb/<kind>/<name>/default.nix.
# builtins.readDir is the index. Do not add a clients.nix line.
# Fill LIBC, TEXT, and GPU in a comment before meson or cargo.
# Android: ndkLibs. Do not import lib/androidNdk.nix.
# Do not import apple-mobile.nix. Do not rename main to *_main.
#
# { pkgs, nativePkgs, mkDebFromBins, packProcessDeb, target }:
#
# let
#   ndkLibs = import ../../../../pkgs/wayland/ndkLibs.nix { inherit nativePkgs; };
#   version = "UPSTREAM";
#   built = if target == "android" then
#     nativePkgs.stdenv.mkDerivation {
#       pname = "NAME-android";
#       inherit version;
#       # src = real upstream
#       # PKG_CONFIG_PATH = ndkLibs.pcPath [ "wayland" "pixman" ];
#       # nativeBuildInputs = [ ndkLibs.ndk.pkg-config ndkLibs.ndk.meson ];
#     }
#   else
#     nativePkgs.NAME;
# in
# packProcessDeb {
#   pname = "NAME";
#   inherit version target;
#   homepage = "https://UPSTREAM";
#   description = "WHAT IT IS";
#   files = [ { source = "${built}/bin/NAME"; dest = "bin/NAME"; } ];
# }
