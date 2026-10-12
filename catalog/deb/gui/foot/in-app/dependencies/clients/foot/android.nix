# foot for Android — PIE executable + libfoot_bin.so (waypipe/niri/fuzzel pattern)
# plus a tiny libfoot.so companion exporting foot_main / wwn_foot_is_compat_shim.
# https://codeberg.org/dnkl/foot
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
  footSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "foot";
    tag = "1.26.1";
    sha256 = "sha256-N9/lxbz9nLIGC7VyuRbNbuX0K0XAxhytLzsU16BMCWY=";
  };
  src = fetchSource footSource;

  libwayland = buildModule.buildForAndroid "libwayland" { };
  pixman = buildModule.buildForAndroid "pixman" { };
  xkbcommon = buildModule.buildForAndroid "xkbcommon" { };
  fcft = buildModule.buildForAndroid "fcft" { };
  tllist = buildModule.buildForAndroid "tllist" { };
  utf8proc = buildModule.buildForAndroid "utf8proc" { };
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
    utf8proc
    fontconfig
    freetype
    expat
    libpng
    libffi
  ];
  pcPath = lib.concatMapStringsSep ":" (d: "${d}/lib/pkgconfig") pcDeps;

  # Host wayland-scanner for protocol codegen (meson build-machine tool).
  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host-foot-android";
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
  pname = "foot";
  version = "1.26.1";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    scdoc
    stdenv.cc
    waylandScanner
    wayland-protocols
    python3
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
    # Do not add -D_GNU_SOURCE here: foot's meson already sets
    # -D_GNU_SOURCE=200809L and -Werror turns the redefinition into a hard fail.
    c_args = ['-fPIC', '-D__STDC_ISO_10646__=201103L']
    cpp_args = ['-fPIC', '-D__STDC_ISO_10646__=201103L']
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
      sed -i "s/subdir('doc')/# Android: skip man pages/" meson.build || true
      sed -i "s/subdir('tests')/# Android: skip tests/" meson.build || true
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    if [ -f meson.build ]; then
      sed -i "s/subdir('doc')/# Android: skip man pages/" meson.build || true
      sed -i "s/subdir('tests')/# Android: skip tests/" meson.build || true
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
      -Ddocs=disabled \
      -Dthemes=false \
      -Dime=false \
      -Dterminfo=disabled \
      -Ddefault-terminfo=xterm-256color \
      -Dtests=false \
      -Dsystemd-units-dir=
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
    mkdir -p $out/lib $out/lib/arm64-v8a

    if [ -f "$out/bin/foot" ]; then
      cp "$out/bin/foot" $out/lib/libfoot_bin.so
      chmod u+w $out/lib/libfoot_bin.so
      ${androidToolchain.androidSTRIP} --strip-unneeded $out/lib/libfoot_bin.so || true
      chmod +x $out/lib/libfoot_bin.so
    else
      echo "ERROR: foot binary missing after install" >&2
      exit 1
    fi

    # Companion shared lib for packaging / shim probe. Real terminal runs via
    # fork+exec of libfoot_bin.so (niri pattern); foot_main here must not
    # execv into the Wawona process.
    cat > foot_android_entry.c <<'EOF'
    #include <android/log.h>
    int wwn_foot_is_compat_shim(void) { return 0; }
    int foot_main(int argc, const char **argv) {
      (void)argc;
      (void)argv;
      __android_log_print(ANDROID_LOG_ERROR, "WawonaFoot",
        "foot_main in-process entry is unused; launch libfoot_bin.so via fork/exec");
      return 1;
    }
    EOF
    API="${toString androidToolchain.androidNdkApiLevel}"
    "${androidToolchain.androidCC}" \
      --target="${androidToolchain.androidTarget}$API" \
      --sysroot="${androidToolchain.androidNdkSysroot}" \
      -B"${androidToolchain.androidNdkAbiLibDir}" \
      -L"${androidToolchain.androidNdkAbiLibDir}" \
      -Wl,-rpath-link,"${androidToolchain.androidNdkAbiLibDir}" \
      ${androidToolchain.androidNdkCflags} \
      -D__ANDROID_API__="$API" \
      -fPIC -shared foot_android_entry.c -llog -landroid \
      -o $out/lib/arm64-v8a/libfoot.so
    chmod +x $out/lib/arm64-v8a/libfoot.so

    runHook postInstall
  '';

  meta = with lib; {
    description = "Fast, lightweight Wayland terminal emulator for Android";
    homepage = "https://codeberg.org/dnkl/foot";
    license = licenses.mit;
  };
})
