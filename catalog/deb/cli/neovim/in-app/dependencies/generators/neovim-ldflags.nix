# Link flags for in-process Neovim on Apple targets.
{ lib, deps, forceLoad ? true }:

let
  strip = d: if d == null then "" else toString d;
  neovim = deps.neovim or null;
  libnvim = if neovim != null then "${strip neovim}/lib/libwawona-neovim.a" else "";
in
if forceLoad && neovim != null && builtins.pathExists libnvim then
  [ "-force_load" libnvim ]
else
  [ ]
