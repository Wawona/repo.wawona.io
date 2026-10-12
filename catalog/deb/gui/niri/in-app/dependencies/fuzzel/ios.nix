# fuzzel - Wayland-native application launcher (niri's Mod+D launcher)
# Apple mobile: static libfuzzel.a exposing fuzzel_main for in-process spawn.
# https://codeberg.org/dnkl/fuzzel
{
  lib,
  pkgs,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
  xcodeUtils ? iosToolchain,
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

  linuxInputHeaders = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/45dcf5e28813954da4150e7260ccb61e95856176/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-CqF1r2sCoJbn3Bcr0x6B1JnrqQg3d1FejCCqkVq3new=";
  };

  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  pixman = buildModule.buildForIOS "pixman" { inherit simulator; };
  xkbcommon = buildModule.buildForIOS "xkbcommon" { inherit simulator; };
  fcft = buildModule.buildForIOS "fcft" { inherit simulator; };
  tllist = buildModule.buildForIOS "tllist" { inherit simulator; };
  fontconfig = buildModule.buildForIOS "fontconfig" { inherit simulator; };
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  expat = buildModule.buildForIOS "expat" { inherit simulator; };
  epoll-shim = buildModule.buildForIOS "epoll-shim" { inherit simulator; };
  libpng = buildModule.buildForIOS "libpng" { inherit simulator; };
  libffi = buildModule.buildForIOS "libffi" { inherit simulator; };
  pcDirs = dep: [
    "${dep}/lib/pkgconfig"
    "${dep}/libdata/pkgconfig"
  ];
  pcPath = lib.concatMapStringsSep ":" (dep: lib.concatStringsSep ":" (pcDirs dep)) [
    libwayland pixman xkbcommon fcft tllist fontconfig freetype expat libpng epoll-shim
  ];
  # Build-machine pkg-config (wayland-scanner.pc); must not use pkgs.wayland on Darwin.
  buildPcPath = "${libwayland}/share/pkgconfig";
in
pkgs.stdenv.mkDerivation {
  pname = "fuzzel";
  version = "1.14.1";
  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    scdoc
  ];

  buildInputs = [
    libwayland
    pixman
    xkbcommon
    fcft
    tllist
    fontconfig
    freetype
    expat
    libpng
    pkgs.wayland-protocols
  ];

  __noChroot = true;

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; }}
    export IOS_SDK="$SDKROOT"
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export PKG_CONFIG_PATH="${buildPcPath}:${pcPath}:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1

    _CC="$XCODE_CLANG"
    _CXX="$XCODE_CLANGXX"
    _SDK="$SDKROOT"
    _ARCH="$IOS_ARCH"
    _DEPLOY="$APPLE_DEPLOYMENT_FLAG"
    _TARGET="$APPLE_LINKER_TARGET"

    cat > ios-cross.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
c_for_build = '${pkgs.clang}/bin/clang'
cpp_for_build = '${pkgs.clang}/bin/clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = 'pkg-config'
wayland-scanner = '${libwayland}/bin/wayland-scanner'

[build_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
objc_args = ['-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-fobjc-arc']
objcpp_args = ['-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-fobjc-arc']
c_args = ['-include', '$(pwd)/compat/fuzzel-itimerspec.h', '-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-I$(pwd)/compat', '-I${epoll-shim}/include/libepoll-shim', '-D__STDC_ISO_10646__=201103L', '-Wno-deprecated-declarations', '-DSIGRTMAX=32']
c_link_args = ['-arch', '$_ARCH', '-target', '$_TARGET', '-isysroot', '$_SDK', '$_DEPLOY', '-L${epoll-shim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
needs_exe_wrapper = true
EOF

    cat > ios-native.txt <<EOF
[binaries]
pkgconfig = 'pkg-config'

[built-in options]
pkg_config_path = ['${buildPcPath}']
EOF
  '';

  dontUseMesonConfigure = true;

  buildPhase = ''
    runHook preBuild
    export PKG_CONFIG_PATH="${buildPcPath}:${pcPath}:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1
    unset SDKROOT
    meson setup build --prefix=$out --cross-file=ios-cross.txt --native-file=ios-native.txt \
      -Denable-cairo=disabled \
      -Dpng-backend=libpng \
      -Dsvg-backend=nanosvg \
      --buildtype=plain
    meson compile -C build
    runHook postBuild
  '';

  postPatch = ''
    mkdir -p compat/linux compat/sys

    cp ${linuxInputHeaders} compat/linux/input-event-codes.h

    cat > compat/uchar.h << 'EOF'
#ifndef FUZZEL_UCHAR_H_COMPAT
#define FUZZEL_UCHAR_H_COMPAT
#include <stdint.h>
#include <wchar.h>
typedef uint_least16_t char16_t;
typedef uint_least32_t char32_t;
static inline size_t c32rtomb(char *s, char32_t c32, mbstate_t *ps) {
    (void)ps;
    if (c32 < 0x80) { if (s) s[0] = (char)c32; return 1; }
    if (c32 < 0x800) {
        if (s) { s[0] = 0xC0 | (c32 >> 6); s[1] = 0x80 | (c32 & 0x3F); }
        return 2;
    }
    if (c32 < 0x10000) {
        if (s) { s[0] = 0xE0 | (c32 >> 12); s[1] = 0x80 | ((c32 >> 6) & 0x3F); s[2] = 0x80 | (c32 & 0x3F); }
        return 3;
    }
    if (s) {
        s[0] = 0xF0 | (c32 >> 18); s[1] = 0x80 | ((c32 >> 12) & 0x3F);
        s[2] = 0x80 | ((c32 >> 6) & 0x3F); s[3] = 0x80 | (c32 & 0x3F);
    }
    return 4;
}
static inline size_t mbrtoc32(char32_t *pc32, const char *s, size_t n, mbstate_t *ps) {
    (void)ps;
    if (!s || n == 0) return 0;
    unsigned char c = (unsigned char)s[0];
    if (c < 0x80) { if (pc32) *pc32 = c; return c ? 1 : 0; }
    if ((c & 0xE0) == 0xC0 && n >= 2) {
        if (pc32) *pc32 = ((c & 0x1F) << 6) | (s[1] & 0x3F);
        return 2;
    }
    if ((c & 0xF0) == 0xE0 && n >= 3) {
        if (pc32) *pc32 = ((c & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F);
        return 3;
    }
    if ((c & 0xF8) == 0xF0 && n >= 4) {
        if (pc32) *pc32 = ((c & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F);
        return 4;
    }
    return (size_t)-1;
}
#endif
EOF

    cat > compat/threads.h << 'EOF'
#ifndef FUZZEL_THREADS_H_COMPAT
#define FUZZEL_THREADS_H_COMPAT
#include <pthread.h>
#include <errno.h>
#include <time.h>
#include <sched.h>
typedef pthread_t thrd_t;
typedef pthread_mutex_t mtx_t;
typedef pthread_cond_t cnd_t;
typedef pthread_once_t once_flag;
typedef pthread_key_t tss_t;
typedef void (*tss_dtor_t)(void *);
typedef int (*thrd_start_t)(void *);
enum { thrd_success = 0, thrd_nomem = ENOMEM, thrd_timedout = ETIMEDOUT, thrd_busy = EBUSY, thrd_error = -1 };
enum { mtx_plain = 0, mtx_recursive = 1, mtx_timed = 2 };
#define ONCE_FLAG_INIT PTHREAD_ONCE_INIT
static inline int thrd_create(thrd_t *thr, thrd_start_t func, void *arg) {
    return pthread_create(thr, NULL, (void *(*)(void *))func, arg) == 0 ? thrd_success : thrd_error;
}
static inline int thrd_join(thrd_t thr, int *res) {
    void *retval;
    int r = pthread_join(thr, &retval);
    if (res) *res = (int)(intptr_t)retval;
    return r == 0 ? thrd_success : thrd_error;
}
static inline thrd_t thrd_current(void) { return pthread_self(); }
static inline int thrd_equal(thrd_t a, thrd_t b) { return pthread_equal(a, b); }
static inline void thrd_yield(void) { sched_yield(); }
static inline int mtx_init(mtx_t *mtx, int type) {
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    if (type & mtx_recursive) pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    int r = pthread_mutex_init(mtx, &attr);
    pthread_mutexattr_destroy(&attr);
    return r == 0 ? thrd_success : thrd_error;
}
static inline int mtx_lock(mtx_t *mtx) { return pthread_mutex_lock(mtx) == 0 ? thrd_success : thrd_error; }
static inline int mtx_unlock(mtx_t *mtx) { return pthread_mutex_unlock(mtx) == 0 ? thrd_success : thrd_error; }
static inline int mtx_trylock(mtx_t *mtx) {
    int r = pthread_mutex_trylock(mtx);
    if (r == 0) return thrd_success;
    if (r == EBUSY) return thrd_busy;
    return thrd_error;
}
static inline void mtx_destroy(mtx_t *mtx) { pthread_mutex_destroy(mtx); }
static inline int cnd_init(cnd_t *cnd) { return pthread_cond_init(cnd, NULL) == 0 ? thrd_success : thrd_error; }
static inline int cnd_signal(cnd_t *cnd) { return pthread_cond_signal(cnd) == 0 ? thrd_success : thrd_error; }
static inline int cnd_broadcast(cnd_t *cnd) { return pthread_cond_broadcast(cnd) == 0 ? thrd_success : thrd_error; }
static inline int cnd_wait(cnd_t *cnd, mtx_t *mtx) { return pthread_cond_wait(cnd, mtx) == 0 ? thrd_success : thrd_error; }
static inline void cnd_destroy(cnd_t *cnd) { pthread_cond_destroy(cnd); }
static inline void call_once(once_flag *flag, void (*func)(void)) { pthread_once(flag, func); }
static inline int tss_create(tss_t *key, tss_dtor_t dtor) { return pthread_key_create(key, dtor) == 0 ? thrd_success : thrd_error; }
static inline void *tss_get(tss_t key) { return pthread_getspecific(key); }
static inline int tss_set(tss_t key, void *val) { return pthread_setspecific(key, val) == 0 ? thrd_success : thrd_error; }
static inline void tss_delete(tss_t key) { pthread_key_delete(key); }
#endif
EOF

    # epoll-shim's timerfd.h only forward-declares itimerspec; force full struct
    # before any translation unit (meson puts epoll-shim includes ahead of compat/).
    cat > compat/fuzzel-itimerspec.h << 'EOF'
#ifndef FUZZEL_ITIMERSPEC_H
#define FUZZEL_ITIMERSPEC_H
#include <time.h>
#ifndef _STRUCT_ITIMERSPEC
struct itimerspec { struct timespec it_interval; struct timespec it_value; };
#define _STRUCT_ITIMERSPEC
#endif
#endif
EOF

    cat > compat/pthread.h << 'EOF'
#ifndef FUZZEL_PTHREAD_H_COMPAT
#define FUZZEL_PTHREAD_H_COMPAT
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <pthread.h>
#pragma clang diagnostic pop
#ifdef __APPLE__
#define pthread_setname_np(thread, name) pthread_setname_np(name)
#endif
#endif
EOF

    cat > compat/semaphore.h << 'EOF'
#ifndef FUZZEL_SEMAPHORE_H_COMPAT
#define FUZZEL_SEMAPHORE_H_COMPAT
#include <pthread.h>
#include <errno.h>
#include <time.h>
typedef struct { pthread_mutex_t mutex; pthread_cond_t cond; unsigned int value; } sem_t;
#define SEM_FAILED ((sem_t *)0)
static inline int sem_init(sem_t *sem, int pshared, unsigned int value) {
    if (pshared) { errno = ENOSYS; return -1; }
    sem->value = value;
    pthread_mutex_init(&sem->mutex, NULL);
    pthread_cond_init(&sem->cond, NULL);
    return 0;
}
static inline int sem_destroy(sem_t *sem) {
    pthread_mutex_destroy(&sem->mutex);
    pthread_cond_destroy(&sem->cond);
    return 0;
}
static inline int sem_wait(sem_t *sem) {
    pthread_mutex_lock(&sem->mutex);
    while (sem->value == 0) pthread_cond_wait(&sem->cond, &sem->mutex);
    sem->value--;
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}
static inline int sem_trywait(sem_t *sem) {
    int ret = 0;
    pthread_mutex_lock(&sem->mutex);
    if (sem->value > 0) sem->value--;
    else { errno = EAGAIN; ret = -1; }
    pthread_mutex_unlock(&sem->mutex);
    return ret;
}
static inline int sem_post(sem_t *sem) {
    pthread_mutex_lock(&sem->mutex);
    sem->value++;
    pthread_cond_signal(&sem->cond);
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}
#endif
EOF

    cat > compat/sys/timerfd.h << 'EOF'
#ifndef FUZZEL_SYS_TIMERFD_H_COMPAT
#define FUZZEL_SYS_TIMERFD_H_COMPAT
#include <time.h>
#ifndef _STRUCT_ITIMERSPEC
struct itimerspec { struct timespec it_interval; struct timespec it_value; };
#define _STRUCT_ITIMERSPEC
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <sys/timerfd.h>
#pragma clang diagnostic pop
#endif
EOF

    cat > compat/sys/socket.h << 'EOF'
#ifndef FUZZEL_SYS_SOCKET_H_COMPAT
#define FUZZEL_SYS_SOCKET_H_COMPAT
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <sys/socket.h>
#pragma clang diagnostic pop
#include <fcntl.h>
#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0x10000000
#endif
#ifndef SOCK_NONBLOCK
#define SOCK_NONBLOCK 0x20000000
#endif
#ifdef __APPLE__
static inline int fuzzel_socket_compat(int domain, int type, int protocol) {
    int real_type = type;
    int flags = 0;
    if (type & SOCK_CLOEXEC) { real_type &= ~SOCK_CLOEXEC; flags |= FD_CLOEXEC; }
    int fd = (socket)(domain, real_type, protocol);
    if (fd < 0) return -1;
    if (flags & FD_CLOEXEC) fcntl(fd, F_SETFD, FD_CLOEXEC);
    if (type & SOCK_NONBLOCK) {
        int fl = fcntl(fd, F_GETFL);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    }
    return fd;
}
#define socket fuzzel_socket_compat
#endif
#endif
EOF

    cat > compat/unistd.h << 'EOF'
#ifndef FUZZEL_UNISTD_H_COMPAT
#define FUZZEL_UNISTD_H_COMPAT
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <unistd.h>
#pragma clang diagnostic pop
#include <fcntl.h>
#ifdef __APPLE__
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
#endif
#endif
EOF

    cat > compat/stdlib.h << 'EOF'
#ifndef FUZZEL_STDLIB_H_COMPAT
#define FUZZEL_STDLIB_H_COMPAT
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu-include-next"
#include_next <stdlib.h>
#pragma clang diagnostic pop
#ifdef __APPLE__
static inline void *reallocarray(void *ptr, size_t nmemb, size_t size) {
    if (nmemb && size > SIZE_MAX / nmemb) return NULL;
    return realloc(ptr, nmemb * size);
}
#endif
#endif
EOF

    MACOS_COMPAT=$(cat <<'EOF'
#ifdef __APPLE__
#include <sys/types.h>
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
#endif
EOF
)
    for f in wayland.c render.c main.c shm.c; do
      if [ -f "$f" ]; then
        printf '%s\n' "$MACOS_COMPAT" | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      fi
    done
    if [ -f main.c ]; then
      sed -i '1i#define main fuzzel_main' main.c
    fi
    # Static iOS lib only; skip scdoc man-page generation (no .pc in nixpkgs scdoc).
    if [ -f meson.build ]; then
      sed -i "s/subdir('doc')/# iOS: skip man pages/" meson.build
      sed -i "/^  'main.c',$/a\\
  'fuzzel-link-stub.c'," meson.build
    fi
    cat > fuzzel-link-stub.c << 'EOF'
/* Satisfy meson executable link; main.c defines fuzzel_main instead of main.
 * Weak dispatch stubs: the real implementations live in libwwn-pty when the
 * archive is force-loaded into the Wawona app. */
extern int fuzzel_main(int argc, char *argv[]);
int main(int argc, char *argv[]) { return fuzzel_main(argc, argv); }

__attribute__((weak)) int wawona_dispatch_can_handle(const char *argv0) {
  (void)argv0;
  return 0;
}
__attribute__((weak)) int wawona_dispatch_spawn_async(const char *path,
                                                      char *const argv[],
                                                      char *const envp[]) {
  (void)path;
  (void)argv;
  (void)envp;
  return -1;
}
EOF
    # App Store: replace fork+exec launch with wawona_dispatch_spawn_async.
    patch -p1 < ${./wawona-ios-launch.patch}
    # Nested compositor HUP: skip wl_* destroys (else wl_closure_send SEGV).
    patch -p1 < ${./wawona-safe-wayland-teardown.patch}
  '';

  # Package every compiled object into a single static archive for in-process
  # linking (App Store: no fork/exec of a bundled fuzzel binary).
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    # Omit only Wayland protocol stubs that weston already exports in the Wawona
    # iOS link; keep fuzzel-specific protocols (layer-shell, color-mgmt, etc.).
    OBJS=$(find build -name '*.o' -type f \
      ! -name 'fuzzel-link-stub.c.o' \
      ! -path '*/meson-generated_.._xdg-shell.c.o' \
      ! -path '*/meson-generated_.._viewporter.c.o' \
      ! -path '*/meson-generated_.._tablet-unstable-v2.c.o' \
      ! -path '*/meson-generated_.._fractional-scale-v1.c.o' \
      | sort)
    if [ -z "$OBJS" ]; then
      echo "ERROR: no fuzzel object files under build/" >&2
      find build -type f | head -50 >&2 || true
      exit 1
    fi
    $AR rcs $out/lib/libfuzzel.a $OBJS
    if ! nm build/fuzzel.p/main.c.o 2>/dev/null | grep -q ' _fuzzel_main$'; then
      echo "ERROR: fuzzel main object missing fuzzel_main symbol" >&2
      nm build/fuzzel.p/main.c.o 2>/dev/null | grep -i main | head -20 >&2 || true
      exit 1
    fi
    runHook postInstall
  '';

  meta = with lib; {
    description = "Wayland-native application launcher for niri (Apple mobile staticlib)";
    homepage = "https://codeberg.org/dnkl/fuzzel";
    license = with licenses; [ mit zlib ];
  };
}
