# Weston nested compositor (wayland + headless backends), cross-compiled for Apple
# mobile as a single in-process static archive (libweston-compositor-13.a).
#
# Entry symbol: weston_compositor_main -> wet_main with cooperative shutdown via
# wwn_weston_compositor_shutdown_requested (volatile sig_atomic_t).
{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildPackages,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
  macos ? false,
  enableIlandDrm ? false,
  # Injected by wwn-toolchain (xcodeUtils === apple toolchain; was
  # ../../utils/xcode-wrapper.nix), iland source tree (udev/gbm shim copies;
  # was ../../libs/iland), and wwn-toolchain source tree (apple-mobile-platform.nix;
  # was ../../toolchains).
  xcodeUtils ? iosToolchain,
  ilandSrc ? null,
  toolchainSrc ? null,
  ...
}:

let
  libwayland = if macos then buildModule.buildForMacOS "libwayland" { } else buildModule.buildForIOS "libwayland" { inherit simulator; };
  xkbcommon = if macos then pkgs.libxkbcommon else buildModule.buildForIOS "xkbcommon" { inherit simulator; };
  epollShim = if macos then buildModule.buildForMacOS "epoll-shim" { } else buildModule.buildForIOS "epoll-shim" { inherit simulator; };
  pixman = if macos then pkgs.pixman else buildModule.buildForIOS "pixman" { inherit simulator; };
  cairo = if macos then pkgs.cairo else buildModule.buildForIOS "cairo" { inherit simulator; };
  pango = if macos then pkgs.pango else buildModule.buildForIOS "pango" { inherit simulator; };
  fontconfig = if macos then pkgs.fontconfig else buildModule.buildForIOS "fontconfig" { inherit simulator; };
  freetype = if macos then pkgs.freetype else buildModule.buildForIOS "freetype" { inherit simulator; };
  glib = if macos then pkgs.glib else buildModule.buildForIOS "glib" { inherit simulator; };
  harfbuzz = if macos then pkgs.harfbuzz else buildModule.buildForIOS "harfbuzz" { inherit simulator; };
  fribidi = if macos then pkgs.fribidi else buildModule.buildForIOS "fribidi" { inherit simulator; };
  libpng = if macos then pkgs.libpng else buildModule.buildForIOS "libpng" { inherit simulator; };
  expat = if macos then pkgs.expat else buildModule.buildForIOS "expat" { inherit simulator; };
  libffi = if macos then pkgs.libffi else buildModule.buildForIOS "libffi" { inherit simulator; };
  pcre2 = if macos then pkgs.pcre2 else buildModule.buildForIOS "pcre2" { inherit simulator; };

  iland =
    if enableIlandDrm then
      if macos then buildModule.buildForMacOS "iland" { }
      else buildModule.buildForIOS "iland" { inherit simulator; }
    else
      null;
  angle =
    if enableIlandDrm then
      if macos then buildModule.buildForMacOS "angle" { }
      else buildModule.buildForIOS "angle" { inherit simulator; }
    else
      null;

  ilandIncludeFlags =
    if enableIlandDrm then
      "-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include -DILAND_ANGLE_STATIC"
    else
      "";

  crossDeps =
    [
      libwayland xkbcommon pixman cairo pango fontconfig freetype glib harfbuzz
      fribidi libpng expat libffi pcre2 epollShim
    ]
    ++ lib.optionals enableIlandDrm [ iland angle ];
  pkgConfigPath = lib.concatStringsSep ":" (
    map (d: "${lib.getDev d}/lib/pkgconfig") crossDeps
  );
  crossPkgConfigDirs = lib.concatStringsSep "', '" (
    (map (d: "${lib.getDev d}/lib/pkgconfig") crossDeps)
    ++ [ "${buildPackages.wayland-protocols}/share/pkgconfig" ]
  );

  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host";
    src = pkgs.wayland.src;
    nativeBuildInputs = [
      buildPackages.meson buildPackages.ninja buildPackages.pkg-config
      buildPackages.expat buildPackages.libxml2
    ];
    configurePhase = ''
      meson setup build --prefix=$out -Dlibraries=false -Ddocumentation=false -Dtests=false
    '';
    buildPhase = ''meson compile -C build wayland-scanner'';
    installPhase = ''
      mkdir -p $out/bin $out/share/pkgconfig
      SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
      [ -n "$SCANNER_BIN" ] || { echo "wayland-scanner not found" >&2; exit 1; }
      cp "$SCANNER_BIN" $out/bin/wayland-scanner
      cat > $out/share/pkgconfig/wayland-scanner.pc <<EOF
prefix=$out
exec_prefix=''${prefix}
bindir=''${exec_prefix}/bin
wayland_scanner=''${bindir}/wayland-scanner
Name: Wayland Scanner
Description: Wayland protocol scanner (host build)
Version: 1.25.0
EOF
    '';
  };

  platformInfo = import "${toolchainSrc}/dependencies/toolchains/apple-mobile-platform.nix";
  mobile =
    if macos then {
      isTVOS = false;
      isVisionOS = false;
      isWatchOS = false;
      minVersion = "12.0";
      mesonSubsystem = "macos";
    } else platformInfo { inherit iosToolchain simulator; };
  isTVOS = mobile.isTVOS;
  isVisionOS = mobile.isVisionOS;
  isWatchOS = mobile.isWatchOS;
  mobileMinVersion = mobile.minVersion;
  targetCpu = if stdenv.hostPlatform.isAarch64 then "aarch64" else "x86_64";
in
stdenv.mkDerivation rec {
  pname = if macos then "weston-compositor-macos" else "weston-compositor-apple-mobile";
  version = "13.0.0";
  __noChroot = true;

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };
  patches = [
    ./patches/0001-constraints-mark-reused-buffer-busy.patch
    ./patches/0002-wayland-backend-nested-xdg-size.patch
  ];

  wayland_cursor_h = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.23.1/cursor/wayland-cursor.h";
    sha256 = "sha256-DZ22b6sk+QbnKzZAEyug2QymprjDnnvyuc/cJcwV3zg=";
  };
  wayland_xcursor_h = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.23.1/cursor/xcursor.h";
    sha256 = "sha256-l4vxxyzBImXkMIywX6/aalUU5lWAWs/i85/z+NCv+Jc=";
  };
  wayland_egl_h = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.23.1/egl/wayland-egl.h";
    sha256 = "sha256-4zviqopwClCNF1EGwS6lcT+vHJ2fGJ1vivlRhJpQSr0=";
  };
  wayland_egl_core_h = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.23.1/egl/wayland-egl-core.h";
    sha256 = "sha256-B81UDjJ6AoBm2h3HncJRJmQVCYV6RHhWBHFUDPGzXEI=";
  };

  linuxHeadersRef = "45dcf5e28813954da4150e7260ccb61e95856176";
  drmHeadersRef = "8de45ef60d69472a0f8ba898f91250dac88bb81f";

  linux_input_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input.h";
    sha256 = "sha256-ciO4IN6ANMgnw/yBe2dApcUcqDMkgLhtagwUJzD7I54=";
  };
  linux_input_event_codes_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-CqF1r2sCoJbn3Bcr0x6B1JnrqQg3d1FejCCqkVq3new=";
  };
  libdrm_fourcc_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/include/drm/drm_fourcc.h";
    sha256 = "sha256-qFbvL2tD6PeyaHFZThkYZMVAoDcg1xwT7opFDSarxi0=";
  };
  libdrm_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/include/drm/drm.h";
    sha256 = "sha256-+erb+g+eGurMJ/XJMco717RpdNutgXzQL+YBzLXN8I0=";
  };
  libdrm_mode_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/include/drm/drm_mode.h";
    sha256 = "sha256-7kBowCbftshcZoy05B/5y/MOmcEMXn7yrRx4cNP5o78=";
  };
  libdrm_xf86drm_mode_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/xf86drmMode.h";
    sha256 = "sha256-ltfaSCm9QfQaPiYBHHz5pjpZfWZAfzNIqpuyvTcS4uI=";
  };
  libdrm_xf86drm_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/xf86drm.h";
    sha256 = "sha256-X62GrL3cw7amhWkNoMfeWUEtNU0TdWRHNGcvXGvfQgI=";
  };

  nativeBuildInputs = [
    waylandScanner
    buildPackages.wayland-protocols
    buildPackages.meson
    buildPackages.ninja
    buildPackages.pkg-config
    buildPackages.python3
    buildPackages.bison
    buildPackages.flex
  ];

  buildInputs = [ ];

  mesonFlags =
    [
      "-Dbackend-headless=true"
      "-Dbackend-rdp=false"
      "-Dbackend-vnc=false"
      "-Dbackend-pipewire=false"
      "-Dbackend-x11=false"
      "-Dxwayland=false"
      "-Dimage-jpeg=false"
      "-Dimage-webp=false"
      "-Ddemo-clients=false"
      "-Dsimple-clients=[]"
      "-Dtest-junit-xml=false"
      "-Ddoc=false"
      "-Dpipewire=false"
      "-Dsystemd=false"
      "-Dcolor-management-lcms=false"
      "-Dshell-desktop=true"
      "-Dshell-fullscreen=false"
      "-Dshell-ivi=false"
      "-Dshell-kiosk=false"
      "-Dremoting=false"
      "-Dscreenshare=false"
    ]
    ++ (
      if enableIlandDrm then
        [
          "-Dbackend-drm=true"
          "-Dbackend-wayland=true"
          "-Dbackend-default=wayland"
          "-Drenderer-gl=true"
          "-Dbackend-drm-screencast-vaapi=false"
        ]
      else
        [
          "-Dbackend-drm=false"
          "-Dbackend-wayland=true"
          "-Dbackend-default=wayland"
          "-Drenderer-gl=false"
        ]
    );

  postPatch = ''
    cp ${./mobile-weston-client-launch.c} compositor/mobile-weston-client-launch.c
    cp ${./wwn-mobile-clients.h} include/wwn-mobile-clients.h
    # Route the compositor's weston_log() to the app log before wet_main runs
    # (constructor installs the handler ahead of backend dlopen), so nested
    # weston's early startup ("Loading module …", GL init, backend selection)
    # is diagnosable in the iOS app log the CI harness scans.
    cp ${./wwn-weston-log.c} compositor/wwn-weston-log.c

    # Skip tests and client demos (compositor-only static archive)
    sed -i "/subdir('tests')/d" meson.build
    sed -i "/subdir('clients')/d" meson.build

    # Static in-process modules (no dlopen on iOS)
    sed -i 's/shared_library(/static_library(/g' libweston/backend-wayland/meson.build
    sed -i 's/shared_library(/static_library(/g' libweston/backend-headless/meson.build
    sed -i 's/shared_library(/static_library(/g' desktop-shell/meson.build
    ${lib.optionalString enableIlandDrm ''
    sed -i 's/shared_library(/static_library(/g' libweston/backend-drm/meson.build
    sed -i 's/shared_library(/static_library(/g' libweston/renderer-gl/meson.build
    sed -i 's/^weston_backend_init(/wwn_weston_drm_backend_init(/' libweston/backend-drm/drm.c
    sed -i 's/^weston_module_init(/wwn_gl_renderer_module_init(/' libweston/renderer-gl/gl-renderer.c
    # Global client open() redirect must not rewrite launcher interface member
    # calls (`iface->open(...)`). The launcher implementation remains redirected.
    sed -i '1i#undef open' libweston/launcher-util.c
    ''}
    sed -i "/subdir('wcap')/d" meson.build
    sed -i "/^exe_weston = executable(/,/^)/d" compositor/meson.build

    python3 - <<'PY'
from pathlib import Path
import re

def staticify_lib(path: Path, name: str) -> None:
    text = path.read_text()
    if f"{name} = shared_library(" not in text:
        if f"{name} = static_library(" in text:
            return
        raise SystemExit(f"{name} shared_library anchor not found in {path}")
    text = text.replace(f"{name} = shared_library(", f"{name} = static_library(", 1)
    # Remove kwargs invalid for static_library within this target block only.
    block_re = re.compile(
        rf"{re.escape(name)} = static_library\((.*?)\n\)",
        re.DOTALL,
    )
    m = block_re.search(text)
    if not m:
        raise SystemExit(f"{name} static_library block not found in {path}")
    block = m.group(1)
    block = re.sub(r"^\s*version:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*soversion:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*install_dir:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*install_rpath:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*name_prefix:.*\n", "", block, flags=re.MULTILINE)
    block = block.replace("install: true", "install: false")
    text = text[: m.start(1)] + block + text[m.end(1) :]
    path.write_text(text)

staticify_lib(Path("libweston/meson.build"), "lib_weston")
PY

    python3 - <<'PY'
from pathlib import Path
path = Path("compositor/meson.build")
text = path.read_text()
old = """libexec_weston = shared_library(
	'exec_weston',
	sources: srcs_weston,
	include_directories: common_inc,
	dependencies: deps_weston,
	install_dir: dir_module_weston,
	install: true,
	version: '0.0.0',
	soversion: 0
)"""
new = """libexec_weston = static_library(
	'exec_weston',
	sources: srcs_weston,
	include_directories: common_inc,
	dependencies: deps_weston,
	install: false
)"""
if old not in text:
    raise SystemExit("libexec_weston block not found")
path.write_text(text.replace(old, new, 1))
PY

    # Unique backend entry symbols (avoid duplicate weston_backend_init when linked)
    sed -i 's/^weston_backend_init(/wwn_weston_wayland_backend_init(/' libweston/backend-wayland/wayland.c
    sed -i 's/^weston_backend_init(/wwn_weston_headless_backend_init(/' libweston/backend-headless/headless.c
    sed -i 's/^wet_shell_init(/wwn_wet_desktop_shell_init(/' desktop-shell/shell.c

    # In-process host: wayland_destroy must not cairo_debug_reset_static_data.
    # Sibling terminals / pango still hold scaled fonts (SIGABRT in
    # _cairo_hash_table_destroy). Same rationale as toytoolkit wwn #96.
    python3 ${./terminal-patches/patch-cairo-util-inprocess.py}

    python3 - <<'PY'
from pathlib import Path

path = Path("libweston/backend-wayland/wayland.c")
text = path.read_text()
marker = "static int\nwayland_backend_create_output_surface"
helper = """
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
static int
wwn_parent_output_scale(void)
{
\tconst char *env = getenv("WAWONA_OUTPUT_SCALE");
\tint scale = env ? atoi(env) : 1;

\tif (scale < 1)
\t\tscale = 1;
\treturn scale;
}
#endif

"""
if "wwn_parent_output_scale" not in text:
    if marker not in text:
        raise SystemExit("wayland_backend_create_output_surface anchor missing")
    text = text.replace(marker, helper + marker, 1)

surface_hook = "\twl_surface_set_user_data(output->parent.surface, output);\n\n\toutput->parent.draw_initial_frame = true;"
surface_patch = """\twl_surface_set_user_data(output->parent.surface, output);

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
\t{
\t\tint scale = wwn_parent_output_scale();

\t\tif (scale > 1)
\t\t\twl_surface_set_buffer_scale(output->parent.surface, scale);
\t}
#endif

\toutput->parent.draw_initial_frame = true;"""
if surface_patch not in text:
    if surface_hook not in text:
        raise SystemExit("wl_surface_set_user_data hook missing in wayland.c")
    text = text.replace(surface_hook, surface_patch, 1)

path.write_text(text)
PY

    # Soft-fail nested wayland+pixman when output SHM allocation fails, and
    # skip paint nodes whose SHM backing vanished mid-repaint (client exit /
    # pool recycle races under in-process pthread vs GCD).
    python3 - <<'PY'
from pathlib import Path

wl = Path("libweston/backend-wayland/wayland.c")
text = wl.read_text()
old = """\tsb = wayland_output_get_shm_buffer(output);

\twayland_output_update_shm_border(sb);
\tb->compositor->renderer->repaint_output(output_base, damage,
\t\t\t\t\t\tsb->renderbuffer);

\twayland_shm_buffer_attach(sb, damage);"""
new = """\tsb = wayland_output_get_shm_buffer(output);
\tif (!sb || !sb->renderbuffer) {
\t\tweston_log("wayland-backend: no SHM renderbuffer for pixman repaint; skipping frame\\n");
\t\treturn -1;
\t}

\twayland_output_update_shm_border(sb);
\tb->compositor->renderer->repaint_output(output_base, damage,
\t\t\t\t\t\tsb->renderbuffer);

\twayland_shm_buffer_attach(sb, damage);"""
if "no SHM renderbuffer for pixman repaint" not in text:
    if old not in text:
        raise SystemExit("wayland_output_repaint_pixman SHM anchor missing")
    text = text.replace(old, new, 1)
    wl.write_text(text)

pr = Path("libweston/pixman-renderer.c")
text = pr.read_text()
old = """\t/* No buffer attached */
\tif (!ps->image)
\t\treturn;

\t/* if we still have a reference, but the underlying buffer is no longer
\t * available signal that we should unref image_t as well. This happens
\t * when using close animations, with the reference surviving the
\t * animation while the underlying buffer went away as the client was
\t * terminated. This is a particular use-case and should probably be
\t * refactored to provide some analogue with the GL-renderer (as in, to
\t * still maintain the buffer and let the compositor dispose of it). */
\tif (ps->buffer_ref.buffer && !ps->buffer_ref.buffer->shm_buffer) {
\t\tpixman_image_unref(ps->image);
\t\tps->image = NULL;
\t\treturn;
\t}"""
new = """\t/* No buffer attached */
\tif (!ps->image)
\t\treturn;

\t/* if we still have a reference, but the underlying buffer is no longer
\t * available signal that we should unref image_t as well. This happens
\t * when using close animations, with the reference surviving the
\t * animation while the underlying buffer went away as the client was
\t * terminated. This is a particular use-case and should probably be
\t * refactored to provide some analogue with the GL-renderer (as in, to
\t * still maintain the buffer and let the compositor dispose of it). */
\tif (ps->buffer_ref.buffer && !ps->buffer_ref.buffer->shm_buffer) {
\t\tpixman_image_unref(ps->image);
\t\tps->image = NULL;
\t\treturn;
\t}

\t/* In-process Apple mobile: client pthread can recycle SHM pools while
\t * nested weston still paints. Drop stale images that lost their bits. */
\tif (!pixman_image_get_data(ps->image)) {
\t\tpixman_image_unref(ps->image);
\t\tps->image = NULL;
\t\treturn;
\t}"""
if "pixman_image_get_data(ps->image)" not in text:
    if old not in text:
        raise SystemExit("pixman draw_paint_node buffer guard anchor missing")
    text = text.replace(old, new, 1)
    pr.write_text(text)
PY

    touch include/empty.c
    mkdir -p include
    sed -i "s/'libinput-device.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.h'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-device.h'/'..\/include\/empty.c'/g" libweston/meson.build

    sed -i "s|message('The default backend is ' + backend_default)|message('Skipping backend validation for mobile compositor build')|g" meson.build
    sed -i "s/dependency('libinput'/dependency('libinput', required: false/g" meson.build
    sed -i "s/dependency('libevdev'/dependency('libevdev', required: false/g" meson.build
    sed -i "s/dependency('libdrm'/dependency('libdrm', required: false/g" meson.build
    ${lib.optionalString enableIlandDrm ''
    sed -i "s/'launcher-libseat.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/dependency('libseat'/dependency('libseat', required: false/g" libweston/meson.build
    sed -i "s/dependency('gbm'/dependency('gbm', required: true/g" libweston/meson.build
    sed -i "s/dependency('egl'/dependency('egl', required: true/g" libweston/meson.build
    sed -i "s/dependency('glesv2'/dependency('glesv2', required: true/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" libweston/backend-drm/meson.build
    sed -i "s/dependency('libinput'/dependency('libinput', required: false/g" libweston/backend-drm/meson.build
    sed -i "s/dependency('libseat'/dependency('libseat', required: false/g" libweston/backend-drm/meson.build
    sed -i "s/dependency('libdisplay-info'/dependency('libdisplay-info', required: false/g" libweston/backend-drm/meson.build
    mkdir -p include/libseat
    cat > include/libseat/libseat.h <<'EOF'
#ifndef _LIBSEAT_H
#define _LIBSEAT_H
#include <stdarg.h>
struct libseat;
struct libseat_device;
enum libseat_log_level { LIBSEAT_LOG_LEVEL_NONE=0, LIBSEAT_LOG_LEVEL_INFO=1 };
struct libseat_seat_listener {
	void (*enable_seat)(struct libseat *, void *);
	void (*disable_seat)(struct libseat *, void *);
};
struct libseat *libseat_open_seat(const struct libseat_seat_listener *, void *);
void libseat_close_seat(struct libseat *);
int libseat_get_fd(struct libseat *);
int libseat_dispatch(struct libseat *, int);
int libseat_disable_seat(struct libseat *);
typedef void (*libseat_log_handler)(enum libseat_log_level, const char *, va_list);
void libseat_set_log_handler(libseat_log_handler);
#endif
EOF
    ''}
    sed -i "s/cc.find_library('pam'/cc.find_library('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('pam'/dependency('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" clients/meson.build
    sed -i "s/error(/warning(/g" clients/meson.build
    sed -i "s/dependency('libevdev'/dependency('libevdev', required: false/g" clients/meson.build
    sed -i "s/dependency('gbm'/dependency('gbm', required: false/g" clients/meson.build
    sed -i "s/dependency('libdrm'/dependency('libdrm', required: false/g" clients/meson.build
    sed -i "s/dependency('libinput'/dependency('libinput', required: false/g" clients/meson.build
    sed -i "s/dep_libinput,//" compositor/meson.build
    sed -i "s/dep_libevdev,//" compositor/meson.build

    # Replace libinput backend with empty stub (no Linux input stack on Apple mobile)
    python3 - <<'PY'
from pathlib import Path
path = Path("libweston/meson.build")
text = path.read_text()
start = "lib_libinput_backend = static_library("
end = "dep_libinput_backend = declare_dependency("
si = text.find(start)
ei = text.find(end)
if si < 0 or ei < 0:
    raise SystemExit("libinput backend block not found")
# Include the full dep_libinput_backend declare_dependency(...) block.
close = text.find(")\n\ndep_vertex_clipping", ei)
if close < 0:
    raise SystemExit("libinput backend end anchor not found")
close += 2  # keep trailing newline before dep_vertex_clipping
stub = """lib_libinput_backend = static_library(
	'libinput-backend',
	'../include/empty.c',
	include_directories: common_inc,
	install: false
)
dep_libinput_backend = declare_dependency(
	link_with: lib_libinput_backend,
	include_directories: include_directories('.')
)

"""
path.write_text(text[:si] + stub + text[close:])
PY

    # Stub pkg-config for Linux-only deps (headers only; no runtime dlopen)
    cat > include/wwn-static-modules.h <<'EOF'
#ifndef WWN_STATIC_MODULES_H
#define WWN_STATIC_MODULES_H
#include <stddef.h>
#include <string.h>
struct weston_compositor;
struct weston_backend_config;
extern int wwn_weston_wayland_backend_init(struct weston_compositor *c, struct weston_backend_config *cfg);
extern int wwn_weston_headless_backend_init(struct weston_compositor *c, struct weston_backend_config *cfg);
extern int wwn_wet_desktop_shell_init(struct weston_compositor *ec, int *argc, char **argv);
extern volatile int wwn_weston_compositor_shutdown_requested;
${lib.optionalString enableIlandDrm ''
extern int wwn_weston_drm_backend_init(struct weston_compositor *c, struct weston_backend_config *cfg);
extern int wwn_gl_renderer_module_init(struct weston_compositor *ec);
''}
static inline void *wwn_static_module_lookup(const char *name, const char *entrypoint) {
	if (!name || !entrypoint)
		return NULL;
	if (strcmp(entrypoint, "weston_backend_init") == 0) {
		if (strstr(name, "wayland-backend") != NULL)
			return (void *)wwn_weston_wayland_backend_init;
		if (strstr(name, "headless-backend") != NULL)
			return (void *)wwn_weston_headless_backend_init;
${lib.optionalString enableIlandDrm ''
		if (strstr(name, "drm-backend") != NULL)
			return (void *)wwn_weston_drm_backend_init;
''}
	}
	if (strcmp(entrypoint, "wet_shell_init") == 0 && strstr(name, "desktop-shell") != NULL)
		return (void *)wwn_wet_desktop_shell_init;
${lib.optionalString enableIlandDrm ''
	if (strcmp(entrypoint, "weston_module_init") == 0 && strstr(name, "gl-renderer") != NULL)
		return (void *)wwn_gl_renderer_module_init;
''}
	return NULL;
}
#endif
EOF

    python3 - <<'PY'
from pathlib import Path

compositor = Path("libweston/compositor.c").read_text()
needle = '#include "backend.h"'
insert = needle + '\n#include "include/wwn-static-modules.h"'
if needle not in compositor:
    raise SystemExit("compositor.c include anchor missing")
compositor = compositor.replace(needle, insert, 1)
old = "\tmodule = dlopen(path, RTLD_NOW | RTLD_NOLOAD);"
new = """\t{
\t\tvoid *static_init = wwn_static_module_lookup(name, entrypoint);
\t\tif (!static_init && path)
\t\t\tstatic_init = wwn_static_module_lookup(path, entrypoint);
\t\tif (static_init)
\t\t\treturn static_init;
\t}
\tmodule = dlopen(path, RTLD_NOW | RTLD_NOLOAD);"""
if old not in compositor:
    raise SystemExit("weston_load_module dlopen anchor missing")
compositor = compositor.replace(old, new, 1)
Path("libweston/compositor.c").write_text(compositor)

main = Path("compositor/main.c").read_text()
main = main.replace(
    "\twl_display_run(display);",
    """\twhile (!wwn_weston_compositor_shutdown_requested) {
\t\tint timeout_ms = 100;
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
\t\tif (wwn_mobile_pending_roundtrips() > 0 ||
\t\t    wwn_mobile_active_clients() > 0) {
\t\t\twl_display_flush_clients(display);
\t\t\ttimeout_ms = 1;
\t\t}
#endif
\t\tif (wl_event_loop_dispatch(loop, timeout_ms) < 0)
\t\t\tbreak;
\t}""",
    1,
)
if "wwn-static-modules.h" not in main:
    main = main.replace(
        '#include "weston-private.h"',
        '#include "weston-private.h"\n#include "include/wwn-static-modules.h"\n#include "include/wwn-mobile-clients.h"',
        1,
    )
forward_decl = """
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
struct wet_process *
wwn_wet_client_launch_inprocess(struct weston_compositor *compositor,
				char *const *argp,
				char *const *envp,
				int *no_cloexec_fds,
				size_t num_no_cloexec_fds,
				wet_process_cleanup_func_t cleanup,
				void *cleanup_data);
#endif
"""
wet_launch_anchor = "struct wet_process *\nwet_client_launch(struct weston_compositor *compositor,"
if "wwn_wet_client_launch_inprocess" not in main:
    if wet_launch_anchor not in main:
        raise SystemExit("wet_client_launch definition anchor missing")
    main = main.replace(
        wet_launch_anchor,
        forward_decl + "\n" + wet_launch_anchor,
        1,
    )
inprocess_hook = """
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
	{
		proc = wwn_wet_client_launch_inprocess(compositor, argp, envp,
					no_cloexec_fds, num_no_cloexec_fds,
					cleanup, cleanup_data);
		if (proc) {
			wl_list_insert(&wet->child_process_list, &proc->link);
			custom_env_fini(child_env);
			free(fail_exec);
			return proc;
		}
	}
#endif
"""
fork_anchor = "\tstr_printf(&fail_exec, \"Error: Couldn't launch client '%s'\\n\", argp[0]);\n\n\tpid = fork();"
if fork_anchor not in main:
    raise SystemExit("wet_client_launch fork anchor missing")
if inprocess_hook.strip() not in main:
    main = main.replace(
        fork_anchor,
        "\tstr_printf(&fail_exec, \"Error: Couldn't launch client '%s'\\n\", argp[0]);\n"
        + inprocess_hook
        + "\n\tpid = fork();",
        1,
    )
wet_start_old = """\tproc = wet_client_launch(compositor, &child_env,
\t\t\t\t no_cloexec_fds, num_no_cloexec_fds,
\t\t\t\t NULL, NULL);
\tif (!proc)
\t\treturn NULL;

\tclient = wl_client_create(compositor->wl_display,
\t\t\t\t  wayland_socket.fds[0]);
\tif (!client) {
\t\tweston_log("wet_client_start: "
\t\t\t   "wl_client_create failed while launching '%s'.\\n",
\t\t\t   path);
\t\t/* We have no way of killing the process, so leave it hanging */
\t\tgoto out_sock;
\t}

\t/* Close the child end of our socket which we no longer need */
\tclose(wayland_socket.fds[1]);

\t/* proc is now owned by the compositor's process list */

\treturn client;

out_sock:
\tfdstr_close_all(&wayland_socket);

\treturn NULL;"""
wet_start_new = """\t/*
\t * Create the wl_client before starting the in-process client thread.
\t * Otherwise the client may connect and bind globals before the server
\t * associates the socket with a wl_client (fork naturally delays this).
\t */
\tclient = wl_client_create(compositor->wl_display,
\t\t\t\t  wayland_socket.fds[0]);
\tif (!client) {
\t\tweston_log("wet_client_start: "
\t\t\t   "wl_client_create failed while launching '%s'.\\n",
\t\t\t   path);
\t\tgoto out_sock;
\t}

\tproc = wet_client_launch(compositor, &child_env,
\t\t\t\t no_cloexec_fds, num_no_cloexec_fds,
\t\t\t\t NULL, NULL);
\tif (!proc) {
\t\tweston_log("wet_client_start: "
\t\t\t   "failed to launch '%s'.\\n", path);
\t\tgoto out_client;
\t}

\t/* Close the child end of our socket which we no longer need */
\tclose(wayland_socket.fds[1]);

\t/* proc is now owned by the compositor's process list */

\treturn client;

out_client:
\twl_client_destroy(client);

out_sock:
\tfdstr_close_all(&wayland_socket);

\treturn NULL;"""
if wet_start_old not in main:
    raise SystemExit("wet_client_start reorder anchor missing")
if "Create the wl_client before starting the in-process client thread" not in main:
    main = main.replace(wet_start_old, wet_start_new, 1)
compositor_ok = "\tif (wet.compositor == NULL) {\n\t\tweston_log(\"fatal: failed to create compositor\\n\");\n\t\tgoto out;\n\t}"
compositor_ok_reg = compositor_ok + "\n\n#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH\n\twwn_mobile_register_compositor_display(display);\n#endif"
if "wwn_mobile_register_compositor_display(display)" not in main:
    if compositor_ok not in main:
        raise SystemExit("weston_compositor_create success anchor missing")
    main = main.replace(compositor_ok, compositor_ok_reg, 1)
destroy_anchor = "\tweston_compositor_destroy(wet.compositor);"
destroy_reg = "#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH\n\twwn_mobile_register_compositor_display(NULL);\n#endif\n" + destroy_anchor
if "wwn_mobile_register_compositor_display(NULL)" not in main:
    if destroy_anchor not in main:
        raise SystemExit("weston_compositor_destroy anchor missing")
    main = main.replace(destroy_anchor, destroy_reg, 1)
Path("compositor/main.c").write_text(main)
PY

    # -fvisibility=hidden is on for the weston static archive. Entry points the
    # host resolves via weak_import (WWNWaypipeRunner) must be default-visible
    # or they become non-external in the final iOS binary and resolve to NULL
    # at runtime — Start looks like a no-op ("weston_compositor_main not linked").
    cat > compositor/wwn-weston-compositor-main.c <<'EOF'
#include "config.h"
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include "weston.h"

#if defined(__GNUC__) || defined(__clang__)
#define WWN_EXPORT __attribute__((visibility("default")))
#else
#define WWN_EXPORT
#endif

WWN_EXPORT volatile sig_atomic_t wwn_weston_compositor_shutdown_requested = 0;

static atomic_int wwn_weston_main_active;

WWN_EXPORT int wwn_weston_compositor_is_running(void)
{
	return atomic_load(&wwn_weston_main_active);
}

WWN_EXPORT int weston_compositor_main(int argc, char **argv)
{
	int rc;

	if (atomic_exchange(&wwn_weston_main_active, 1)) {
		fprintf(stderr,
			"weston is already this process's compositor and "
			"cannot nest inside itself.\n"
			"On iOS there is no second weston process. "
			"Start niri here to nest another compositor.\n");
		return 1;
	}
	wwn_weston_compositor_shutdown_requested = 0;
	rc = wet_main(argc, argv, NULL);
	atomic_store(&wwn_weston_main_active, 0);
	return rc;
}
EOF

    # Weston 13 GL renderer exports gl_renderer_interface (not weston_module_init),
    # but wwn-static-modules.h still takes the address of wwn_gl_renderer_module_init.
    # libinput-seat / launcher-libseat are replaced with empty.c on Apple builds, yet
    # the DRM backend still references udev_input_* and launcher_libseat_iface.
    cat > compositor/wwn-drm-link-stubs.c <<'EOF'
#include "config.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <time.h>
#include <libweston/libweston.h>
#include "../libweston/libweston-internal.h"
#include "../libweston/backend.h"
#include "../libweston/libinput-seat.h"
#include "../libweston/launcher-impl.h"

#if defined(__GNUC__) || defined(__clang__)
#define WWN_EXPORT __attribute__((visibility("default")))
#else
#define WWN_EXPORT
#endif

#ifndef BTN_LEFT
#define BTN_LEFT 0x110
#endif

enum wwn_inj_kind {
	WWN_INJ_TOUCH = 1,
	WWN_INJ_POINTER = 2,
	WWN_INJ_AXIS = 3,
	WWN_INJ_CANCEL = 4,
};

struct wwn_inj {
	uint8_t kind;
	int8_t state;
	int32_t id;
	double x;
	double y;
	double axis_value;
	int axis;
};

#define WWN_INJ_CAP 64
#define WWN_SLOT_CAP 16

static struct weston_compositor *g_wwn_ec;
static struct weston_seat *g_wwn_seat;
static struct weston_touch_device *g_wwn_touch_dev;
static struct wl_event_source *g_wwn_inject_source;
static int g_wwn_inject_pipe[2] = { -1, -1 };
static pthread_mutex_t g_wwn_inj_lock = PTHREAD_MUTEX_INITIALIZER;
static struct wwn_inj g_wwn_inj_q[WWN_INJ_CAP];
static unsigned g_wwn_inj_head;
static unsigned g_wwn_inj_tail;
static int32_t g_wwn_slots[WWN_SLOT_CAP];
static uint8_t g_wwn_slot_used[WWN_SLOT_CAP];
static int g_wwn_input_ready;
static int g_wwn_pointer_down;

static void
wwn_now(struct timespec *ts)
{
	if (clock_gettime(CLOCK_MONOTONIC, ts) != 0)
		memset(ts, 0, sizeof(*ts));
}

static struct weston_coord_global
wwn_pos(double x, double y)
{
	struct weston_coord_global pos;

	pos.c.x = x;
	pos.c.y = y;
	return pos;
}

static int
wwn_slot_of(int32_t id, int alloc)
{
	int i;

	for (i = 0; i < WWN_SLOT_CAP; i++) {
		if (g_wwn_slot_used[i] && g_wwn_slots[i] == id)
			return i;
	}
	if (!alloc)
		return -1;
	for (i = 0; i < WWN_SLOT_CAP; i++) {
		if (!g_wwn_slot_used[i]) {
			g_wwn_slot_used[i] = 1;
			g_wwn_slots[i] = id;
			return i;
		}
	}
	return 0;
}

static void
wwn_slot_clear(int32_t id)
{
	int i;

	for (i = 0; i < WWN_SLOT_CAP; i++) {
		if (g_wwn_slot_used[i] && g_wwn_slots[i] == id) {
			g_wwn_slot_used[i] = 0;
			g_wwn_slots[i] = 0;
			return;
		}
	}
}

static void
wwn_enqueue(struct wwn_inj ev)
{
	unsigned next;
	char wake = 1;

	if (!g_wwn_input_ready || g_wwn_inject_pipe[1] < 0)
		return;
	pthread_mutex_lock(&g_wwn_inj_lock);
	next = (g_wwn_inj_head + 1u) % WWN_INJ_CAP;
	if (next != g_wwn_inj_tail) {
		g_wwn_inj_q[g_wwn_inj_head] = ev;
		g_wwn_inj_head = next;
	}
	pthread_mutex_unlock(&g_wwn_inj_lock);
	(void)write(g_wwn_inject_pipe[1], &wake, 1);
}

static void
wwn_dispatch_one(const struct wwn_inj *ev)
{
	struct timespec ts;
	struct weston_coord_global pos;
	int slot;
	int type;

	if (!g_wwn_seat)
		return;
	wwn_now(&ts);
	pos = wwn_pos(ev->x, ev->y);
	switch (ev->kind) {
	case WWN_INJ_TOUCH:
		if (!g_wwn_touch_dev)
			break;
		if (ev->state == 0) {
			slot = wwn_slot_of(ev->id, 0);
			type = WL_TOUCH_UP;
		} else if (ev->state == 1) {
			slot = wwn_slot_of(ev->id, 1);
			type = WL_TOUCH_DOWN;
		} else {
			slot = wwn_slot_of(ev->id, 0);
			type = WL_TOUCH_MOTION;
		}
		if (slot < 0)
			break;
		notify_touch(g_wwn_touch_dev, &ts, slot, &pos, type);
		notify_touch_frame(g_wwn_touch_dev);
		if (ev->state == 0)
			wwn_slot_clear(ev->id);
		break;
	case WWN_INJ_POINTER:
		notify_motion_absolute(g_wwn_seat, &ts, pos);
		if (ev->state == 1 && !g_wwn_pointer_down) {
			notify_button(g_wwn_seat, &ts, BTN_LEFT,
				      WL_POINTER_BUTTON_STATE_PRESSED);
			g_wwn_pointer_down = 1;
		} else if (ev->state == 0 && g_wwn_pointer_down) {
			notify_button(g_wwn_seat, &ts, BTN_LEFT,
				      WL_POINTER_BUTTON_STATE_RELEASED);
			g_wwn_pointer_down = 0;
		}
		notify_pointer_frame(g_wwn_seat);
		break;
	case WWN_INJ_AXIS: {
		struct weston_pointer_axis_event axis = {
			.axis = (uint32_t)ev->axis,
			.value = ev->axis_value,
			.has_discrete = false,
			.discrete = 0,
		};
		notify_axis(g_wwn_seat, &ts, &axis);
		notify_pointer_frame(g_wwn_seat);
		break;
	}
	case WWN_INJ_CANCEL:
		if (g_wwn_touch_dev)
			notify_touch_cancel(g_wwn_touch_dev);
		if (g_wwn_pointer_down) {
			notify_button(g_wwn_seat, &ts, BTN_LEFT,
				      WL_POINTER_BUTTON_STATE_RELEASED);
			g_wwn_pointer_down = 0;
			notify_pointer_frame(g_wwn_seat);
		}
		memset(g_wwn_slot_used, 0, sizeof(g_wwn_slot_used));
		break;
	default:
		break;
	}
}

static int
wwn_inject_dispatch(int fd, uint32_t mask, void *data)
{
	char buf[32];
	struct wwn_inj ev;
	int have;

	(void)mask;
	(void)data;
	while (read(fd, buf, sizeof(buf)) > 0) {
	}
	for (;;) {
		have = 0;
		pthread_mutex_lock(&g_wwn_inj_lock);
		if (g_wwn_inj_tail != g_wwn_inj_head) {
			ev = g_wwn_inj_q[g_wwn_inj_tail];
			g_wwn_inj_tail = (g_wwn_inj_tail + 1u) % WWN_INJ_CAP;
			have = 1;
		}
		pthread_mutex_unlock(&g_wwn_inj_lock);
		if (!have)
			break;
		wwn_dispatch_one(&ev);
	}
	return 0;
}

static void
wwn_input_teardown(void)
{
	g_wwn_input_ready = 0;
	if (g_wwn_inject_source) {
		wl_event_source_remove(g_wwn_inject_source);
		g_wwn_inject_source = NULL;
	}
	if (g_wwn_inject_pipe[0] >= 0) {
		close(g_wwn_inject_pipe[0]);
		g_wwn_inject_pipe[0] = -1;
	}
	if (g_wwn_inject_pipe[1] >= 0) {
		close(g_wwn_inject_pipe[1]);
		g_wwn_inject_pipe[1] = -1;
	}
	g_wwn_touch_dev = NULL;
	if (g_wwn_seat) {
		weston_seat_release(g_wwn_seat);
		free(g_wwn_seat);
		g_wwn_seat = NULL;
	}
	g_wwn_ec = NULL;
	g_wwn_pointer_down = 0;
	memset(g_wwn_slot_used, 0, sizeof(g_wwn_slot_used));
	g_wwn_inj_head = 0;
	g_wwn_inj_tail = 0;
}

WWN_EXPORT int
wwn_weston_input_ready(void)
{
	return g_wwn_input_ready;
}

WWN_EXPORT int
wwn_weston_logical_size(uint32_t *width, uint32_t *height)
{
	struct weston_output *output;

	if (width)
		*width = 0;
	if (height)
		*height = 0;
	if (!g_wwn_ec)
		return -1;
	wl_list_for_each(output, &g_wwn_ec->output_list, link) {
		if (width)
			*width = (uint32_t)output->width;
		if (height)
			*height = (uint32_t)output->height;
		return 0;
	}
	return -1;
}

WWN_EXPORT void
wwn_weston_inject_touch(int32_t id, int state, double x, double y)
{
	struct wwn_inj ev = {
		.kind = WWN_INJ_TOUCH,
		.state = (int8_t)state,
		.id = id,
		.x = x,
		.y = y,
	};
	wwn_enqueue(ev);
}

WWN_EXPORT void
wwn_weston_inject_pointer(int state, double x, double y)
{
	struct wwn_inj ev = {
		.kind = WWN_INJ_POINTER,
		.state = (int8_t)state,
		.x = x,
		.y = y,
	};
	wwn_enqueue(ev);
}

WWN_EXPORT void
wwn_weston_inject_axis(int axis, double value)
{
	struct wwn_inj ev = {
		.kind = WWN_INJ_AXIS,
		.axis = axis,
		.axis_value = value,
	};
	wwn_enqueue(ev);
}

WWN_EXPORT void
wwn_weston_inject_touch_cancel(void)
{
	struct wwn_inj ev = { .kind = WWN_INJ_CANCEL };
	wwn_enqueue(ev);
}

WWN_EXPORT int
wwn_gl_renderer_module_init(struct weston_compositor *ec)
{
	(void)ec;
	/* Real GL bring-up uses gl_renderer_interface from gl-renderer.c. */
	return -1;
}

WWN_EXPORT int
udev_input_enable(struct udev_input *input)
{
	(void)input;
	return 0;
}

WWN_EXPORT void
udev_input_disable(struct udev_input *input)
{
	(void)input;
}

WWN_EXPORT int
udev_input_init(struct udev_input *input, struct weston_compositor *c,
		struct udev *udev, const char *seat_id,
		udev_configure_device_t configure_device)
{
	struct wl_event_loop *loop;
	struct weston_touch *touch;

	(void)input;
	(void)udev;
	(void)seat_id;
	(void)configure_device;
	/* Own-display IOMFB: no libinput. Create a synthetic seat so UIKit
	 * can inject wl_touch / wl_pointer on Weston's event loop. */
	wwn_input_teardown();
	if (!c || !c->wl_display)
		return 0;
	g_wwn_seat = zalloc(sizeof(*g_wwn_seat));
	if (!g_wwn_seat)
		return 0;
	weston_seat_init(g_wwn_seat, c, "wwn-ios-touch");
	(void)weston_seat_init_pointer(g_wwn_seat);
	(void)weston_seat_init_touch(g_wwn_seat);
	touch = weston_seat_get_touch(g_wwn_seat);
	if (touch) {
		g_wwn_touch_dev = weston_touch_create_touch_device(
			touch, "wwn-ios-touchscreen", NULL, NULL);
	}
	if (pipe(g_wwn_inject_pipe) != 0) {
		weston_log("wwn-ios-touch: pipe failed (%s)\n",
			   strerror(errno));
		wwn_input_teardown();
		return 0;
	}
	fcntl(g_wwn_inject_pipe[0], F_SETFL, O_NONBLOCK);
	fcntl(g_wwn_inject_pipe[1], F_SETFL, O_NONBLOCK);
	loop = wl_display_get_event_loop(c->wl_display);
	g_wwn_inject_source = wl_event_loop_add_fd(loop, g_wwn_inject_pipe[0],
						   WL_EVENT_READABLE,
						   wwn_inject_dispatch, NULL);
	if (!g_wwn_inject_source) {
		wwn_input_teardown();
		return 0;
	}
	g_wwn_ec = c;
	g_wwn_input_ready = 1;
	weston_log("wwn-ios-touch: synthetic seat ready\n");
	return 0;
}

WWN_EXPORT void
udev_input_destroy(struct udev_input *input)
{
	(void)input;
	wwn_input_teardown();
}

WWN_EXPORT struct udev_seat *
udev_seat_get_named(struct udev_input *u, const char *seat_name)
{
	(void)u;
	(void)seat_name;
	return NULL;
}

/* No seatd/logind on iOS. Succeed as a launcher and open DRM nodes with
 * plain open(); iland_drm_open_compat.h routes /dev/dri/cardN. */
struct wwn_launcher {
	struct weston_launcher base;
	struct weston_compositor *compositor;
};

static int
wwn_libseat_connect(struct weston_launcher **launcher_out,
		    struct weston_compositor *compositor, const char *seat_id,
		    bool sync_drm)
{
	struct wwn_launcher *wl;

	(void)seat_id;
	(void)sync_drm;
	wl = calloc(1, sizeof(*wl));
	if (!wl)
		return -1;
	wl->base.iface = &launcher_libseat_iface;
	wl->compositor = compositor;
	compositor->session_active = true;
	wl_signal_emit(&compositor->session_signal, compositor);
	*launcher_out = &wl->base;
	weston_log("wwn-launcher: iOS own-display stub seat (no seatd/logind)\n");
	return 0;
}

static void
wwn_libseat_destroy(struct weston_launcher *launcher)
{
	struct wwn_launcher *wl = wl_container_of(launcher, wl, base);
	free(wl);
}

static int
wwn_libseat_open(struct weston_launcher *launcher, const char *path, int flags)
{
	int fd;

	(void)launcher;
	fd = open(path, flags | O_CLOEXEC);
	if (fd < 0)
		return -1;
	return fd;
}

static void
wwn_libseat_close(struct weston_launcher *launcher, int fd)
{
	(void)launcher;
	close(fd);
}

static int
wwn_libseat_activate_vt(struct weston_launcher *launcher, int vt)
{
	(void)launcher;
	(void)vt;
	return 0;
}

static int
wwn_libseat_get_vt(struct weston_launcher *launcher)
{
	(void)launcher;
	return -ENOSYS;
}

WWN_EXPORT const struct launcher_interface launcher_libseat_iface = {
	.name = "libseat",
	.connect = wwn_libseat_connect,
	.destroy = wwn_libseat_destroy,
	.open = wwn_libseat_open,
	.close = wwn_libseat_close,
	.activate_vt = wwn_libseat_activate_vt,
	.get_vt = wwn_libseat_get_vt,
};
EOF
    python3 - <<'PY'
from pathlib import Path
path = Path("compositor/meson.build")
text = path.read_text()
needle = "\t'main.c',"
insert = needle + "\n\t'wwn-weston-compositor-main.c',"
if needle not in text:
    raise SystemExit("main.c entry not found in compositor/meson.build")
if "wwn-weston-compositor-main.c" not in text:
    text = text.replace(needle, insert, 1)
needle2 = "\t'wwn-weston-compositor-main.c',"
insert2 = needle2 + "\n\t'mobile-weston-client-launch.c',"
if needle2 not in text:
    raise SystemExit("wwn-weston-compositor-main.c entry not found")
if "mobile-weston-client-launch.c" not in text:
    text = text.replace(needle2, insert2, 1)
needle3 = "\t'mobile-weston-client-launch.c',"
insert3 = needle3 + "\n\t'wwn-weston-log.c',"
if needle3 not in text:
    raise SystemExit("mobile-weston-client-launch.c entry not found")
if "wwn-weston-log.c" not in text:
    text = text.replace(needle3, insert3, 1)
needle4 = "\t'wwn-weston-log.c',"
insert4 = needle4 + "\n\t'wwn-drm-link-stubs.c',"
if needle4 not in text:
    raise SystemExit("wwn-weston-log.c entry not found")
if "wwn-drm-link-stubs.c" not in text:
    text = text.replace(needle4, insert4, 1)
path.write_text(text)
PY

    # Apple shims (mirror macos.nix)
    mkdir -p include/sys include/libudev include/libinput include/libevdev include/linux include/GLES2 include/EGL include/KHR

    cat > include/weston-macos-polyfills.h <<'EOF'
#ifndef WESTON_MACOS_POLYFILLS_H
#define WESTON_MACOS_POLYFILLS_H
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <libgen.h>
#ifdef __APPLE__
#include <TargetConditionals.h>
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};
#define WESTON_HOWMANY(x, y) (((int)(x) + (int)(y) - 1) / (int)(y))
#define SOCK_CLOEXEC 0
#define SOCK_NONBLOCK 0
static inline int pipe2(int fds[2], int flags) {
    if (pipe(fds) != 0) return -1;
    if (flags & O_CLOEXEC) {
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    }
    if (flags & O_NONBLOCK) {
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);
    }
    return 0;
}
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
/* fork/exec/system are prohibited on Apple mobile sandboxes. */
static inline int wwn_weston_system(const char *cmd) { (void)cmd; return -1; }
#define system(cmd) wwn_weston_system(cmd)
static inline pid_t wwn_weston_fork(void) { return (pid_t)-1; }
#undef fork
#define fork() wwn_weston_fork()
#define execl(file, arg0, ...) (-1)
#define execlp(file, arg0, ...) (-1)
#define execve(file, argv, envp) (-1)
#define execv(file, argv) (-1)
#define execvp(file, argv) (-1)
#endif
/* String literal (not getprogname): App Store rejects libSystem ___progname. */
#ifndef program_invocation_short_name
#define program_invocation_short_name "weston"
#endif
#endif
#endif
EOF

    cat > include/libinput.h <<'EOF'
#ifndef _LIBINPUT_H
#define _LIBINPUT_H
#include <stdint.h>
struct libinput;
struct libinput_device;
struct libinput_event;
struct libinput_event_keyboard;
struct libinput_event_pointer;
struct libinput_seat;

enum libinput_led { LIBINPUT_LED_NUM_LOCK, LIBINPUT_LED_CAPS_LOCK, LIBINPUT_LED_SCROLL_LOCK };
enum libinput_key_state { LIBINPUT_KEY_STATE_RELEASED, LIBINPUT_KEY_STATE_PRESSED };
enum libinput_device_capability { LIBINPUT_DEVICE_CAP_POINTER, LIBINPUT_DEVICE_CAP_KEYBOARD, LIBINPUT_DEVICE_CAP_TOUCH };

enum libinput_config_scroll_method { LIBINPUT_CONFIG_SCROLL_NO_SCROLL, LIBINPUT_CONFIG_SCROLL_2FG, LIBINPUT_CONFIG_SCROLL_EDGE, LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN };
enum libinput_config_click_method { LIBINPUT_CONFIG_CLICK_METHOD_NONE, LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS, LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER };
enum libinput_config_tap_state { LIBINPUT_CONFIG_TAP_DISABLED, LIBINPUT_CONFIG_TAP_ENABLED };
enum libinput_config_tap_button_map { LIBINPUT_CONFIG_TAP_MAP_LRM, LIBINPUT_CONFIG_TAP_MAP_LMR };
enum libinput_config_send_events_mode { LIBINPUT_CONFIG_SEND_EVENTS_ENABLED, LIBINPUT_CONFIG_SEND_EVENTS_DISABLED, LIBINPUT_CONFIG_SEND_EVENTS_DISABLED_ON_EXTERNAL_MOUSE };
enum libinput_config_accel_profile { LIBINPUT_CONFIG_ACCEL_PROFILE_NONE, LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT, LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE };

static inline const char* libinput_device_get_name(struct libinput_device *d) { (void)d; return "apple-input"; }
static inline void* libinput_device_get_user_data(struct libinput_device *d) { (void)d; return (void*)0; }
static inline int libinput_device_has_capability(struct libinput_device *d, int c) { (void)d; (void)c; return 0; }
static inline int libinput_event_keyboard_get_key_state(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline int libinput_event_keyboard_get_seat_key_count(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline uint64_t libinput_event_keyboard_get_time_usec(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline uint32_t libinput_event_keyboard_get_key(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline void libinput_device_led_update(struct libinput_device *d, int l) { (void)d; (void)l; }
static inline void* libinput_event_keyboard_get_device(struct libinput_event_keyboard *e) { (void)e; return (void*)0; }

static inline uint32_t libinput_device_config_scroll_get_methods(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_scroll_set_method(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline int libinput_device_config_scroll_set_button(struct libinput_device *d, uint32_t b) { (void)d; (void)b; return 0; }
static inline uint32_t libinput_device_config_click_get_methods(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_click_set_method(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline int libinput_device_config_tap_get_finger_count(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_tap_set_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline void libinput_device_config_tap_set_button_map(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline void libinput_device_config_tap_set_drag_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline void libinput_device_config_tap_set_drag_lock_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline void libinput_device_config_send_events_set_mode(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline int libinput_device_config_accel_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_accel_set_speed(struct libinput_device *d, double s) { (void)d; (void)s; }
static inline void libinput_device_config_accel_set_profile(struct libinput_device *d, int p) { (void)d; (void)p; }
static inline uint32_t libinput_device_config_accel_get_profiles(struct libinput_device *d) { (void)d; return 0; }
static inline int libinput_device_config_left_handed_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_left_handed_set(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline int libinput_device_config_middle_emulation_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_middle_emulation_set_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline int libinput_device_config_natural_scroll_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline int libinput_device_config_scroll_has_natural_scroll(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_scroll_set_natural_scroll_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline int libinput_device_config_rotation_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_rotation_set_angle(struct libinput_device *d, double a) { (void)d; (void)a; }
static inline void libinput_device_config_calibration_set_matrix(struct libinput_device *d, const float m[6]) { (void)d; (void)m; }
static inline int libinput_device_config_tap_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline int libinput_device_config_dwt_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_dwt_set_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
#endif
EOF

    cat > include/libevdev/libevdev.h <<'EOF'
#ifndef _LIBEVDEV_H
#define _LIBEVDEV_H
struct libevdev;
#define EV_KEY 1
static inline int libevdev_event_code_from_name(unsigned int type, const char *name) { (void)type; (void)name; return -1; }
#endif
EOF

    cat > include/libudev.h <<'EOF'
#ifndef _LIBUDEV_H
#define _LIBUDEV_H
struct udev;
struct udev_device;
#endif
EOF
    ${lib.optionalString enableIlandDrm ''
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/udev/include/libudev.h include/libudev.h
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/udev/src/udev.c compositor/wwn-udev-shim.c
    python3 - <<'PY'
from pathlib import Path
path = Path("libweston/backend-drm/meson.build")
text = path.read_text()
needle = "srcs_drm = ["
if needle not in text:
    raise SystemExit("srcs_drm anchor missing")
text = text.replace(
    needle,
    needle + "\n\t'../../compositor/wwn-udev-shim.c',",
    1,
)
path.write_text(text)
PY
    ''}

    ${lib.optionalString (!enableIlandDrm) ''
    cat > include/gbm.h <<'EOF'
#ifndef _GBM_H
#define _GBM_H
struct gbm_device;
struct gbm_bo;
struct gbm_surface;
#endif
EOF
    ''}

    cat > include/pty.h <<'EOF'
#ifndef _PTY_H
#define _PTY_H
#include <util.h>
#endif
EOF

    cat > include/values.h <<'EOF'
#ifndef _VALUES_H
#define _VALUES_H
#include <limits.h>
#include <float.h>
#endif
EOF

    cat > include/alloca.h <<'EOF'
#ifndef _ALLOCA_H
#define _ALLOCA_H
#include <stdlib.h>
#endif
EOF

    # Linux pixel-formats.c uses `__BYTE_ORDER == __LITTLE_ENDIAN`. Darwin's
    # <machine/endian.h> only defines BYTE_ORDER / LITTLE_ENDIAN (no underscores).
    # Defining __BYTE_ORDER alone made `#if __BYTE_ORDER == __LITTLE_ENDIAN` become
    # `1234 == 0` (false) → big-endian PIXMAN_* branches on little-endian Apple,
    # so nested Weston SHM was B↔A swapped (everything blue-tinted / B=255).
    cat > include/endian.h <<'EOF'
#ifndef _ENDIAN_H
#define _ENDIAN_H
#include <machine/endian.h>
#define __BYTE_ORDER BYTE_ORDER
#define __LITTLE_ENDIAN LITTLE_ENDIAN
#define __BIG_ENDIAN BIG_ENDIAN
#ifdef PDP_ENDIAN
#define __PDP_ENDIAN PDP_ENDIAN
#endif
#endif
EOF

    cp ${linux_input_h} include/linux/input.h
    cp ${linux_input_event_codes_h} include/linux/input-event-codes.h
    cat > include/linux/types.h <<'EOF'
#ifndef _LINUX_TYPES_H
#define _LINUX_TYPES_H
#include <stdint.h>
typedef uint8_t __u8; typedef uint16_t __u16; typedef uint32_t __u32; typedef uint64_t __u64;
typedef int8_t __s8; typedef int16_t __s16; typedef int32_t __s32; typedef int64_t __s64;
typedef uint16_t __le16; typedef uint32_t __le32; typedef uint64_t __le64;
#define __user
#define __BITS_PER_LONG 64
#endif
EOF
    cat > include/linux/ioctl.h <<'EOF'
#ifndef _LINUX_IOCTL_H
#define _LINUX_IOCTL_H
#include <sys/ioctl.h>
#endif
EOF
    cat > include/linux/limits.h <<'EOF'
#ifndef _LINUX_LIMITS_H
#define _LINUX_LIMITS_H
#include <limits.h>
#endif
EOF

    cp ${libdrm_fourcc_h} include/drm_fourcc.h
    cp ${libdrm_h} include/drm.h
    cp ${libdrm_mode_h} include/drm_mode.h
    ${lib.optionalString enableIlandDrm ''
    cp ${libdrm_xf86drm_h} include/xf86drm.h
    cp ${libdrm_xf86drm_mode_h} include/xf86drmMode.h
    ''}
    ${lib.optionalString (!enableIlandDrm) ''
    cat > include/xf86drm.h <<'EOF'
#ifndef _XF86DRM_H
#define _XF86DRM_H
#include <stdint.h>
#define drmGetFormatModifierName(m) "INVALID"
#define drmGetFormatModifierVendor(m) "INVALID"
#endif
EOF
    ''}

    # wayland-cursor headers (libwayland-ios ships the .a but not cursor/*.h)
    mkdir -p include/wayland
    cp ${wayland_cursor_h} include/wayland/wayland-cursor.h
    cp ${wayland_xcursor_h} include/wayland/xcursor.h
    ${lib.optionalString enableIlandDrm ''
    cp ${wayland_egl_h} include/wayland-egl.h
    cp ${wayland_egl_core_h} include/wayland-egl-core.h
    cat > include/linux/vt.h <<'EOF'
#include <sys/ioctl.h>
EOF
    cat > include/malloc.h <<'EOF'
#include <stdlib.h>
EOF
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/gbm/include/gbm.h include/gbm.h
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/gbm/include/gbm_priv.h include/gbm_priv.h
    ''}

    ${lib.optionalString (!enableIlandDrm) ''
    cat > include/EGL/egl.h <<'EOF'
#ifndef _EGL_H
#define _EGL_H
typedef void *EGLDisplay;
typedef void *EGLContext;
typedef void *EGLSurface;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_NONE 0x3038
#endif
EOF
    touch include/EGL/eglext.h include/EGL/eglplatform.h include/GLES2/gl2.h include/GLES2/glext.h include/KHR/khrplatform.h
    ''}
  '';

  preConfigure = ''
    ${if macos then ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
      fi
      export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
      export APPLE_SDK_NAME=macosx
      export SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
      export XCODE_CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      export XCODE_CLANGXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      export IOS_ARCH="${if stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64"}"
      export APPLE_DEPLOYMENT_FLAG="-mmacosx-version-min=${mobileMinVersion}"
      export APPLE_LINKER_TARGET=""
    '' else iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobileMinVersion; }}

    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CC="$XCODE_CLANG"
    export CXX="$XCODE_CLANGXX"
    export PKG_CONFIG_PATH="$PWD/stub-pkgconfig:${waylandScanner}/share/pkgconfig:${pkgConfigPath}"

    mkdir -p stub-pkgconfig
    cat > stub-pkgconfig/libudev.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libudev
Version: 255
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/libinput.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libinput
Version: 1.25.0
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/libevdev.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libevdev
Version: 1.13.0
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/libdrm.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libdrm
Version: 2.4.120
Cflags: -I$PWD/include
EOF
    ${lib.optionalString enableIlandDrm ''
    cat > stub-pkgconfig/gbm.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: gbm
Version: 22.0.0
Description: iland GBM shim (header only; impl in libiland_userland)
Cflags: -I$PWD/include
Libs: -L${iland}/lib -liland_userland
EOF
    cat > stub-pkgconfig/egl.pc <<EOF
prefix=${angle}
includedir=${angle}/include
libdir=${angle}/lib
Name: egl
Version: 1.5
Description: ANGLE EGL (via iland)
Cflags: -I${angle}/include -I${angle}/include/EGL -DILAND_ANGLE_STATIC
Libs: -L${iland}/lib -liland_userland
EOF
    cat > stub-pkgconfig/glesv2.pc <<EOF
prefix=${angle}
includedir=${angle}/include
libdir=${angle}/lib
Name: glesv2
Version: 2.0
Description: ANGLE GLES2 (via iland)
Cflags: -I${angle}/include -I${angle}/include/GLES2 -DILAND_ANGLE_STATIC
Libs: -L${iland}/lib -liland_userland
EOF
    cat > stub-pkgconfig/libdrm.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libdrm
Version: 2.4.120
Description: Linux DRM UAPI headers (mesa) + iland ioctl helpers via xf86drm.h
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/libseat.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libseat
Version: 0.7.0
Cflags: -I$PWD/include/libseat
EOF
    cat > stub-pkgconfig/wayland-egl.pc <<EOF
prefix=$PWD
includedir=$PWD/include
libdir=${libwayland}/lib
Name: wayland-egl
Version: 1.25.0
Description: Wayland EGL windowing (header stub + libwayland-ios)
Cflags: -I$PWD/include
Libs: -L${libwayland}/lib -lwayland-egl -lwayland-client
EOF
    ''}
    cat > stub-pkgconfig/wayland-scanner.pc <<EOF
prefix=${waylandScanner}
exec_prefix=''${prefix}
bindir=''${exec_prefix}/bin
wayland_scanner=${waylandScanner}/bin/wayland-scanner
Name: wayland-scanner
Description: Wayland protocol scanner
Version: 1.25.0
EOF

    # Meson runs wayland-scanner on the build machine during protocol codegen.
    MACOS_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
    NATIVE_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    NATIVE_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"

    cat > native-file.txt <<EOF
[binaries]
c = '$NATIVE_CC'
cpp = '$NATIVE_CXX'
ar = 'ar'
strip = 'strip'
pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
wayland-scanner = '${waylandScanner}/bin/wayland-scanner'

[built-in options]
c_args = ['-isysroot', '$MACOS_SDK_PATH']
cpp_args = ['-isysroot', '$MACOS_SDK_PATH']
objc_args = ['-isysroot', '$MACOS_SDK_PATH', '-fobjc-arc']
objcpp_args = ['-isysroot', '$MACOS_SDK_PATH', '-fobjc-arc']
c_link_args = ['-isysroot', '$MACOS_SDK_PATH']
cpp_link_args = ['-isysroot', '$MACOS_SDK_PATH']
pkg_config_path = ['$PWD/stub-pkgconfig', '${waylandScanner}/share/pkgconfig', '${buildPackages.wayland-protocols}/share/pkgconfig']
EOF

    _CC="$XCODE_CLANG"
    _CXX="$XCODE_CLANGXX"
    _SDK="$SDKROOT"
    _ARCH="$IOS_ARCH"
    _DEPLOY="$APPLE_DEPLOYMENT_FLAG"
    if [[ "''${APPLE_SDK_NAME:-}" == xros ]] || [[ "''${APPLE_SDK_NAME:-}" == xrsimulator ]]; then
      _TARGET="$APPLE_LINKER_TARGET"
      _DEPLOY=""
    else
      _TARGET=""
    fi

    EPOL_LINK="-L${epollShim}/lib -lepoll-shim"

    if [[ -n "$_TARGET" ]]; then
      cat > ios-cross-file.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
ar = 'ar'
strip = 'strip'
pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
wayland-scanner = '${waylandScanner}/bin/wayland-scanner'

[host_machine]
system = 'darwin'
cpu_family = '${targetCpu}'
cpu = '${targetCpu}'
endian = 'little'
subsystem = '${mobile.mesonSubsystem}'

[built-in options]
objc_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-fPIC', '-fobjc-arc']
objcpp_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-fPIC', '-fobjc-arc']
c_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-fPIC', '-D_DARWIN_C_SOURCE', '-I${epollShim}/include/libepoll-shim', '-I$PWD/include', '-I$PWD/include/wayland'${lib.optionalString enableIlandDrm ", '-I$PWD/include/libseat', '-I${iland}/include/EGL', '-I${iland}/include/GLES2', '-I${angle}/include', '-DILAND_ANGLE_STATIC', '-include', '${iland}/include/iland_drm_open_compat.h'"}, '-include', '$PWD/include/weston-macos-polyfills.h', '-DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC', '-DCLOCK_REALTIME_COARSE=CLOCK_REALTIME']
cpp_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$PWD/include']
c_link_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
cpp_link_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
pkg_config_path = ['$PWD/stub-pkgconfig', '${crossPkgConfigDirs}']
default_library = 'static'
EOF
    else
      cat > ios-cross-file.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
ar = 'ar'
strip = 'strip'
pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
wayland-scanner = '${waylandScanner}/bin/wayland-scanner'

[host_machine]
system = 'darwin'
cpu_family = '${targetCpu}'
cpu = '${targetCpu}'
endian = 'little'
subsystem = '${mobile.mesonSubsystem}'

[built-in options]
objc_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-fobjc-arc']
objcpp_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-fobjc-arc']
c_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-D_DARWIN_C_SOURCE', '-I${epollShim}/include/libepoll-shim', '-I$PWD/include', '-I$PWD/include/wayland'${lib.optionalString enableIlandDrm ", '-I$PWD/include/libseat', '-I${iland}/include/EGL', '-I${iland}/include/GLES2', '-I${angle}/include', '-DILAND_ANGLE_STATIC', '-include', '${iland}/include/iland_drm_open_compat.h'"}, '-include', '$PWD/include/weston-macos-polyfills.h', '-DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC', '-DCLOCK_REALTIME_COARSE=CLOCK_REALTIME']
cpp_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$PWD/include']
c_link_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
cpp_link_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
pkg_config_path = ['$PWD/stub-pkgconfig', '${crossPkgConfigDirs}']
default_library = 'static'
EOF
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    export PKG_CONFIG_PATH="$PWD/stub-pkgconfig:${waylandScanner}/share/pkgconfig:${pkgConfigPath}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --native-file=native-file.txt \
      --cross-file=ios-cross-file.txt \
      --default-library=static \
      ${lib.concatMapStringsSep " \\\n      " (f: f) mesonFlags}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/include

    mapfile -t ARCHIVES < <(find build -name '*.a' -type f | sort)
    if [ "''${#ARCHIVES[@]}" -eq 0 ]; then
      echo "No static archives produced" >&2
      exit 1
    fi

    # libtool -static keeps duplicate libweston core objects from each backend
    # archive; extract into one directory so same-named .o files collapse.
    MERGE_DIR=$(mktemp -d)
    ROOT="$PWD"
    for a in "''${ARCHIVES[@]}"; do
      (cd "$MERGE_DIR" && ar x "$ROOT/$a") || exit 1
    done

    # Apple mobile pairs this archive with weston-ios libweston-13.a (toytoolkit +
    # shared helpers + client protocol glue). Drop those objects here so Xcode can
    # force_load both without duplicate symbols.
    #
    # macOS has no libweston-13.a — buildForMacOS "weston" is a shared/dylib recipe
    # for Resources/bin demos. Keeping helpers/protocols in this fat archive is what
    # makes -force_load libweston-compositor-13.a link (frame_create, custom_env_*,
    # hash_table_*, wl_interface protocol symbols, …).
    ${if macos then ''
    echo "macos: keeping shared helpers + protocol glue in libweston-compositor-13.a"
    '' else ''
    for pattern in \
      'os-compatibility.c.o' \
      'process-util.c.o' \
      'config-parser.c.o' \
      'option-parser.c.o' \
      'signal.c.o' \
      'file-util.c.o' \
      'hash.c.o' \
      'image-loader.c.o' \
      'cairo-util.c.o' \
      'frame.c.o' \
      '*matrix*.o' \
      'vertex-clipping.c.o' \
      'wayland-cursor.c.o' \
      'xcursor.c.o'; do
      find "$MERGE_DIR" -name "$pattern" -delete
    done

    for pattern in \
      '*weston-desktop-shell-protocol*.o' \
      '*input-method-unstable-v1-protocol*.o' \
      '*xdg-shell-protocol*.o' \
      '*viewporter-protocol*.o' \
      '*presentation-time-protocol*.o' \
      '*relative-pointer-unstable-v1-protocol*.o' \
      '*pointer-constraints-unstable-v1-protocol*.o' \
      '*tablet-unstable-v2-protocol*.o' \
      '*text-input-unstable-v1-protocol*.o' \
      '*text-cursor-position-protocol*.o'; do
      find "$MERGE_DIR" -name "$pattern" -delete
    done
    ''}

    # Meson embeds different relative-path depths in object names
    # (…_.._protocol_FOO vs …_.._.._protocol_FOO). Same wl_interface
    # symbols then collide under -force_load. Keep one object per protocol.
    dedupe_protocol_suffix() {
      local suffix="$1"
      mapfile -t matches < <(find "$MERGE_DIR" -name "*$suffix*.o" | sort)
      if [ "''${#matches[@]}" -gt 1 ]; then
        for f in "''${matches[@]:1}"; do rm -f "$f"; done
      fi
    }
    for suffix in \
      xdg-shell-protocol \
      xdg-shell-unstable-v6-protocol \
      xdg-output-unstable-v1-protocol \
      linux-dmabuf-unstable-v1-protocol \
      presentation; do
      dedupe_protocol_suffix "$suffix"
    done

    find "$MERGE_DIR" -name '*.o' -print0 | xargs -0 ar rcs $out/lib/libweston-compositor-13.a

    # Host launch uses weak_import of weston_compositor_main — must stay global.
    if ! nm -gU $out/lib/libweston-compositor-13.a 2>/dev/null \
         | grep -E '[[:space:]]T[[:space:]]+_weston_compositor_main$' >/dev/null; then
      echo "ERROR: _weston_compositor_main is not a global text symbol in libweston-compositor-13.a" >&2
      nm -m $out/lib/libweston-compositor-13.a 2>/dev/null | grep weston_compositor_main >&2 || true
      exit 1
    fi
    ${lib.optionalString enableIlandDrm ''
    if ! nm -gU $out/lib/libweston-compositor-13.a 2>/dev/null \
         | grep -E '[[:space:]]T[[:space:]]+_wwn_weston_drm_backend_init$' >/dev/null; then
      echo "ERROR: _wwn_weston_drm_backend_init missing from libweston-compositor-13.a (enableIlandDrm)" >&2
      nm $out/lib/libweston-compositor-13.a 2>/dev/null | grep -E 'weston_backend_init|wwn_weston_drm' >&2 || true
      exit 1
    fi
    ''}

    cp include/wwn-static-modules.h $out/include/ 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "Weston nested compositor static archive for Apple mobile";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
