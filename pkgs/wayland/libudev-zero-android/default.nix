# libudev-zero drop-in for Termux (no systemd). Feeds libinput on Bionic.
{ nativePkgs, androidNdk }:

let
  version = "1.0.3";
in
nativePkgs.stdenv.mkDerivation {
  pname = "libudev-zero-android";
  inherit version;

  src = nativePkgs.fetchFromGitHub {
    owner = "illiliti";
    repo = "libudev-zero";
    rev = version;
    hash = "sha256-NXDof1tfr66ywYhCBDlPa+8DUfFj6YH0dvSaxHFqsXI=";
  };

  dontPatchELF = true;
  dontStrip = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    objs=
    for src in udev.c udev_list.c udev_device.c udev_enumerate.c udev_monitor.c; do
      ${androidNdk.cc} -fPIC -O2 -I. -c -o ''${src%.c}.o $src
      objs="$objs ''${src%.c}.o"
    done
    ${androidNdk.ar} rcs libudev.a $objs
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/pkgconfig $out/include
    cp libudev.a $out/lib/
    cp udev.h $out/include/
    cp udev.h $out/include/libudev.h
    cat > $out/lib/pkgconfig/libudev.pc <<EOF
prefix=$out
libdir=$out/lib
includedir=$out/include

Name: libudev
Description: libudev-zero (Android/Termux)
# Fake systemd-compatible version: weston requires libudev >= 136.
Version: 251
Libs: -L$out/lib -ludev
Cflags: -I$out/include
EOF
    runHook postInstall
  '';

  meta = {
    description = "libudev-zero for Termux (Bionic, NDK)";
    homepage = "https://github.com/illiliti/libudev-zero";
  };
}
