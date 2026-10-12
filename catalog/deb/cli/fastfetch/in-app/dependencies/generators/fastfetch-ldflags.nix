# Link flags for in-process fastfetch on Apple targets.
# Pass nativeDeps with fastfetch from mobile-platform-deps.
#
# The framework list is read from the per-platform manifest emitted by the
# fastfetch archive ($out/nix-support/fastfetch-frameworks) so this generator
# never hardcodes per-platform framework knowledge (watchOS has no Metal or
# VideoToolbox). Falls back to the CoreFoundation/Foundation base if the
# manifest is absent (older archives).
{ lib, deps, forceLoad ? true }:

let
  strip = d: if d == null then "" else toString d;
  fastfetch = deps.fastfetch or null;
  libff = if fastfetch != null then "${strip fastfetch}/lib/libfastfetch.a" else "";
  fwFile = if fastfetch != null then "${strip fastfetch}/nix-support/fastfetch-frameworks" else "";
  frameworks =
    if fwFile != "" && builtins.pathExists fwFile
    then lib.filter (s: s != "") (lib.splitString "\n" (builtins.readFile fwFile))
    else [ "CoreFoundation" "Foundation" ];
  frameworkFlags = lib.concatMap (f: [ "-framework" f ]) frameworks;
in
if forceLoad && fastfetch != null && builtins.pathExists libff then
  [ "-force_load" libff ] ++ frameworkFlags
else
  [ ]
