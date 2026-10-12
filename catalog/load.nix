# Directory is the index. A package is catalog/<channel>/<kind>/<name>/default.nix.
# The APT index file at the repo root is named Packages, so this tree is catalog/.
{ channel, kind }:
let
  dir = ./. + "/${channel}/${kind}";
  entries = if builtins.pathExists dir then builtins.readDir dir else { };
  names = builtins.filter (
    name: entries.${name} == "directory" && builtins.pathExists (dir + "/${name}/default.nix")
  ) (builtins.attrNames entries);
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value = dir + "/${name}/default.nix";
  }) names
)
