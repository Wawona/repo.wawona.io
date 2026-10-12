# Standalone fastfetch binary + in-process archive for macOS.
args@{
  lib,
  pkgs,
  buildPackages,
  xcodeUtils,
  ...
}:

let
  inherit (args) lib pkgs buildPackages xcodeUtils;
  fastfetchSrc = import ./common.nix { inherit pkgs; };
in

pkgs.stdenv.mkDerivation {
  pname = "fastfetch-macos";
  version = "2.64.2";
  src = fastfetchSrc;

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    pkg-config
    python3
    xcodeUtils.findXcodeScript
  ];

  postPatch = ''
    cp ${./patches/apply-wawona-wayland-macos.py} ./apply-wawona-wayland-macos.py
    python3 apply-wawona-wayland-macos.py
  '';

  configurePhase = ''
    runHook preConfigure
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBINARY_LINK_TYPE=dlopen
  '';

  buildPhase = ''
    runHook preBuild
    ninja -C build fastfetch libfastfetch
    ${pkgs.clang}/bin/clang -c src/fastfetch.c \
      -I. -Ibuild -Isrc \
      -O2 -DFASTFETCH_TARGET_BINARY_NAME=fastfetch -Dmain=fastfetch_main \
      -o fastfetch_main.o
    find build/CMakeFiles/libfastfetch.dir -name '*.o' > objlist.txt
    ar rcs libfastfetch.a $(cat objlist.txt) fastfetch_main.o
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include
    cp build/fastfetch $out/bin/
    cp libfastfetch.a $out/lib/
    cat > $out/include/fastfetch.h <<'EOF'
#ifndef WAWONA_FASTFETCH_H
#define WAWONA_FASTFETCH_H
int fastfetch_main(int argc, char *argv[]);
#endif
EOF
  '';

  meta = with lib; {
    description = "fastfetch for macOS with Wawona Wayland WM detection";
    homepage = "https://github.com/fastfetch-cli/fastfetch";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
