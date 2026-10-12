# niri for macOS — Wawona-patched niri (v26.04 + nested + macOS DRM tty).
#
# Mode A: nested (WAYLAND_DISPLAY -> Wawona, NIRI_BACKEND=nested). GLES via
# iland's EGL (force-loaded; ANGLE is dlopened as a private image).
# Mode B: session compositor (no WAYLAND_DISPLAY, NIRI_BACKEND=tty) against
# iland userspace DRM/KMS/GBM/udev/libinput. L0 epoll-shim supplies eventfd(2)
# for smithay drm_syncobj (same substrate as libwayland). The dylib
# libwayland-mac.dylib still does Dobby open()/ioctl interpose plus
# framebufferd/inputd at engage time.
{
  lib,
  pkgs,
  common,
  buildModule,
  ilandSrc ? null,
}:

let
  niriSrc = import ./src.nix { inherit pkgs; };
  libwayland = buildModule.buildForMacOS "libwayland" { };
  xkbcommon = buildModule.buildForMacOS "xkbcommon" { };
  iland = buildModule.buildForMacOS "iland" { };
  angle = buildModule.buildForMacOS "angle" { };
  epollShim = buildModule.buildForMacOS "epoll-shim" { };
  cargoTarget = pkgs.stdenv.hostPlatform.rust.rustcTarget;
  ilandUpstream =
    if ilandSrc != null then "${ilandSrc}/dependencies/libs/iland/upstream" else null;
in
assert ilandSrc != null && ilandUpstream != null;
pkgs.rustPlatform.buildRustPackage {
  pname = "niri";
  version = "26.04-wawona";
  src = niriSrc;

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "smithay-0.7.0" = "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
    };
  };

  # dbus/systemd/xdp-gnome-screencast are desktop-Linux session integration.
  buildNoDefaultFeatures = true;
  buildFeatures = [ ];

  nativeBuildInputs = [ pkgs.pkg-config pkgs.clang pkgs.python3 ];

  buildInputs = [
    libwayland
    xkbcommon
    iland
    angle
    epollShim
    pkgs.pango
    pkgs.cairo
    pkgs.glib
    pkgs.libiconv
  ];

  CARGO_BUILD_TARGET = cargoTarget;

  doCheck = false;

  preConfigure = ''
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    export SDKROOT="$MACOS_SDK"

    SHIM="$NIX_BUILD_TOP/niri-drm-shims"
    mkdir -p "$SHIM/include/libseat" "$SHIM/lib" "$SHIM/pkgconfig"
    cp ${./macos-libseat.h} "$SHIM/include/libseat/libseat.h"
    cp ${ilandUpstream}/shims/udev/include/libudev.h "$SHIM/include/libudev.h"
    cp ${ilandUpstream}/shims/libinput/include/libinput.h "$SHIM/include/libinput.h"
    cp ${ilandUpstream}/shims/libinput/include/input_ipc.h "$SHIM/include/input_ipc.h"
    cp ${iland}/include/gbm.h "$SHIM/include/gbm.h" || true
    cp ${iland}/include/xf86drm.h "$SHIM/include/xf86drm.h" || true
    cp ${iland}/include/xf86drmMode.h "$SHIM/include/xf86drmMode.h" || true
    cp ${iland}/include/drm.h "$SHIM/include/drm.h" || true
    cp ${iland}/include/drm_fourcc.h "$SHIM/include/drm_fourcc.h" || true

    CLANG="${pkgs.clang}/bin/clang"
    SHIM_CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -fPIC -O2 -std=c11 \
      -I$SHIM/include -I$SHIM/include/libseat -I${iland}/include"
    cat ${ilandUpstream}/shims/udev/src/udev.c ${./macos-udev-niri-extra.c} \
      > "$SHIM/udev-full.c"
    cat ${ilandUpstream}/shims/libinput/input/libinput.c \
      ${./macos-libinput-niri-extra.c} > "$SHIM/libinput-full.c"
    "$CLANG" -c "$SHIM/udev-full.c" $SHIM_CFLAGS -o "$SHIM/udev.o"
    "$CLANG" -c "$SHIM/libinput-full.c" $SHIM_CFLAGS \
      -o "$SHIM/libinput.o"
    "$CLANG" -c ${./macos-libseat-stub.c} $SHIM_CFLAGS -o "$SHIM/libseat.o"
    ar rcs "$SHIM/lib/libniri_drm_shims.a" "$SHIM/udev.o" "$SHIM/libinput.o" "$SHIM/libseat.o"
    # input-sys / libudev-sys / libseat-sys pass -linput/-ludev/-lseat regardless of
    # the .pc Libs line. Same archive, Linux soname.
    ln -sf libniri_drm_shims.a "$SHIM/lib/libinput.a"
    ln -sf libniri_drm_shims.a "$SHIM/lib/libudev.a"
    ln -sf libniri_drm_shims.a "$SHIM/lib/libseat.a"
    ln -sf ${iland}/lib/libiland_userland.a "$SHIM/lib/libgbm.a"
    ln -sf ${iland}/lib/libiland_userland.a "$SHIM/lib/libdrm.a"

    cat > "$SHIM/pkgconfig/libudev.pc" <<EOF
Name: libudev
Description: iland udev shim for macOS niri DRM
Version: 255
Cflags: -I$SHIM/include
Libs: -L$SHIM/lib -lniri_drm_shims
EOF
    cat > "$SHIM/pkgconfig/libinput.pc" <<EOF
Name: libinput
Description: iland libinput shim for macOS niri DRM
Version: 1.25.0
Cflags: -I$SHIM/include
Libs: -L$SHIM/lib -lniri_drm_shims
EOF
    cat > "$SHIM/pkgconfig/libseat.pc" <<EOF
Name: libseat
Description: libseat stub for macOS niri DRM
Version: 0.7.0
Cflags: -I$SHIM/include -I$SHIM/include/libseat
Libs: -L$SHIM/lib -lniri_drm_shims
EOF
    cat > "$SHIM/pkgconfig/libdrm.pc" <<EOF
Name: libdrm
Description: iland DRM/KMS for macOS niri
Version: 2.4.120
Cflags: -I$SHIM/include -I${iland}/include
Libs: -L${iland}/lib -liland_userland
EOF
    cat > "$SHIM/pkgconfig/gbm.pc" <<EOF
Name: gbm
Description: iland GBM for macOS niri
Version: 22.0.0
Cflags: -I$SHIM/include -I${iland}/include
Libs: -L${iland}/lib -liland_userland
EOF
    cat > "$SHIM/pkgconfig/egl.pc" <<EOF
Name: egl
Description: iland EGL (Wayland-EGL winsys; ANGLE is dlopened)
Version: 1.5
Cflags: -I${angle}/include -I${iland}/include
Libs: -L${iland}/lib -liland_userland
EOF
    cat > "$SHIM/pkgconfig/glesv2.pc" <<EOF
Name: glesv2
Description: ANGLE GLES2
Version: 2.0
Cflags: -I${angle}/include -I${iland}/include
Libs: -L${angle}/lib -lGLESv2
EOF

    export PKG_CONFIG_PATH="$SHIM/pkgconfig:${libwayland}/lib/pkgconfig:${xkbcommon}/lib/pkgconfig:${epollShim}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export NIX_CFLAGS_COMPILE="-I${epollShim}/include/libepoll-shim $NIX_CFLAGS_COMPILE"
    export RUSTFLAGS="-A warnings $RUSTFLAGS"
    # Public EGL is iland's libEGL.dylib (Wayland-EGL + dma_buf). ANGLE is
    # dlopened as libEGL_angle.dylib. Do not -lEGL from the ANGLE prefix.
    export NIX_LDFLAGS="$NIX_LDFLAGS -L$SHIM/lib -lniri_drm_shims -L${epollShim}/lib -lepoll-shim -L${iland}/lib -liland_userland -L${libwayland}/lib -lwayland-client -L${angle}/lib -lGLESv2 -framework IOSurface -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework Accelerate -framework QuartzCore -framework Metal -framework IOKit"
    # iland libEGL.dylib is the public EGL ABI. Target-only: NIX_LDFLAGS -lEGL
    # would LC_LOAD @rpath/libEGL into host proc-macro build scripts.
    export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="-C link-arg=-L${iland}/lib -C link-arg=-lEGL $CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS"
    export CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS="-C link-arg=-L${iland}/lib -C link-arg=-lEGL $CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS"

    python3 ${./macos-rustix-eventfd-epoll-shim.py} "$NIX_BUILD_TOP/cargo-vendor-dir"

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

    for sh in "$NIX_BUILD_TOP"/cargo-vendor-dir/smithay-*/src/backend/renderer/gles/shaders/mod.rs; do
      if [ -f "$sh" ]; then
        sed -i 's/create_variant(&\[shaders::EXTERNAL\])?/create_variant(\&[])?/' "$sh"
        echo "Patched smithay GLES EXTERNAL shader for macOS ANGLE"
      fi
    done

    python3 ${./wawona-wayland-sys-dylib.py} "$NIX_BUILD_TOP"/cargo-vendor-dir/wayland-sys-*/src/server.rs \
      "$NIX_BUILD_TOP"/cargo-vendor-dir/wayland-sys-*/src/client.rs
  '';

  postInstall = ''
    mkdir -p $out/lib
    for cand in \
      "target/${cargoTarget}/release/libniri.a" \
      "target/release/libniri.a"; do
      if [ -f "$cand" ]; then
        cp "$cand" $out/lib/libniri.a
        break
      fi
    done

    mkdir -p $out/share/niri
    cp ${niriSrc}/resources/default-config.kdl $out/share/niri/default-config.kdl
    python3 ${./wawona-niri-default-config.py} $out/share/niri/default-config.kdl

    # wegl / wayland-egl crate LC_LOADs libwayland-egl, whose stubs abort.
    # wl_egl_window_* live in iland's libEGL.dylib. Point niri at that.
    if [ -f "$out/bin/niri" ]; then
      install_name_tool -add_rpath "${iland}/lib" "$out/bin/niri" 2>/dev/null || true
      old_wl_egl=$(otool -L "$out/bin/niri" | awk '/libwayland-egl/{print $1; exit}')
      if [ -n "$old_wl_egl" ]; then
        install_name_tool -change "$old_wl_egl" @rpath/libEGL.dylib "$out/bin/niri"
      fi
    fi
  '';

  meta = {
    description = "niri (scrollable-tiling Wayland compositor), Wawona nested + macOS Mode B DRM tty port";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.darwin;
    mainProgram = "niri";
  };
}
