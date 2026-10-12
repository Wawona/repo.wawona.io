{ lib, stdenv, fetchurl, meson, ninja, pkg-config, wayland, wayland-scanner, wayland-protocols, libxkbcommon, cairo, pango, libpng, libjpeg, mesa, pixman, python3, libinput, libevdev, seatd, pam, openssl, epoll-shim
, # L1 source injection (headers/shims only). Mode B supplies drm/EGL at runtime
  # via DYLD_INSERT of libwayland-mac.dylib; do not LC_LOAD Mode A/B dylibs here.
  ilandSrc ? null
, buildModule ? null
, ...
}:
assert ilandSrc != null;
let
  angle =
    if buildModule != null then buildModule.buildForMacOS "angle" { } else null;
  # Nix pkg-config wrapper ignores ad-hoc $PWD stubs. Ship .pc files as a
  # real store path so meson finds egl/gbm/libdrm without linking Mode A/B.
  westonDrmStubPc = stdenv.mkDerivation {
    name = "weston-macos-drm-stub-pc";
    preferLocalBuild = true;
    allowSubstitutes = false;
    buildCommand = ''
      mkdir -p $out/lib/pkgconfig
      cat > $out/lib/pkgconfig/libdrm.pc <<EOF
prefix=/nonexistent
includedir=/nonexistent
Name: libdrm
Version: 2.4.120
Description: DRM UAPI headers via -I in c_args (Mode B dynamic_lookup)
Cflags:
Libs:
EOF
      cat > $out/lib/pkgconfig/gbm.pc <<EOF
prefix=/nonexistent
Name: gbm
Version: 22.0.0
Description: iland GBM headers via -I (Mode B dynamic_lookup)
Cflags:
Libs:
EOF
      cat > $out/lib/pkgconfig/libudev.pc <<EOF
prefix=/nonexistent
Name: libudev
Version: 255
Cflags:
Libs:
EOF
      cat > $out/lib/pkgconfig/libseat.pc <<EOF
prefix=/nonexistent
Name: libseat
Version: 0.7.0
Cflags:
Libs:
EOF
      cat > $out/lib/pkgconfig/libinput.pc <<EOF
prefix=/nonexistent
Name: libinput
Version: 1.25.0
Cflags:
Libs:
EOF
      ${lib.optionalString (angle != null) ''
        cat > $out/lib/pkgconfig/egl.pc <<EOF
prefix=${angle}
includedir=${angle}/include
Name: egl
Description: ANGLE EGL headers (Mode B dynamic_lookup)
Version: 1.5
Cflags: -I${angle}/include -I${angle}/include/EGL
Libs:
EOF
        cat > $out/lib/pkgconfig/glesv2.pc <<EOF
prefix=${angle}
includedir=${angle}/include
Name: glesv2
Description: ANGLE GLES2 headers (Mode B dynamic_lookup)
Version: 2.0
Cflags: -I${angle}/include -I${angle}/include/GLES2
Libs:
EOF
      ''}
    '';
  };
in
stdenv.mkDerivation rec {
  pname = "weston-macos-drm-shared";
  version = "13.0.0";
  linuxHeadersRef = "45dcf5e28813954da4150e7260ccb61e95856176";
  drmHeadersRef = "8de45ef60d69472a0f8ba898f91250dac88bb81f";

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  patches = [
    ./patches/0001-constraints-mark-reused-buffer-busy.patch
    ./patches/0002-wayland-backend-nested-xdg-size.patch
    ./patches/0003-libexec-weston-libexec-dir.patch
  ];
  
  # Fetch linux input headers for macOS shim
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
  libdrm_xf86drm_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/xf86drm.h";
    sha256 = "sha256-X62GrL3cw7amhWkNoMfeWUEtNU0TdWRHNGcvXGvfQgI=";
  };
  libdrm_xf86drm_mode_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/xf86drmMode.h";
    sha256 = "sha256-ltfaSCm9QfQaPiYBHHz5pjpZfWZAfzNIqpuyvTcS4uI=";
  };

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner python3 westonDrmStubPc ];

  buildInputs = [
    wayland
    wayland-protocols
    libxkbcommon
    cairo
    pango
    libpng
    epoll-shim
    libjpeg
    mesa
    pixman
    openssl
  ];

  mesonFlags = [
    "-Dbackend-drm=true"
    "-Dbackend-drm-screencast-vaapi=false"
    "-Dbackend-headless=true"
    "-Dbackend-rdp=false"
    "-Dbackend-vnc=false"
    "-Dbackend-pipewire=false"
    "-Dbackend-wayland=true"
    "-Dbackend-x11=false"
    "-Dxwayland=false"
    # Mode B fork/exec recipe. Nested Mode A always passes --backend=wayland.
    # Bare `weston` on a Classic TTY must be DRM/KMS/GBM (iland), not nested.
    "-Dbackend-default=drm"
    "-Drenderer-gl=true"
    "-Db_lundef=false"
    "-Dimage-jpeg=true"
    "-Dimage-webp=false"
    "-Ddemo-clients=true"
    "-Dsimple-clients=damage,im,shm,touch"
    "-Dtest-junit-xml=false"
    "-Ddoc=false"
    "-Dpipewire=false"
    "-Dsystemd=false"
    "-Dcolor-management-lcms=false"
  ] ++ lib.optionalString stdenv.hostPlatform.isDarwin [
    "-Dremoting=false"
    "-Dshell-fullscreen=false"
    "-Dshell-ivi=false"
    "-Dshell-kiosk=false"
  ];

  preConfigure = ''
    # Create the polyfill header
    mkdir -p include
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
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};

#define WESTON_HOWMANY(x, y) (((int)(x) + (int)(y) - 1) / (int)(y))
#define SOCK_CLOEXEC 0
#define SOCK_NONBLOCK 0

/* Linux memfd seals (os-compatibility.c). Darwin has no memfd seals; define
 * the constants so the unused HAVE_MEMFD paths compile. */
#ifndef F_ADD_SEALS
#define F_ADD_SEALS 1033
#define F_GET_SEALS 1034
#define F_SEAL_SEAL 0x0001
#define F_SEAL_SHRINK 0x0002
#define F_SEAL_GROW 0x0004
#define F_SEAL_WRITE 0x0008
#endif

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

/* Weston provides the definition in os-compatibility.c, we just need the declaration */
char *strchrnul(const char *s, int c);

/* String literal (not getprogname): App Store rejects libSystem ___progname.
 * Define in the header so meson/ninja cannot strip -D quotes. */
#ifndef program_invocation_short_name
#define program_invocation_short_name "weston"
#endif
#endif
#endif
EOF

    mesonFlagsArray+=(
      "-Dc_args=${lib.optionalString (angle != null) "-I${angle}/include -I${angle}/include/EGL -I${angle}/include/GLES2 "}-I${epoll-shim}/include/libepoll-shim -I$PWD/include -I$PWD/include/libseat -include $PWD/include/weston-macos-polyfills.h -DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC -DCLOCK_REALTIME_COARSE=CLOCK_REALTIME -UHAVE_MEMFD_CREATE -UHAVE_POSIX_FALLOCATE"
      "-Dc_link_args=-L${epoll-shim}/lib -lepoll-shim -Wl,-undefined,dynamic_lookup"
      "-Dcpp_link_args=-L${epoll-shim}/lib -lepoll-shim -Wl,-undefined,dynamic_lookup"
    )
  '';
  
  NIX_CFLAGS_COMPILE = "-I${epoll-shim}/include/libepoll-shim -I$PWD/include";
  NIX_LDFLAGS = "-L${epoll-shim}/lib -lepoll-shim";

  # DRM/GL meson probes can spuriously enable Linux memfd seals on Darwin.
  postConfigure = lib.optionalString stdenv.hostPlatform.isDarwin ''
    echo "postConfigure cwd=$PWD"
    find . -name config.h -print
    for f in $(find . -name config.h); do
      echo "--- $f before ---"
      grep -E 'MEMFD|FALLOCATE' "$f" || true
      # config.h may use #define HAVE_FOO or #define HAVE_FOO 1
      sed -i -E 's/^#define HAVE_MEMFD_CREATE.*/\/\* Darwin: no memfd *\//' "$f"
      sed -i -E 's/^#define HAVE_POSIX_FALLOCATE.*/\/\* Darwin: no posix_fallocate *\//' "$f"
      echo "--- $f after ---"
      grep -E 'MEMFD|FALLOCATE|Darwin' "$f" || true
    done
  '';

  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Darwin has no memfd seals; force the shm fallback path regardless of meson probes.
    python3 <<'PY'
from pathlib import Path
path = Path("shared/os-compatibility.c")
text = path.read_text()
needle = '#include "config.h"\n'
inject = needle + "#undef HAVE_MEMFD_CREATE\n#undef HAVE_POSIX_FALLOCATE\n"
if "undef HAVE_MEMFD_CREATE" not in text:
    if needle not in text:
        raise SystemExit("os-compatibility.c: config.h include missing")
    text = text.replace(needle, inject, 1)
    path.write_text(text)
print("forced Darwin shm fallback in os-compatibility.c")
PY

    # Skip building problematic subdirectories (keeping compositor and shells)
    sed -i "/subdir('tests')/d" meson.build
    
    # Remove subsurfaces demo client (requires EGL/GLES2; not available on macOS meson build).
    sed -i "/'subsurfaces.c'/d" clients/meson.build
    python3 <<'PY'
from pathlib import Path
import re
path = Path("clients/meson.build")
text = path.read_text()
text, n = re.subn(
    r"\n\t\{\n\t\t'basename': 'subsurfaces',.*?\n\t\},",
    "",
    text,
    count=1,
    flags=re.DOTALL,
)
if n != 1:
    raise SystemExit(f"subsurfaces demo client block not removed (n={n})")
path.write_text(text)
PY
    
    # Create an empty C file to replace problematic sources while keeping Meson syntax intact
    touch include/empty.c

    # Replace libinput source files with our empty file
    sed -i "s/'libinput-device.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.h'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-device.h'/'..\/include\/empty.c'/g" libweston/meson.build

    # Patch backend default logic
    sed -i "s|message('The default backend is ' + backend_default)|message('Skipping backend validation for client-only build')|g" meson.build
    
    # Make all Linux-specific dependencies optional
    sed -i "s/dependency('libinput'/dependency('libinput', required: false/g" meson.build
    sed -i "s/dependency('libevdev'/dependency('libevdev', required: false/g" meson.build
    sed -i "s/dependency('libdrm'/dependency('libdrm', required: false/g" meson.build
    sed -i "s/'launcher-libseat.c'/'wwn-drm-link-stubs.c'/g" libweston/meson.build
    # DRM backend dlopens against flat-namespace symbols that lived in
    # launcher-libseat.c / libinput-seat.c. Provide stubs in libweston.
    cat > libweston/wwn-drm-link-stubs.c <<'EOF'
#include "config.h"
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include "libinput-seat.h"
#include "launcher-impl.h"

#if defined(__GNUC__) || defined(__clang__)
#define WWN_EXPORT __attribute__((visibility("default")))
#else
#define WWN_EXPORT
#endif

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
	(void)input;
	(void)c;
	(void)udev;
	(void)seat_id;
	(void)configure_device;
	/* Mode B: no libinput. --continue-without-input is the client flag;
	 * DRM backend still requires udev_input_init to succeed. */
	return 0;
}

WWN_EXPORT void
udev_input_destroy(struct udev_input *input)
{
	(void)input;
}

WWN_EXPORT struct udev_seat *
udev_seat_get_named(struct udev_input *u, const char *seat_name)
{
	(void)u;
	(void)seat_name;
	return NULL;
}

/* Mode B: no seatd/logind. Succeed as a launcher and open DRM nodes with
 * plain open(); libwayland-mac.dylib interposes those paths. */
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
	/* DRM backend waits for an active session before modeset. */
	compositor->session_active = true;
	wl_signal_emit(&compositor->session_signal, compositor);
	*launcher_out = &wl->base;
	weston_log("wwn-launcher: Mode B stub seat (no seatd/logind)\n");
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
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/udev/include/libudev.h include/libudev.h
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/udev/src/udev.c compositor/wwn-udev-shim.c
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/gbm/include/gbm.h include/gbm.h
    cp ${ilandSrc}/dependencies/libs/iland/upstream/shims/gbm/include/gbm_priv.h include/gbm_priv.h
    chmod u+w include/libudev.h include/gbm.h include/gbm_priv.h compositor/wwn-udev-shim.c
    python3 <<'PY'
from pathlib import Path
path = Path("libweston/backend-drm/meson.build")
text = path.read_text()
needle = "srcs_drm = ["
if needle not in text:
    raise SystemExit("srcs_drm anchor missing")
if "wwn-udev-shim.c" not in text:
    text = text.replace(needle, needle + "\n\t'../../compositor/wwn-udev-shim.c',", 1)
    path.write_text(text)
PY
    sed -i "s/cc.find_library('pam'/cc.find_library('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('pam'/dependency('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" clients/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" tests/meson.build
    
    # Downgrade errors to warnings in clients
    sed -i "s/error(/warning(/g" clients/meson.build

    # Patch terminal.c to use our safe HOWMANY macro
    sed -i "s/\bhowmany\b/WESTON_HOWMANY/g" clients/terminal.c
    # Keep classic default title expected by Wawona UX/tests.
    # Weston 13 defaults to "Wayland Terminal"; restore "Weston Terminal".
    sed -i "s/Wayland Terminal/Weston Terminal/g" clients/terminal.c

    # --- OSC 7 title + PROMPT_COMMAND patches ---
    # macOS zsh sends OSC 7 (file://host/path) for the cwd instead of
    # OSC 0/2. Upstream weston-terminal recognises OSC 7 but silently
    # discards it.  Patch handle_osc to extract the path from the URI
    # and set it as the window title.  Also inject PROMPT_COMMAND so
    # bash sessions send OSC 0 title updates on every prompt.
    cat > _patch_terminal_title.py << 'PYEOF'
with open("clients/terminal.c") as f:
    src = f.read()

# --- 1. OSC 7: extract directory from file:// URI, set as title ---
old_osc7 = "\tcase 7: /* shell cwd as uri */\n\t\tbreak;"
new_osc7 = (
    "\tcase 7: { /* shell cwd as uri - extract path for title */\n"
    "\t\tconst char *fp = \"file://\";\n"
    "\t\tif (strncmp(p, fp, 7) == 0) {\n"
    "\t\t\tconst char *sl = strchr(p + 7, '/');\n"
    "\t\t\tif (sl) {\n"
    "\t\t\t\tconst char *hm = getenv(\"HOME\");\n"
    "\t\t\t\tsize_t hlen = hm ? strlen(hm) : 0;\n"
    "\t\t\t\tchar *t = NULL;\n"
    "\t\t\t\tif (hm && strncmp(sl, hm, hlen) == 0\n"
    "\t\t\t\t    && (sl[hlen] == '/' || sl[hlen] == '\\0'))\n"
    "\t\t\t\t\tasprintf(&t, \"~%s\", sl + hlen);\n"
    "\t\t\t\telse\n"
    "\t\t\t\t\tt = strdup(sl);\n"
    "\t\t\t\tif (t) {\n"
    "\t\t\t\t\tfree(terminal->title);\n"
    "\t\t\t\t\tterminal->title = t;\n"
    "\t\t\t\t\twindow_set_title(terminal->window, t);\n"
    "\t\t\t\t}\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t\tbreak;\n"
    "\t}"
)
assert old_osc7 in src, "OSC 7 patch target not found in terminal.c"
src = src.replace(old_osc7, new_osc7)

# --- 2. PROMPT_COMMAND for bash ---
old_env = '\t\tsetenv("COLORTERM", option_term, 1);'
prompt = (
    'printf \'\\\\033]0;%s@%s:%s\\\\007\' '
    '\\"$USER\\" '
    '\\"''${HOSTNAME%%.*}\\" '
    '\\"''${PWD/#$HOME/~}\\"'
)
new_env = old_env + '\n\t\tsetenv("PROMPT_COMMAND", "' + prompt + '", 0);'
assert old_env in src, "COLORTERM patch target not found in terminal.c"
src = src.replace(old_env, new_env)

with open("clients/terminal.c", "w") as f:
    f.write(src)
print("Patched terminal.c: OSC 7 handler + PROMPT_COMMAND")
PYEOF
    python3 _patch_terminal_title.py
    rm _patch_terminal_title.py
    
    # Create inclusive directory for shims (no GLES/EGL stubs: ANGLE headers via c_args)
    mkdir -p include/sys include/libudev include/libinput include/linux include/libevdev

    # libudev.h already copied from ilandSrc (Mode B shared DRM)

    # Create libevdev/libevdev.h shim
    cat > include/libevdev/libevdev.h <<'EOF'
#ifndef _LIBEVDEV_H
#define _LIBEVDEV_H
struct libevdev;
#define EV_KEY 1
static inline int libevdev_event_code_from_name(unsigned int type, const char *name) { return -1; }
#endif
EOF

    # Create libinput.h shim
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

static inline const char* libinput_device_get_name(struct libinput_device *d) { return "macos-input"; }
static inline void* libinput_device_get_user_data(struct libinput_device *d) { return (void*)0; }
static inline int libinput_device_has_capability(struct libinput_device *d, int c) { return 0; }
static inline int libinput_event_keyboard_get_key_state(struct libinput_event_keyboard *e) { return 0; }
static inline int libinput_event_keyboard_get_seat_key_count(struct libinput_event_keyboard *e) { return 0; }
static inline uint64_t libinput_event_keyboard_get_time_usec(struct libinput_event_keyboard *e) { return 0; }
static inline uint32_t libinput_event_keyboard_get_key(struct libinput_event_keyboard *e) { return 0; }
static inline void libinput_device_led_update(struct libinput_device *d, int l) {}
static inline void* libinput_event_keyboard_get_device(struct libinput_event_keyboard *e) { return (void*)0; }

static inline uint32_t libinput_device_config_scroll_get_methods(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_scroll_set_method(struct libinput_device *d, int m) {}
static inline int libinput_device_config_scroll_set_button(struct libinput_device *d, uint32_t b) { return 0; }
static inline uint32_t libinput_device_config_click_get_methods(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_click_set_method(struct libinput_device *d, int m) {}
static inline int libinput_device_config_tap_get_finger_count(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_tap_set_enabled(struct libinput_device *d, int e) {}
static inline void libinput_device_config_tap_set_button_map(struct libinput_device *d, int m) {}
static inline void libinput_device_config_tap_set_drag_enabled(struct libinput_device *d, int e) {}
static inline void libinput_device_config_tap_set_drag_lock_enabled(struct libinput_device *d, int e) {}
static inline void libinput_device_config_send_events_set_mode(struct libinput_device *d, int m) {}
static inline int libinput_device_config_accel_is_available(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_accel_set_speed(struct libinput_device *d, double s) {}
static inline void libinput_device_config_accel_set_profile(struct libinput_device *d, int p) {}
static inline uint32_t libinput_device_config_accel_get_profiles(struct libinput_device *d) { return 0; }
static inline int libinput_device_config_left_handed_is_available(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_left_handed_set(struct libinput_device *d, int e) {}
static inline int libinput_device_config_middle_emulation_is_available(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_middle_emulation_set_enabled(struct libinput_device *d, int e) {}
static inline int libinput_device_config_natural_scroll_is_available(struct libinput_device *d) { return 0; }
static inline int libinput_device_config_scroll_has_natural_scroll(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_scroll_set_natural_scroll_enabled(struct libinput_device *d, int e) {}
static inline int libinput_device_config_rotation_is_available(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_rotation_set_angle(struct libinput_device *d, double a) {}
static inline void libinput_device_config_calibration_set_matrix(struct libinput_device *d, const float m[6]) {}
static inline int libinput_device_config_tap_is_available(struct libinput_device *d) { return 0; }
static inline int libinput_device_config_dwt_is_available(struct libinput_device *d) { return 0; }
static inline void libinput_device_config_dwt_set_enabled(struct libinput_device *d, int e) {}
#endif
EOF

    # gbm.h already copied from ilandSrc (Mode B shared DRM)

    # Create pty.h shim
    cat > include/pty.h <<'EOF'
#ifndef _PTY_H
#define _PTY_H
#include <util.h>
#endif
EOF

    # Create values.h shim for legacy code
    cat > include/values.h <<'EOF'
#ifndef _VALUES_H
#define _VALUES_H
#include <limits.h>
#include <float.h>
#endif
EOF

    # Create endian.h shim
    cat > include/endian.h <<'EOF'
#ifndef _ENDIAN_H
#define _ENDIAN_H
#include <machine/endian.h>
#define __BYTE_ORDER BYTE_ORDER
#define __LITTLE_ENDIAN LITTLE_ENDIAN
#define __BIG_ENDIAN BIG_ENDIAN
#endif
EOF

    # Create alloca.h shim
    cat > include/alloca.h <<'EOF'
#ifndef _ALLOCA_H
#define _ALLOCA_H
#include <stdlib.h>
#endif
EOF
    
    # Inject linux/input.h shims
    cp ${linux_input_h} include/linux/input.h
    cp ${linux_input_event_codes_h} include/linux/input-event-codes.h
    cat > include/linux/ioctl.h <<'EOF'
#ifndef _LINUX_IOCTL_H
#define _LINUX_IOCTL_H
#include <sys/ioctl.h>
#endif
EOF
    
    # Create linux/types.h shim
    cat > include/linux/types.h <<'EOF'
#ifndef _LINUX_TYPES_H
#define _LINUX_TYPES_H
#include <stdint.h>
typedef uint8_t __u8;
typedef uint16_t __u16;
typedef uint32_t __u32;
typedef uint64_t __u64;
typedef int8_t __s8;
typedef int16_t __s16;
typedef int32_t __s32;
typedef int64_t __s64;
typedef uint16_t __le16;
typedef uint32_t __le32;
typedef uint64_t __le64;
typedef uint16_t __be16;
typedef uint32_t __be32;
typedef uint64_t __be64;
#define __user
#define __BITS_PER_LONG 64
#endif
EOF
    
    # Create linux/limits.h shim
    cat > include/linux/limits.h <<'EOF'
#ifndef _LINUX_LIMITS_H
#define _LINUX_LIMITS_H
#include <limits.h>
#endif
EOF
    
    # Real DRM UAPI + xf86drm headers (symbols resolved at Mode B runtime)
    cp ${libdrm_fourcc_h} include/drm_fourcc.h
    cp ${libdrm_h} include/drm.h
    cp ${libdrm_mode_h} include/drm_mode.h
    cp ${libdrm_xf86drm_h} include/xf86drm.h
    cp ${libdrm_xf86drm_mode_h} include/xf86drmMode.h
    mkdir -p include/linux
    cat > include/linux/vt.h <<'EOF'
#include <sys/ioctl.h>
EOF
    cat > include/malloc.h <<'EOF'
#include <stdlib.h>
EOF

    # Weston 13 abort()s loading wayland-backend.so if weston_log_set_handler was
    # not installed before wet_main logs "Loading module …" (default handler aborts).
    # Weston 13 moved main() to compositor/executable.c; wwn-weston-log.c installs
    # the handler from a constructor when libexec_weston loads.
    cp ${./wwn-weston-log.c} compositor/wwn-weston-log.c
    python3 <<'PY'
from pathlib import Path

meson = Path("compositor/meson.build")
text = meson.read_text()
if "'wwn-weston-log.c'" not in text:
    text = text.replace("\t'main.c',", "\t'main.c',\n\t'wwn-weston-log.c',", 1)
    meson.write_text(text)

compositor = Path("libweston/compositor.c")
text = compositor.read_text()
helper = """
static const char *
wwn_effective_module_dir(const char *module_dir)
{
	const char *backend_env;
	const char *module_env;

	if (!module_dir)
		return module_dir;

	backend_env = getenv("WESTON_BACKEND_DIR");
	module_env = getenv("WESTON_MODULE_DIR");

	if (strstr(module_dir, "libweston") != NULL) {
		if (backend_env && backend_env[0])
			return backend_env;
	} else if (strstr(module_dir, "weston") != NULL) {
		if (module_env && module_env[0])
			return module_env;
	}
	return module_dir;
}

"""
if "wwn_effective_module_dir" not in text:
    anchor = "WL_EXPORT void *\nweston_load_module(const char *name, const char *entrypoint,"
    if anchor not in text:
        raise SystemExit("libweston/compositor.c: weston_load_module anchor missing")
    text = text.replace(anchor, helper + anchor, 1)
    old = "\tvoid *module, *init;\n\tsize_t len;\n\n\tif (name == NULL)"
    new = (
        "\tvoid *module, *init;\n\tsize_t len;\n\n"
        "\tmodule_dir = wwn_effective_module_dir(module_dir);\n\n"
        "\tif (name == NULL)"
    )
    if old not in text:
        raise SystemExit("libweston/compositor.c: weston_load_module body anchor missing")
    text = text.replace(old, new, 1)
    compositor.write_text(text)

main = Path("compositor/main.c")
text = main.read_text()
old = """static char *
weston_choose_default_backend(void)
{
	char *backend = NULL;

	if (getenv("WAYLAND_DISPLAY") || getenv("WAYLAND_SOCKET"))
		backend = strdup("wayland");
	else if (getenv("DISPLAY"))
		backend = strdup("x11");
	else
		backend = strdup(WESTON_NATIVE_BACKEND);

	return backend;
}
"""
new = """static int
wwn_host_wayland_live(void)
{
	const char *sock = getenv("WAYLAND_SOCKET");
	const char *disp = getenv("WAYLAND_DISPLAY");
	const char *rt;
	char path[512];

	if (sock && sock[0])
		return 1;
	if (!disp || !disp[0])
		return 0;
	if (disp[0] == '/')
		return access(disp, F_OK) == 0;
	rt = getenv("XDG_RUNTIME_DIR");
	if (!rt || !rt[0])
		rt = "/tmp";
	if (snprintf(path, sizeof(path), "%s/%s", rt, disp) >= (int)sizeof(path))
		return 0;
	return access(path, F_OK) == 0;
}

static char *
weston_choose_default_backend(void)
{
	char *backend = NULL;
	const char *modeb;

	/* Classic session compositor: no parent Wayland. Inner weston/niri
	 * inside that compositor still nest (live WAYLAND_DISPLAY). */
	modeb = getenv("WWN_MODEB_TTY");
	if (modeb && modeb[0] && strcmp(modeb, "0") != 0 &&
	    !wwn_host_wayland_live())
		return strdup("drm");
#ifdef __APPLE__
	if (!wwn_host_wayland_live())
		return strdup("drm");
	return strdup("wayland");
#endif

	if (wwn_host_wayland_live())
		backend = strdup("wayland");
	else if (getenv("DISPLAY"))
		backend = strdup("x11");
	else
		backend = strdup(WESTON_NATIVE_BACKEND);

	return backend;
}
"""
if old not in text:
    raise SystemExit("compositor/main.c: weston_choose_default_backend anchor missing")
text = text.replace(old, new, 1)
after = """			if (!backends)
				backends = weston_choose_default_backend();
		}
	}

	wet.compositor = weston_compositor_create(display, log_ctx, &wet, test_data);
"""
force = """			if (!backends)
				backends = weston_choose_default_backend();
		}
	}
	{
		const char *modeb = getenv("WWN_MODEB_TTY");
		if (modeb && modeb[0] && strcmp(modeb, "0") != 0 &&
		    !wwn_host_wayland_live() &&
		    backends &&
		    (strcmp(backends, "wayland") == 0 ||
		     strncmp(backends, "wayland,", 8) == 0 ||
		     strcmp(backends, "x11") == 0)) {
			weston_log("Mode B TTY: using drm (iland), not "
				   "--backend=%s\\n",
				   backends);
			backends = strdup("drm");
		}
	}

	wet.compositor = weston_compositor_create(display, log_ctx, &wet, test_data);
"""
if after not in text:
    raise SystemExit("compositor/main.c: weston_choose_default_backend call missing")
text = text.replace(after, force, 1)
main.write_text(text)

print("patched macOS weston log init + bundled module dirs + Mode B DRM default")
PY
  '';

  postInstall = ''
    # Weston's module loader on macOS/Darwin still expects .so extensions for backends
    # naturally built as .dylib. Symlink them recursively to ensure they can be loaded.
    find "$out/lib" -name "*.dylib" | while read f; do
      if [ -f "$f" ]; then
        ln -s "$(basename "$f")" "''${f%.dylib}.so"
      fi
    done

    echo "Verifying required Weston client binaries..."
    missing=0
    for id in weston weston-terminal weston-simple-shm \
              weston-flower weston-clickdot weston-smoke weston-eventdemo \
              weston-resizor weston-cliptest weston-transformed weston-stacking \
              weston-dnd weston-image weston-scaler weston-editor weston-constraints; do
      if [ -f "$out/bin/$id" ]; then
        echo "✓ $id"
      else
        echo "ERROR: missing $out/bin/$id" >&2
        missing=1
      fi
    done
    if [ ! -f "$out/bin/weston-simple-egl" ]; then
      echo "○ weston-simple-egl (optional GL client, not built on macOS meson)"
    fi
    [ "$missing" -eq 0 ] || exit 1

    echo "Verifying shared DRM/GL backends for Mode B fork/exec..."
    missing_be=0
    for f in drm-backend.so gl-renderer.so wayland-backend.so headless-backend.so; do
      found=$(find "$out/lib" -name "$f" 2>/dev/null | head -1)
      if [ -n "$found" ]; then
        echo "OK $f ($found)"
      else
        echo "ERROR: missing shared backend $f under $out/lib" >&2
        missing_be=1
      fi
    done
    if [ "$missing_be" -ne 0 ]; then
      find "$out/lib" -type f \( -name '*backend*' -o -name '*renderer*' \) 2>/dev/null || true
      exit 1
    fi

    # Nested GL weston creates wl_egl_window via LC_LOAD libwayland-egl. The
    # toolchain dylib is the vendor stub (geometry only, no iland magic).
    # iland's wl_egl_window_* live in libEGL.dylib (force_load of
    # libiland_wayland_egl.a). niri already remaps that load. Without this,
    # eglCreateWindowSurface treats the stub window as a gbm_surface and
    # SIGBUS in gbm_surface_get_write_bo (GPU carveout).
    echo "Remapping libwayland-egl -> @rpath/libEGL.dylib (iland Wayland-EGL)..."
    find "$out/lib" "$out/bin" -type f \( -name '*.dylib' -o -name '*.so' \) | while read -r f; do
      old=$(otool -L "$f" 2>/dev/null | awk '/libwayland-egl/{print $1; exit}')
      if [ -n "$old" ] && [ "$old" != "@rpath/libEGL.dylib" ]; then
        echo "  $f: $old"
        install_name_tool -change "$old" @rpath/libEGL.dylib "$f"
      fi
    done
    wb=$(find "$out/lib" -name 'wayland-backend.dylib' | head -1)
    if [ -z "$wb" ]; then
      echo "ERROR: wayland-backend.dylib missing after remap" >&2
      exit 1
    fi
    if otool -L "$wb" | grep -q libwayland-egl; then
      echo "ERROR: $wb still LC_LOADs libwayland-egl" >&2
      otool -L "$wb" >&2
      exit 1
    fi
    if ! otool -L "$wb" | grep -q 'libEGL.dylib'; then
      echo "ERROR: $wb does not LC_LOAD libEGL.dylib" >&2
      otool -L "$wb" >&2
      exit 1
    fi
    echo "OK wayland-backend uses @rpath/libEGL.dylib"
  '';

  meta = with lib; {
    description = "Weston macOS client + shared drm-backend/gl-renderer for Mode B";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
