# foot — real in-process static archive for Apple mobile
# (iOS / iPadOS / tvOS / watchOS / visionOS). Replaces the weston-terminal shim.
# Shell spawn uses wawona-pty (no fork/exec) — App Store safe.
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
  xcodeUtils ? iosToolchain,
  toolchainSrc ? null,
  ...
}:

let
  fetchSource = common.fetchSource;
  mobile = (import "${toolchainSrc}/dependencies/toolchains/apple-mobile-platform.nix") {
    inherit iosToolchain simulator;
  };

  footSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "foot";
    tag = "1.26.1";
    sha256 = "sha256-N9/lxbz9nLIGC7VyuRbNbuX0K0XAxhytLzsU16BMCWY=";
  };
  src = fetchSource footSource;

  linuxInputHeaders = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/45dcf5e28813954da4150e7260ccb61e95856176/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-CqF1r2sCoJbn3Bcr0x6B1JnrqQg3d1FejCCqkVq3new=";
  };

  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  pixman = buildModule.buildForIOS "pixman" { inherit simulator; };
  xkbcommon = buildModule.buildForIOS "xkbcommon" { inherit simulator; };
  fcft = buildModule.buildForIOS "fcft" { inherit simulator; };
  tllist = buildModule.buildForIOS "tllist" { inherit simulator; };
  utf8proc = buildModule.buildForIOS "utf8proc" { inherit simulator; };
  fontconfig = buildModule.buildForIOS "fontconfig" { inherit simulator; };
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  epoll-shim = buildModule.buildForIOS "epoll-shim" { inherit simulator; };
  expat = buildModule.buildForIOS "expat" { inherit simulator; };
  wawonaPty = buildModule.buildForIOS "wawona-pty" { inherit simulator; };

  pcDeps = [
    libwayland
    pixman
    xkbcommon
    fcft
    tllist
    utf8proc
    fontconfig
    freetype
    epoll-shim
    expat
  ];
  pcPath = lib.concatMapStringsSep ":" (d: "${d}/lib/pkgconfig") pcDeps;

  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host-foot-apple-mobile";
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
in
assert toolchainSrc != null;
pkgs.stdenv.mkDerivation {
  pname = "foot-apple-mobile";
  version = "1.26.1";
  inherit src;

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    waylandScanner
    pkgs.wayland-protocols
    xcodeUtils.findXcodeScript
  ];
  buildInputs = [ ];

  dontUseMesonConfigure = true;

  postPatch = ''
    export LINUX_INPUT_HEADERS=${linuxInputHeaders}
    bash ${./patches/generate-darwin-compat.sh}
    cp ${./patches/patch-foot-apple-mobile.py} ./patch-foot-apple-mobile.py
    cp ${wawonaPty}/include/wwn_pty.h ./wwn_pty.h
    ${buildPackages.python3}/bin/python3 ./patch-foot-apple-mobile.py

    # Xcode's python3 is often <3.10 and rejects PEP604 unions in foot scripts.
    # Force both scripts through nixpkgs python via shebang + Absolute meson path.
    for s in scripts/generate-emoji-variation-sequences.py scripts/generate-builtin-terminfo.py scripts/srgb.py; do
      [ -f "$s" ] || continue
      ${buildPackages.python3}/bin/python3 - <<PY
from pathlib import Path
p = Path("$s")
t = p.read_text()
t = t.replace("None | int", "Optional[int]").replace("None|int", "Optional[int]")
t = t.replace("bool | int | str", "Union[bool, int, str]")
t = t.replace("bool|int|str", "Union[bool, int, str]")
if "Optional[" in t and "from typing import" not in t:
    lines = t.splitlines(True)
    # after shebang / encoding
    i = 1 if lines and lines[0].startswith("#!") else 0
    lines.insert(i, "from typing import Optional, Union\n")
    t = "".join(lines)
elif "Union[" in t and "from typing import" not in t:
    lines = t.splitlines(True)
    i = 1 if lines and lines[0].startswith("#!") else 0
    lines.insert(i, "from typing import Optional, Union\n")
    t = "".join(lines)
if t.startswith("#!"):
    t = "#!${buildPackages.python3}/bin/python3\n" + "\n".join(t.splitlines()[1:]) + "\n"
else:
    t = "#!${buildPackages.python3}/bin/python3\n" + t
p.write_text(t)
PY
    done

    if [ -f meson.build ]; then
      sed -i "s/subdir('doc')/# Apple mobile: skip man pages/" meson.build || true
      sed -i "s/subdir('tests')/# Apple mobile: skip tests/" meson.build || true
      ${buildPackages.python3}/bin/python3 - <<'PY'
from pathlib import Path
p = Path("meson.build")
t = p.read_text()
start = t.find("executable(\n  'footclient',")
if start < 0:
    start = t.find("executable(\n  'footclient'")
if start >= 0:
    end = t.find("install: true)", start)
    if end > start:
        end = t.find("\n", end) + 1
        t = t[:start] + "# footclient omitted on Apple mobile\n" + t[end:]
        p.write_text(t)
PY
    fi
  '';

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv {
      inherit simulator;
      minVersion = mobile.minVersion;
    }}
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CC="$XCODE_CLANG"
    export CXX="$XCODE_CLANGXX"
    export PATH="${buildPackages.python3}/bin:${waylandScanner}/bin:$PATH"
    export PKG_CONFIG_PATH="${pcPath}:${epoll-shim}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:${buildPackages.wayland-protocols}/share/pkgconfig:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
    export PKG_CONFIG_ALLOW_CROSS=1

    # Ensure meson codegen uses nixpkgs python3 (>=3.10), not Xcode's.
    export PYTHON="${buildPackages.python3}/bin/python3"

    _CC="$XCODE_CLANG"
    _CXX="$XCODE_CLANGXX"
    _SDK="$SDKROOT"
    _ARCH="$IOS_ARCH"
    _DEPLOY="$APPLE_DEPLOYMENT_FLAG"
    _TARGET="$APPLE_LINKER_TARGET"
    _EPOLL_INC="${epoll-shim}/include/libepoll-shim"
    _COMPAT="$(pwd)/compat"
    _PTY_INC="${wawonaPty}/include"

    cat > ios-cross.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
c_for_build = '${buildPackages.clang}/bin/clang'
cpp_for_build = '${buildPackages.clang}/bin/clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = 'pkg-config'
wayland_scanner = '${waylandScanner}/bin/wayland-scanner'
python = '${buildPackages.python3}/bin/python3'
python3 = '${buildPackages.python3}/bin/python3'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
objc_args = ['-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-fobjc-arc']
objcpp_args = ['-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-fobjc-arc']
c_args = ['-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC',
          '-I$_COMPAT', '-I$_EPOLL_INC', '-I$_PTY_INC',
          '-D__STDC_ISO_10646__=201103L', '-Wno-deprecated-declarations', '-DSIGRTMAX=32',
          '-DWAWONA_APPLE_MOBILE=1']
c_link_args = ['-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY',
               '-L${epoll-shim}/lib', '-lepoll-shim']
needs_exe_wrapper = true
EOF
  '';

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    # Prefer nixpkgs python3 for meson Program('python3') discovery.
    export PATH="${buildPackages.python3}/bin:$PATH"
    cat > native-file.txt <<EOF
[binaries]
python = '${buildPackages.python3}/bin/python3'
python3 = '${buildPackages.python3}/bin/python3'
c = '${buildPackages.clang}/bin/clang'
cpp = '${buildPackages.clang}/bin/clang++'
pkg-config = 'pkg-config'
wayland_scanner = '${waylandScanner}/bin/wayland-scanner'
EOF
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --native-file=native-file.txt \
      --cross-file=ios-cross.txt \
      --buildtype=release \
      -Ddocs=disabled \
      -Dthemes=false \
      -Dime=false \
      -Dterminfo=disabled \
      -Ddefault-terminfo=xterm-256color \
      -Dtests=false \
      -Dsystemd-units-dir= \
      -Ddefault_library=static
    # Meson may still bake Xcode's python3 into build.ninja — rewrite.
    if [ -f build/build.ninja ]; then
      sed -i.bak "s|/Applications/Xcode.app/Contents/Developer/usr/bin/python3|${buildPackages.python3}/bin/python3|g" build/build.ninja || true
    fi
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export PATH="${buildPackages.python3}/bin:${waylandScanner}/bin:$PATH"
    export PKG_CONFIG_PATH="${pcPath}:''${PKG_CONFIG_PATH:-}"
    if [ -f build/build.ninja ]; then
      sed -i.bak "s|/Applications/Xcode.app/Contents/Developer/usr/bin/python3|${buildPackages.python3}/bin/python3|g" build/build.ninja || true
    fi
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/include

    # Re-establish SDK env for the probe compile (configure unset SDKROOT).
    ${iosToolchain.mkIOSBuildEnv {
      inherit simulator;
      minVersion = mobile.minVersion;
    }}

    LIBFOOT=$(find build -name 'libfoot.a' | head -n 1)
    if [ -n "$LIBFOOT" ]; then
      cp "$LIBFOOT" $out/lib/libfoot.a
    else
      OBJ_LIST=$(find build -name '*.o' ! -path '*/footclient*' ! -path '*/pgo/*' | tr '\n' ' ')
      ar rcs $out/lib/libfoot.a $OBJ_LIST
    fi

    cat > wwn_foot_shim_probe.c <<'EOF'
int wwn_foot_is_compat_shim(void) { return 0; }
EOF
    AR_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
    NM_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/nm"
    $XCODE_CLANG -c wwn_foot_shim_probe.c \
      -arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT \
      $APPLE_DEPLOYMENT_FLAG -fPIC \
      -o wwn_foot_shim_probe.o
    "$AR_BIN" rcs $out/lib/libfoot.a wwn_foot_shim_probe.o

    # Bundle utf8proc objects so libfoot.a is self-contained. foot 1.26.1's
    # term_process_and_print_non_ascii references utf8proc_charwidth /
    # utf8proc_grapheme_break_stateful; utf8proc is only a pkg-config build input
    # here, so without this the final app link (xcodegen -force_load libfoot.a)
    # fails with undefined utf8proc symbols on every Apple-mobile target.
    UTF8PROC_A=$(find ${utf8proc}/lib -name 'libutf8proc*.a' 2>/dev/null | head -n 1)
    if [ -n "$UTF8PROC_A" ]; then
      _utf8dir=$(mktemp -d)
      ( cd "$_utf8dir" && "$AR_BIN" x "$UTF8PROC_A" )
      _utf8objs=$(find "$_utf8dir" -name '*.o' | tr '\n' ' ')
      if [ -n "$_utf8objs" ]; then
        "$AR_BIN" rcs $out/lib/libfoot.a $_utf8objs
        echo "Bundled utf8proc objects from $UTF8PROC_A into libfoot.a"
      else
        echo "ERROR: no objects extracted from $UTF8PROC_A" >&2
        exit 1
      fi
    else
      echo "ERROR: libutf8proc.a not found under ${utf8proc}/lib" >&2
      exit 1
    fi

    # Deduplicate archive members. foot's meson build emits some generated
    # protocol/srgb objects twice (identical content, same basename). A duplicate
    # member makes a later `ld -r -all_load` (Wawona's privatize step) fail with
    # duplicate symbols. Extracting overwrites same-named members, leaving one
    # copy per basename; re-archive a clean copy.
    _dedup_dir=$(mktemp -d)
    ( cd "$_dedup_dir" && "$AR_BIN" x $out/lib/libfoot.a )
    _dedup_objs=$(find "$_dedup_dir" -name '*.o' | sort)
    if [ -n "$_dedup_objs" ]; then
      rm -f $out/lib/libfoot.a
      "$AR_BIN" rcs $out/lib/libfoot.a $_dedup_objs
      echo "Deduplicated libfoot.a members ($(printf '%s\n' "$_dedup_objs" | wc -l | tr -d ' ') unique objects)"
    else
      echo "ERROR: no objects extracted while deduplicating libfoot.a" >&2
      exit 1
    fi

    cat > $out/include/foot.h <<'EOF'
#ifndef WAWONA_FOOT_H
#define WAWONA_FOOT_H
int foot_main(int argc, char *argv[]);
int wwn_foot_is_compat_shim(void);
#endif
EOF

    SYMS=$("$NM_BIN" -gU $out/lib/libfoot.a 2>/dev/null || "$NM_BIN" -g $out/lib/libfoot.a 2>/dev/null || true)
    echo "$SYMS" | grep -E '_foot_main[[:space:]]' >/dev/null \
      || echo "$SYMS" | grep -F '_foot_main' >/dev/null \
      || { echo "ERROR: missing foot_main in libfoot.a" >&2; echo "$SYMS" | head -40 >&2; exit 1; }
    echo "$SYMS" | grep -F '_wwn_foot_is_compat_shim' >/dev/null \
      || { echo "ERROR: missing wwn_foot_is_compat_shim" >&2; echo "$SYMS" | head -40 >&2; exit 1; }

    runHook postInstall
  '';

  meta = with lib; {
    description = "Foot terminal in-process archive for Apple mobile (wawona-pty shell)";
    homepage = "https://codeberg.org/dnkl/foot";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
