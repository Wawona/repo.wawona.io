# Bundled Neovim runtime prefix for Apple mobile (read-only bundle + templates).
{
  lib,
  pkgs,
  buildModule,
  iosToolchain,
  simulator ? false,
}:

let
  neovim = buildModule.buildForIOS "neovim" { inherit simulator; };
  initTemplate = pkgs.writeText "init.lua.template" ''
    -- Wawona iOS Neovim init — bundled runtime only (App Store compliant).
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.mouse = ""
    vim.opt.shell = "/usr/bin/zsh"
  '';
in
pkgs.runCommand "neovim-rootfs-ios${if simulator then "-sim" else ""}"
  {
    inherit neovim;
  }
  ''
    set -euo pipefail
    mkdir -p $out/rootfs/usr/share/nvim $out/rootfs/etc/nvim $out/rootfs/usr/bin
    if [ -d "$neovim/share/nvim/runtime" ]; then
      cp -R "$neovim/share/nvim/runtime" $out/rootfs/usr/share/nvim/
    elif [ -d "$neovim/share/nvim" ]; then
      cp -R "$neovim/share/nvim"/* $out/rootfs/usr/share/nvim/
    fi
    cp ${initTemplate} $out/rootfs/etc/nvim/init.lua.template
    cat > $out/rootfs/usr/bin/nvim <<'EOF'
# Wawona iOS: nvim is linked into the app binary (libwawona-neovim.a).
# This path exists for conventions; exec is in-process via wawona-dispatch.
EOF
    cat > $out/rootfs/README.txt <<'EOF'
Bundled Neovim runtime — do not modify files inside the app bundle.
The editor binary is linked into the app; this tree holds runtime + init templates.
EOF
  ''
