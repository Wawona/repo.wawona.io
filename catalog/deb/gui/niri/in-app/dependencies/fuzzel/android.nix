# fuzzel for Android — PIE executable + libfuzzel_bin.so (waypipe/niri pattern).
# Nested niri Mod+D spawns "fuzzel" via PATH → usr/bin/fuzzel → jniLibs.
# https://codeberg.org/dnkl/fuzzel
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain,
  androidMesonSandbox ? null,
}:

let
  fetchSource = common.fetchSource;
  fuzzelSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "fuzzel";
    tag = "1.14.1";
    sha256 = "sha256-W3+K22p82x05tgmeAeUvN4qIeJZvnfeU6l+dJZONPMQ=";
  };
  src = fetchSource fuzzelSource;

  libwayland = buildModule.buildForAndroid "libwayland" { };
  pixman = buildModule.buildForAndroid "pixman" { };
  xkbcommon = buildModule.buildForAndroid "xkbcommon" { };
  fcft = buildModule.buildForAndroid "fcft" { };
  tllist = buildModule.buildForAndroid "tllist" { };
  fontconfig = buildModule.buildForAndroid "fontconfig" { };
  freetype = buildModule.buildForAndroid "freetype" { };
  expat = buildModule.buildForAndroid "expat" { };
  libpng = buildModule.buildForAndroid "libpng" { };
  libffi = buildModule.buildForAndroid "libffi" { };

  pcDeps = [
    libwayland
    pixman
    xkbcommon
    fcft
    tllist
    fontconfig
    freetype
    expat
    libpng
    libffi
  ];
  pcPath = lib.concatMapStringsSep ":" (d: "${d}/lib/pkgconfig") pcDeps;

  # Host wayland-scanner for protocol codegen (meson build-machine tool).
  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host-fuzzel-android";
    src = pkgs.wayland.src;
    depsBuildBuild = with buildPackages; [ libxml2 expat ];
    nativeBuildInputs = with buildPackages; [
      meson
      ninja
      pkg-config
      python3
      libxml2
      expat
    ];
    configurePhase = ''
      export PKG_CONFIG_PATH="${buildPackages.libxml2.dev}/lib/pkgconfig:${buildPackages.expat.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
      meson setup build \
        --prefix=$out \
        -Dlibraries=false \
        -Ddocumentation=false \
        -Dtests=false
    '';
    buildPhase = ''
      meson compile -C build wayland-scanner
    '';
    installPhase = ''
      mkdir -p $out/bin $out/share/pkgconfig
      SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
      [ -n "$SCANNER_BIN" ] || { echo "wayland-scanner not found" >&2; exit 1; }
      cp "$SCANNER_BIN" $out/bin/wayland-scanner
      cat > $out/share/pkgconfig/wayland-scanner.pc <<EOF
prefix=$out
wayland_scanner=$out/bin/wayland-scanner
Name: Wayland Scanner
Description: Wayland scanner (host)
Version: 1.23.0
EOF
    '';
  };

  applySandbox =
    attrs:
    if androidMesonSandbox != null then
      androidMesonSandbox.apply attrs
    else
      attrs;
in
pkgs.stdenv.mkDerivation (applySandbox {
  pname = "fuzzel";
  version = "1.14.1";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    scdoc
    stdenv.cc
    waylandScanner
    wayland-protocols
  ];
  buildInputs = [ ];

  preConfigure = ''
    export PATH="${waylandScanner}/bin:$PATH"
    export PKG_CONFIG_PATH="${pcPath}:''${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:${buildPackages.wayland-protocols}/share/pkgconfig:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
    export PKG_CONFIG_ALLOW_CROSS=1

    cat > android-cross-file.txt <<EOF
    [binaries]
    c = '${androidToolchain.androidCC}'
    cpp = '${androidToolchain.androidCXX}'
    ar = '${androidToolchain.androidAR}'
    strip = '${androidToolchain.androidSTRIP}'
    pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'
    wayland_scanner = '${waylandScanner}/bin/wayland-scanner'

    [host_machine]
    system = 'android'
    cpu_family = 'aarch64'
    cpu = 'aarch64'
    endian = 'little'

    [built-in options]
    c_args = ['-fPIC', '-D_GNU_SOURCE', '-D__STDC_ISO_10646__=201103L']
    cpp_args = ['-fPIC', '-D_GNU_SOURCE', '-D__STDC_ISO_10646__=201103L']
    c_link_args = ['-Wl,-rpath,\$ORIGIN']
    cpp_link_args = ['-Wl,-rpath,\$ORIGIN']
    EOF

    cat > native-file.txt <<EOF
    [binaries]
    c = '${buildPackages.stdenv.cc}/bin/cc'
    cpp = '${buildPackages.stdenv.cc}/bin/c++'
    ar = '${buildPackages.stdenv.cc}/bin/ar'
    strip = 'strip'
    pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
    wayland_scanner = '${waylandScanner}/bin/wayland-scanner'
    EOF
  '';

  dontUseMesonConfigure = true;

  postPatch = ''
    # Skip man-page generation (scdoc .pc often unavailable in cross builds).
    if [ -f meson.build ]; then
      sed -i "s/subdir('doc')/# Android: skip man pages/" meson.build
    fi
    # Nested compositor HUP: skip wl_* destroys (else wl_closure_send SEGV).
    patch -p1 < ${./wawona-safe-wayland-teardown.patch}
  '';

  configurePhase = ''
    runHook preConfigure
    if [ -f meson.build ]; then
      sed -i "s/subdir('doc')/# Android: skip man pages/" meson.build || true
    fi
    export PATH="${waylandScanner}/bin:$PATH"
    export PKG_CONFIG_PATH="${pcPath}:''${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:${buildPackages.wayland-protocols}/share/pkgconfig:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
    export PKG_CONFIG_ALLOW_CROSS=1
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --bindir=$out/bin \
      --native-file=native-file.txt \
      --cross-file=android-cross-file.txt \
      --buildtype=release \
      -Denable-cairo=disabled \
      -Dpng-backend=libpng \
      -Dsvg-backend=nanosvg
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export PATH="${waylandScanner}/bin:$PATH"
    export PKG_CONFIG_PATH="${pcPath}:''${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:${buildPackages.wayland-protocols}/share/pkgconfig:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    meson install -C build
    mkdir -p $out/lib
    if [ -f "$out/bin/fuzzel" ]; then
      cp "$out/bin/fuzzel" $out/lib/libfuzzel_bin.so
      chmod u+w $out/lib/libfuzzel_bin.so
      ${androidToolchain.androidSTRIP} --strip-unneeded $out/lib/libfuzzel_bin.so || true
      chmod +x $out/lib/libfuzzel_bin.so
    else
      echo "ERROR: fuzzel binary missing after install" >&2
      exit 1
    fi
    runHook postInstall
  '';

  meta = with lib; {
    description = "Wayland application launcher (niri Mod+D) for Android";
    homepage = "https://codeberg.org/dnkl/fuzzel";
    license = licenses.mit;
  };
})
