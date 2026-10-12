# niri for Android — builds the Wawona-patched niri for aarch64-linux-android
# as both a PIE executable and a static library (niri_main C ABI).
#
# Runtime model: Wawona Android runs niri nested (Wayland client of the Wawona
# compositor). The executable ships as lib/libniri_bin.so (the waypipe
# pattern: named like a JNI lib so the APK installer extracts it into the
# exec-allowed nativeLibraryDir), and libniri.a is available for the
# in-process option.
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain,
}:

let
  niriSrc = import ./src.nix { inherit pkgs; };
  libwayland = buildModule.buildForAndroid "libwayland" { };
  xkbcommon = buildModule.buildForAndroid "xkbcommon" { };
  iland = buildModule.buildForAndroid "iland" { };
  cairo = buildModule.buildForAndroid "cairo" { };
  pango = buildModule.buildForAndroid "pango" { };
  glib = buildModule.buildForAndroid "glib" { };
  harfbuzz = buildModule.buildForAndroid "harfbuzz" { };
  fontconfig = buildModule.buildForAndroid "fontconfig" { };
  freetype = buildModule.buildForAndroid "freetype" { };
  pixman = buildModule.buildForAndroid "pixman" { };
  libpng = buildModule.buildForAndroid "libpng" { };
  fribidi = buildModule.buildForAndroid "fribidi" { };
  # Transitive Requires of glib-2.0.pc / gobject-2.0.pc / fontconfig.pc.
  pcre2 = buildModule.buildForAndroid "pcre2" { };
  libffi = buildModule.buildForAndroid "libffi" { };
  expat = buildModule.buildForAndroid "expat" { };
  # glib's gettext shims (ggettext.c) call libintl; Android's bionic has none.
  libintl = buildModule.buildForAndroid "libintl" { };
  # cairo-sys-rs (via pangocairo) links the cairo-gobject glue, which the
  # minimal cairo recipe leaves out (-Dglib=disabled).
  cairoGobject = buildModule.buildForAndroid "cairo-gobject" { };

  pcDeps = [ libwayland xkbcommon cairo pango glib harfbuzz fontconfig freetype pixman libpng fribidi pcre2 libffi expat cairoGobject ];
  pcPath = lib.concatMapStringsSep ":" (d: "${d}/lib/pkgconfig") pcDeps;

  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ "aarch64-linux-android" ];
  };
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  androidLinkerWrapper = pkgs.writeShellScript "android-linker-wrapper" ''
    exec ${androidToolchain.androidCC} "$@"
  '';
in
rustPlatform.buildRustPackage {
  pname = "niri";
  version = "26.04-wawona";
  src = niriSrc;

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "smithay-0.7.0" = "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
    };
  };

  nativeBuildInputs = with buildPackages; [ pkg-config python3 ];
  buildInputs = pcDeps ++ [ iland ];

  CARGO_BUILD_TARGET = "aarch64-linux-android";
  CC_aarch64_linux_android = "${androidLinkerWrapper}";
  CXX_aarch64_linux_android = androidToolchain.androidCXX;
  AR_aarch64_linux_android = androidToolchain.androidAR;
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${androidLinkerWrapper}";

  doCheck = false;
  dontFixup = true;

  preConfigure = ''
    export PKG_CONFIG_PATH="${pcPath}:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1
    # Library search paths for crates that emit bare rustc-link-lib without a
    # pkg-config search path (e.g. the xkbcommon crate).
    export RUSTFLAGS="-A warnings ${lib.concatMapStringsSep " " (d: "-L native=${d}/lib") pcDeps} $RUSTFLAGS"
    # Trailing link inputs (after all crate/native archives):
    # - libintl for glib's gettext calls,
    # - clang_rt builtins for __clear_cache (libffi closures); rustc links
    #   with -nodefaultlibs, so clang's driver never adds it.
    builtins_rt=$(${androidToolchain.androidCC} -print-libgcc-file-name)
    export RUSTFLAGS="$RUSTFLAGS -L native=${libintl}/lib -C link-arg=-lintl -C link-arg=$builtins_rt"
    # iland EGL + Wayland-EGL. Target-only so host proc-macros are not linked.
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-L native=${iland}/lib -C link-arg=-Wl,--whole-archive -C link-arg=-liland_userland -C link-arg=-liland_wayland_egl -C link-arg=-Wl,--no-whole-archive $CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS"

    # Apple mobile / Android link wwn-iland. Resolve EGL from this process.
    for sm in "$NIX_BUILD_TOP"/cargo-vendor-dir/smithay-*/src/backend/egl/ffi.rs; do
      if [ -f "$sm" ]; then
        python3 - "$sm" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = """    pub static LIB: LazyLock<Library> =
        LazyLock::new(|| unsafe { Library::new("libEGL.so.1") }.expect("Failed to load LibEGL"));"""
new = """    pub static LIB: LazyLock<Library> = LazyLock::new(|| {
        Library::from(libloading::os::unix::Library::this())
    });"""
if old not in text:
    raise SystemExit(f"smithay EGL loader anchor missing: {path}")
path.write_text(text.replace(old, new, 1))
PY
        echo "Patched smithay EGL loader to current-process iland symbols"
      fi
    done
  '';

  # Explicit buildPhase: the stock cargoBuildHook pins --target to the Nix
  # host platform (aarch64-apple-darwin on the Darwin build host), which both
  # misses the cross target and drags host builds of pango-sys & co.
  buildPhase = ''
    runHook preBuild
    echo "Building niri (bin + staticlib) for aarch64-linux-android..."
    cargo build --target aarch64-linux-android --release --offline --no-default-features
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib $out/share/niri

    search_roots="''${CARGO_TARGET_DIR:-target} target"
    bin=$(find $search_roots -type f -name niri -path "*aarch64-linux-android*release*" 2>/dev/null | head -1)
    if [ -z "$bin" ]; then
      echo "ERROR: niri (aarch64-linux-android) executable not found" >&2
      exit 1
    fi
    cp "$bin" $out/bin/niri
    # waypipe pattern: also stage as a JNI-named lib so the Android app can
    # bundle it into jniLibs and exec it from nativeLibraryDir. Strip debug
    # info — the unstripped ELF is ~99 MB and would balloon the APK.
    cp "$bin" $out/lib/libniri_bin.so
    chmod u+w $out/lib/libniri_bin.so
    ${androidToolchain.androidSTRIP} --strip-unneeded $out/lib/libniri_bin.so || true

    staticlib=$(find $search_roots -type f -name libniri.a 2>/dev/null | head -1)
    [ -n "$staticlib" ] && cp "$staticlib" $out/lib/libniri.a

    cp ${niriSrc}/resources/default-config.kdl $out/share/niri/default-config.kdl
    python3 ${./wawona-niri-default-config.py} $out/share/niri/default-config.kdl
    runHook postInstall
  '';

  meta = {
    description = "niri (scrollable-tiling Wayland compositor), Wawona nested port for Android";
    license = lib.licenses.gpl3Plus;
  };
}
