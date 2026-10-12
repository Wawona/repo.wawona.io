# Shared Neovim 0.10.4 source fetch (patch-overlay model).
{ pkgs, ... }:

pkgs.fetchzip {
  url = "https://github.com/neovim/neovim/archive/refs/tags/v0.10.4.tar.gz";
  hash = "sha256-TAuoa5GD50XB4OCHkSwP1oXfedzVrCBRutNxBp/zGLY=";
}
