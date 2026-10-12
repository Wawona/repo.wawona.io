# watchOS: no Metal / DRM / ANGLE. The watch iland recipe is a stub, so
# this archive only satisfies the weston GL probe link.
{ lib, pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "kmscube-watchos-stub";
  version = "0.1.0";
  dontUnpack = true;
  buildPhase = ''
    printf '%s\n' \
      'int kmscube_main(int argc, char **argv) { (void)argc; (void)argv; return 1; }' \
      > stub.c
    $CC -c stub.c -o stub.o
    $AR rcs libkmscube.a stub.o
  '';
  installPhase = ''
    mkdir -p $out/lib $out/include $out/nix-support
    cp libkmscube.a $out/lib/
    cat > $out/include/kmscube.h <<'H'
#ifndef WAWONA_KMSCUBE_H
#define WAWONA_KMSCUBE_H
int kmscube_main(int argc, char *argv[]);
#endif
H
    echo stub > $out/nix-support/link-kind
  '';
}
