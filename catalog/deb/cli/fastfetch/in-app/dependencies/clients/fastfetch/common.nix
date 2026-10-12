# Shared fastfetch 2.64.2 source fetch + Wawona patches (applied in postPatch).
{ pkgs, ... }:

pkgs.fetchzip {
  url = "https://github.com/fastfetch-cli/fastfetch/archive/refs/tags/2.64.2.tar.gz";
  hash = "sha256-isSVcmtNglHy7+F3yemGyY8Jnsy3h5mjOnl159CyJ2Q=";
}
