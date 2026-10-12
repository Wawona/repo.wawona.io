# Standalone Neovim binary for macOS (+ optional in-process archive header).
args@{
  lib,
  pkgs,
  buildPackages,
  ...
}:

let
  inherit (args) lib pkgs buildPackages;
  neovimSrc = import ./common.nix { inherit pkgs; };
  version = import ./version.nix;
  helpers = import ./build-helpers.nix {
    inherit lib pkgs buildPackages neovimSrc version;
  };
in
pkgs.stdenv.mkDerivation {
  pname = "neovim-macos";
  inherit version;
  src = neovimSrc;

  __noChroot = true;
  dontConfigure = true;

  nativeBuildInputs = helpers.macNative;

  buildPhase = ''
    runHook preBuild
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export CURL_CA_BUNDLE=$SSL_CERT_FILE
    export CMAKE_BUILD_TYPE=Release
    export CMAKE_EXTRA_FLAGS="${helpers.cmakeExtraMac}"
    make deps -j''${NIX_BUILD_CORES:-4}
    make -j''${NIX_BUILD_CORES:-4}
    WORKDIR=$(mktemp -d)
    SRC_ROOT="$PWD"
    find build -path '*/nvim_bin.dir/*.o' -exec cp {} "$WORKDIR"/ \;
    for lib in "$SRC_ROOT"/.deps/usr/lib/*.a; do
      [ -f "$lib" ] || continue
      (cd "$WORKDIR" && ar x "$lib")
    done
    MAIN_OBJ="$WORKDIR/main.c.o"
    if [ ! -f "$MAIN_OBJ" ]; then
      echo "main.c.o missing" >&2
      exit 1
    fi
    ${pkgs.llvmPackages.llvm}/bin/llvm-objcopy --redefine-sym _main=_wawona_nvim_main \
      "$MAIN_OBJ" "$WORKDIR/wawona_nvim_main.o"
    rm -f "$MAIN_OBJ"
    ar rcs libwawona-neovim.a "$WORKDIR"/*.o
    rm -rf "$WORKDIR"
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include $out/share/nvim
    cp build/bin/nvim $out/bin/
    cp libwawona-neovim.a $out/lib/
    cp -R runtime $out/share/nvim/
    cat > $out/include/wawona-neovim.h <<'EOF'
#ifndef WAWONA_NEOVIM_H
#define WAWONA_NEOVIM_H
int wawona_nvim_main(int argc, char **argv);
#endif
EOF
  '';

  meta = with lib; {
    description = "Neovim for macOS (Wawona wwn-neovim port)";
    homepage = "https://neovim.io";
    license = licenses.asl20;
    platforms = platforms.darwin;
  };
}
