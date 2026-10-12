# Optional Wayland process debs. Add one line and one directory.
# linux and android only. See pkgs/wayland/TEMPLATE.nix.
{
  weston = ./weston/default.nix;
  niri = ./niri/default.nix;
  foot = ./foot/default.nix;
  weston-simple-shm = ./weston-simple-shm/default.nix;
}
