# Unpack Termux aarch64 .debs into a pkg-config sysroot for NDK cross builds.
# Runtime: Termux apt installs the same packages; process debs Declare Depends.
# Not for Play. Not glibc.
{ pkgs, debs }:

pkgs.stdenv.mkDerivation {
  pname = "termux-sysroot-aarch64";
  version = "1";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;
  # Foreign Termux ELFs + dangling doc→LICENSES symlinks. Not a host package.
  dontFixup = true;

  nativeBuildInputs = [ pkgs.dpkg pkgs.gnutar pkgs.xz pkgs.gzip pkgs.gnused ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out extract
    for deb in ${pkgs.lib.concatStringsSep " " (map toString debs)}; do
      dpkg-deb -x "$deb" extract
    done
    if [ -d extract/data/data/com.termux/files/usr ]; then
      cp -a extract/data/data/com.termux/files/usr/. $out/
    else
      echo "termuxSysroot: unexpected deb layout" >&2
      find extract -maxdepth 5 -type d >&2 || true
      exit 1
    fi
    if [ -d $out/lib/pkgconfig ]; then
      for pc in $out/lib/pkgconfig/*.pc; do
        [ -f "$pc" ] || continue
        sed -i \
          -e "s|^prefix=.*|prefix=$out|" \
          -e "s|/data/data/com.termux/files/usr|$out|g" \
          "$pc"
      done
    fi
    runHook postInstall
  '';

  meta = {
    description = "Termux aarch64 headers/libs sysroot for NDK cross builds";
    homepage = "https://termux.dev";
  };
}
