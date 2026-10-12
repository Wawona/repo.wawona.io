{
  nixpkgs,
  pkgs,
  pkgsCross,
  toolchain,
  libraries,
}: rec {
  nano = pkgsCross.callPackage ./nano/nano.nix {
    inherit nixpkgs toolchain;
    ncurses = libraries.ncurses;
  };
  grep = pkgsCross.callPackage ./grep/grep.nix {
    inherit toolchain;
  };
  sed = pkgsCross.callPackage ./sed/sed.nix {
    inherit toolchain;
  };
  find = pkgsCross.callPackage ./find/find.nix {
    inherit toolchain;
  };
  gzip = pkgsCross.callPackage ./gzip/gzip.nix {
    inherit toolchain;
  };
  tar = pkgsCross.callPackage ./tar/tar.nix {
    inherit toolchain;
  };
  less = pkgsCross.callPackage ./less/less.nix {
    inherit toolchain;
    ncurses = libraries.ncurses;
  };
  ncurses = pkgsCross.callPackage ./ncurses/ncurses.nix {
    inherit nixpkgs toolchain;
  };

  crabsay = pkgs.callPackage ./crabsay/crabsay.nix {
    cargoWasix = toolchain.cargoWasix;
  };

  # Wayland / GTK programs (link libraries.*; never name a program "gtk4").
  wayland-bridge-smoke = pkgs.callPackage ./wayland-bridge-smoke/wayland-bridge-smoke.nix {
    cargoWasix = toolchain.cargoWasix;
  };
  gtk4-hello = pkgsCross.callPackage ./gtk4-hello/gtk4-hello.nix {
    inherit toolchain libraries;
  };

  phpixPhp83 = pkgs.callPackage ./phpix/phpixPhp83.nix {
    cargoWasix = toolchain.cargoWasix;
    inherit toolchain;
    php83ZTS = libraries.php83ZTS;
  };
  phpixPhp85 = pkgs.callPackage ./phpix/phpixPhp85.nix {
    cargoWasix = toolchain.cargoWasix;
    inherit toolchain;
    php85ZTS = libraries.php85ZTS;
  };
}
