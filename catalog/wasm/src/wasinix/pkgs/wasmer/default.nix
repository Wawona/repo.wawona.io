{
  lib,
  pkgs,
  nanoWasmer,
  grepWasmer,
  sedWasmer,
  findWasmer,
  gzipWasmer,
  tarWasmer,
  lessWasmer,
  ncursesWasmer,
  crabsayWasmer,
  wayland-bridge-smokeWasmer,
  gtk4-helloWasmer,
  phpixPhp83Wasmer,
  phpixPhp85Wasmer,
  cliPlatformWasmer,
}: let
  packages = {
    nano = nanoWasmer;
    grep = grepWasmer;
    sed = sedWasmer;
    find = findWasmer;
    gzip = gzipWasmer;
    tar = tarWasmer;
    less = lessWasmer;
    ncurses = ncursesWasmer;
    crabsay = crabsayWasmer;
    # Wayland suite: needs Relay host imports; not plain wasmer CLI smoke.
    wayland-bridge-smoke = wayland-bridge-smokeWasmer;
    gtk4-hello = gtk4-helloWasmer;
    phpixPhp83 = phpixPhp83Wasmer;
    phpnixPhp83 = phpixPhp83Wasmer;
    phpixPhp85 = phpixPhp85Wasmer;
    phpnixPhp85 = phpixPhp85Wasmer;
    cliPlatform = cliPlatformWasmer;
  };
  # Wayland suite builds GTK + Relay host imports; GTK WASIX libs workflow owns
  # those. Keep them as wasmer.* attrs but out of .#all.
  allWasmerPackages = lib.removeAttrs packages [
    "phpixPhp83"
    "phpnixPhp83"
    "phpixPhp85"
    "phpnixPhp85"
    "wayland-bridge-smoke"
    "gtk4-hello"
  ];

  allWasmer = pkgs.runCommand "wasix-all-wasmer" {} ''
    set -euo pipefail
    mkdir -p "$out/pkg"
    ${lib.concatMapStringsSep "\n" (attrName: ''
      if [ -d "${allWasmerPackages.${attrName}}/pkg" ]; then
        # Do not preserve top-level directory permissions from Nix store paths.
        ${pkgs.coreutils}/bin/cp -R --no-preserve=mode,ownership "${allWasmerPackages.${attrName}}/pkg/." "$out/pkg/"
      fi
    '') (builtins.attrNames allWasmerPackages)}
  '';
in {
  inherit packages allWasmer;
}
