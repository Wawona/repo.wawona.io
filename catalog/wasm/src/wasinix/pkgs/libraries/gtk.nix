# GTK / WASIX closure (wwn-gtk wasm lane).
#
# Ports the nixpkgs wasi-cross nodes onto the WASIX toolchain (wasixcc + WASIX
# sysroot). Plain wasi-libc is not enough: it has no signals/threads/fork, and
# the raw pkgsCross.wasix build dies in libffi (Emscripten ffi.c) and epoll-shim
# ("wasm lacks signal support"). WASIX implements those, so this is the lane.
#
# Phase 1 (this file, now): glib + libwayland-client.
# Phase 2: pixman/cairo/harfbuzz/fribidi/fontconfig/pango/gdk-pixbuf/graphene.
# Phase 3: gtk4 (GDK Wayland + GSK cairo).
#
# Dependency overrides use the wasinix `self` set so the entire closure is
# built with one toolchain. Do not mix nixpkgs-wasi objects into WASIX objects.
{
  pkgs,
  pkgsCross,
  self,
  mkUpstreamLibrary,
}: let
  # Upstream libffi 3.5.x has only an Emscripten wasm backend (EM_JS/HEAPU8),
  # which cannot exist on WASIX. wasix-org/libffi carries a real src/wasm32
  # backend (configure.host maps wasm32-*-* -> TARGETDIR=wasm32).
  libffiSrc = pkgs.fetchFromGitHub {
    owner = "wasix-org";
    repo = "libffi";
    rev = "09cbf7d66d232a01dbb0c88fd5ae65fa9c15f7c7";
    hash = "sha256-6xayw5iBCCXxTM37+1RmFdxptvgcrKlxOqjaMyBb16I=";
  };

  # Build-machine compiler description for meson, so packages that need a
  # native generator compilable for x86_64 (e.g. harfbuzz) can find one
  # while the host compiler stays wasixcc.
  nativeFile = pkgs.writeText "wasix-native.ini" ''
    [binaries]
    c = '${pkgs.buildPackages.stdenv.cc}/bin/cc'
    cpp = '${pkgs.buildPackages.stdenv.cc}/bin/c++'
    ar = '${pkgs.buildPackages.stdenv.cc}/bin/ar'
    strip = '${pkgs.buildPackages.stdenv.cc}/bin/strip'
  '';

  # Khronos EGL headers. libepoxy and GTK4's Wayland backend include
  # <EGL/egl.h> / <EGL/eglplatform.h>, which wasi does not provide. Use the
  # registry headers with EGL_NO_PLATFORM_SPECIFIC_TYPES (void* natives).
  eglRegistry = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "EGL-Registry";
    rev = "db3425b8246136faccb5e2782b5694960bd6edf1";
    hash = "sha256-P9whusrQkDWZpwaBnroDimsxORkwNJMFrfZcwvxMbvE=";
  };

  # wasi has no <linux/input.h>; GTK4's Wayland backend needs the button
  # codes from it.
  wasixLinuxInput = pkgs.runCommand "wasix-linux-input" {} ''
    mkdir -p $out/include/linux
    cp ${./wasix-linux-input.h} $out/include/linux/input.h
  '';

  # Inert librsvg headers so GTK4's SVG texture path compiles without the
  # real Rust librsvg; the functions are static inline no-ops.
  librsvgStubHeaders = pkgs.writeTextDir "librsvg/rsvg.h" (builtins.readFile ./librsvg-stub.h);

  # wasi lacks ftw(); gtk4-update-icon-cache needs it.
  wasixFtwShim = pkgs.writeText "wasix-ftw.h" (builtins.readFile ./wasix-ftw.h);

  # A small wasm compat library: ppoll (wayland) and dlopen/dlsym/dlerror
  # (libepoxy). Built with the wasix toolchain.
  wasixCompat = mkUpstreamLibrary {
    package = pkgsCross.stdenv.mkDerivation {
      pname = "wasix-compat";
      version = "1";
      dontUnpack = true;
      buildPhase = ''
        runHook preBuild
        $CC -O2 -fPIC -c ${./wasix-compat.c} -o wasix-compat.o
        $AR rcs libwasix-compat.a wasix-compat.o
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib
        cp libwasix-compat.a $out/lib/
        runHook postInstall
      '';
    };
    doCheck = false;
  };

  # Wawona Wasm Wayland transport (guest side of the fd bridge): --wrap shims
  # that route libwayland's connect/sendmsg/recvmsg/poll/close through the
  # host `wawona_wayland_*` / `wawona_socket_*` imports.
  wasixWawonaWayland = mkUpstreamLibrary {
    package = pkgsCross.stdenv.mkDerivation {
      pname = "wawona-wayland";
      version = "1";
      dontUnpack = true;
      buildPhase = ''
        runHook preBuild
        $CC -O2 -fPIC -c ${./wawona-wayland.c} -o wawona-wayland.o
        $AR rcs libwawona-wayland.a wawona-wayland.o
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib
        cp libwawona-wayland.a $out/lib/
        runHook postInstall
      '';
    };
    doCheck = false;
  };
in {
  inherit wasixCompat wasixWawonaWayland;

  libffi = mkUpstreamLibrary {
    package = pkgsCross.libffi.overrideAttrs (old: {
      src = libffiSrc;
      patches = [];
      postPatch = "";
      postFixup =
        (old.postFixup or "")
        + ''
                  echo "WASIX-FFI out=$(ls "$out/lib" 2>/dev/null | tr '\n' ' ') dev=$(ls "$dev/lib" 2>/dev/null | tr '\n' ' ')" >&2
                  for f in $(find . "$dev" "$out" -name '*.a' 2>/dev/null); do
                    cp -a "$f" "$out/lib/" 2>/dev/null || true
                    cp -a "$f" "$dev/lib/" 2>/dev/null || true
                  done
                  if [ ! -e "$out/lib/libffi.a" ] && [ ! -e "$dev/lib/libffi.a" ]; then
                    echo "WASIX-FFI WARNING: no archive in out/dev" >&2
                  fi
                  mkdir -p "$dev/lib/pkgconfig"
                  cat > "$dev/lib/pkgconfig/libffi.pc" <<EOF
          prefix=$out
          exec_prefix=$out
          libdir=$dev/lib
          includedir=$dev/include

          Name: libffi
          Description: Library supporting Foreign Function Interfaces
          Version: ${old.version}
          Libs: -L$dev/lib -L$out/lib -lffi
          Cflags: -I$dev/include
          EOF
        '';
    });
    extraNativeBuildInputs = [pkgs.autoreconfHook pkgs.texinfo];
    doCheck = false;
  };

  # pcre2 always builds pcre2grep; the fork() is in its callout support. The
  # real options are --disable-pcre2grep-callout{,-fork} (there is no
  # --disable-pcre2grep). glib only needs libpcre2 anyway.
  pcre2 = mkUpstreamLibrary {
    package = pkgsCross.pcre2;
    doCheck = false;
    configureFlags = [
      "--disable-pcre2grep-callout"
      "--disable-pcre2grep-callout-fork"
    ];
  };

  expat = mkUpstreamLibrary {
    package = pkgsCross.expat;
    doCheck = false;
  };

  # libwayland-client + libwayland-server. nixpkgs drags in epoll-shim for any
  # non-Linux host, but WASIX provides epoll and its epoll-shim build dies on
  # wasi-libc signals, so force the argument to an empty derivation. The
  # Wayland fd/SCM_RIGHTS bridge to the Wawona compositor is a separate
  # host-ABI concern (wwn-wasm).
  wayland = mkUpstreamLibrary {
    package = pkgsCross.wayland.override {
      epoll-shim = pkgs.emptyDirectory;
      libffi = self.libffi;
    };
    doCheck = false;
    # The wasm-EH headers hide struct cmsghdr/SCM_RIGHTS and fork(). Expose
    # just those via a force-included compat header; the full
    # __wasilibc_unmodified_upstream mode wants a missing bits/errno.h.
    preConfigure = ''
      cat > "$PWD/wasix-compat.h" <<'EOF'
      #include <sys/types.h>
      #include <sys/socket.h>
      #ifndef CMSG_LEN
      struct cmsghdr { socklen_t cmsg_len; int cmsg_level; int cmsg_type; };
      #define __WASIX_CMSG_ALIGN(len) (((len) + sizeof(size_t) - 1) & (size_t) ~(sizeof(size_t) - 1))
      #define CMSG_ALIGN(len) __WASIX_CMSG_ALIGN(len)
      #define CMSG_SPACE(len) (CMSG_ALIGN(len) + CMSG_ALIGN(sizeof(struct cmsghdr)))
      #define CMSG_LEN(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
      #define CMSG_DATA(cmsg) ((unsigned char *)(((struct cmsghdr *)(cmsg)) + 1))
      #define __WASIX_CMSG_LEN(cmsg) (((cmsg)->cmsg_len + sizeof(long) - 1) & ~(long)(sizeof(long) - 1))
      #define __WASIX_CMSG_NEXT(cmsg) ((unsigned char *)(cmsg) + __WASIX_CMSG_LEN(cmsg))
      #define __WASIX_MHDR_END(mhdr) ((unsigned char *)(mhdr)->msg_control + (mhdr)->msg_controllen)
      #define CMSG_FIRSTHDR(mhdr) ((size_t)(mhdr)->msg_controllen >= sizeof(struct cmsghdr) ? (struct cmsghdr *)(mhdr)->msg_control : (struct cmsghdr *)0)
      #define CMSG_NXTHDR(mhdr, cmsg) ((cmsg)->cmsg_len < sizeof(struct cmsghdr) || __WASIX_CMSG_LEN(cmsg) + sizeof(struct cmsghdr) >= __WASIX_MHDR_END(mhdr) - (unsigned char *)(cmsg) ? 0 : (struct cmsghdr *)__WASIX_CMSG_NEXT(cmsg))
      #endif
      #ifndef SCM_RIGHTS
      #define SCM_RIGHTS 0x01
      #endif
      #ifndef SOL_SOCKET
      #define SOL_SOCKET 1
      #endif
      pid_t fork(void);
      pid_t _Fork(int);
      EOF
      export CFLAGS="-include $PWD/wasix-compat.h ''${CFLAGS:-}"
    '';
    postPatch = ''
      # Client-only port: libwayland-server needs signalfd/timerfd (absent on
      # WASIX) and GTK only needs libwayland-client.
      sed -i "/{ 'header': 'sys\/signalfd.h'/d; /{ 'header': 'sys\/timerfd.h'/d" meson.build
      sed -i '/^\twayland_server = library(/,/^\twayland_client = library(/ { /^\twayland_client = library(/!d }' src/meson.build
      # WASIX lacks PF_LOCAL; AF_UNIX is the same value.
      sed -i 's/PF_LOCAL/AF_UNIX/' src/wayland-client.c
      # No SO_PEERCRED on WASIX; return -1 instead of a #error.
      sed -i 's|#error "Don.t know how to read ucred on this platform"|int wl_os_socket_peercred(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid) { (void)sockfd; (void)uid; (void)gid; (void)pid; return -1; }|' src/wayland-os.c
    '';
    overrideAttrs = old: {
      mesonFlags =
        (old.mesonFlags or [])
        ++ [
          "-Dtests=false"
          "-Ddocumentation=false"
          "-Ddtd_validation=false"
        ];
    };
  };

  wayland-protocols = mkUpstreamLibrary {
    package = pkgsCross.wayland-protocols;
    doCheck = false;
  };

  # GLib is the keystone: GObject/GIO/GThread. No introspection, docs, selinux,
  # libmount, sysprof or NLS. Target `gettext`/`libiconv`/`bash`/`gnum4` pull a
  # broken wasi cross closure, so host-build them or drop them; WASIX provides
  # iconv and glib only needs gettext for NLS.
  glib = mkUpstreamLibrary {
    package = pkgsCross.glib.override {
      libffi = self.libffi;
      pcre2 = self.pcre2;
      zlib = self.zlib;
      bash = pkgs.buildPackages.bash;
      gnum4 = pkgs.buildPackages.gnum4;
      gettext = pkgs.buildPackages.gettext;
      # -Dsysprof=disabled, so never build the target sysprof capture lib.
      libsysprof-capture = pkgs.emptyDirectory;
    };
    doCheck = false;
    # fork() is hidden by the wasm-EH headers; expose it (and _Fork) via a
    # force-included compat header.
    preConfigure = ''
      mkdir -p "$PWD/wasix-include"
      cat > "$PWD/wasix-compat.h" <<'EOF'
      #include <sys/types.h>
      #include <sys/socket.h>
      #ifndef CMSG_LEN
      struct cmsghdr { socklen_t cmsg_len; int cmsg_level; int cmsg_type; };
      #define __WASIX_CMSG_ALIGN(len) (((len) + sizeof(size_t) - 1) & (size_t) ~(sizeof(size_t) - 1))
      #define CMSG_ALIGN(len) __WASIX_CMSG_ALIGN(len)
      #define CMSG_SPACE(len) (CMSG_ALIGN(len) + CMSG_ALIGN(sizeof(struct cmsghdr)))
      #define CMSG_LEN(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
      #define CMSG_DATA(cmsg) ((unsigned char *)(((struct cmsghdr *)(cmsg)) + 1))
      #define __WASIX_CMSG_LEN(cmsg) (((cmsg)->cmsg_len + sizeof(long) - 1) & ~(long)(sizeof(long) - 1))
      #define __WASIX_CMSG_NEXT(cmsg) ((unsigned char *)(cmsg) + __WASIX_CMSG_LEN(cmsg))
      #define __WASIX_MHDR_END(mhdr) ((unsigned char *)(mhdr)->msg_control + (mhdr)->msg_controllen)
      #define CMSG_FIRSTHDR(mhdr) ((size_t)(mhdr)->msg_controllen >= sizeof(struct cmsghdr) ? (struct cmsghdr *)(mhdr)->msg_control : (struct cmsghdr *)0)
      #define CMSG_NXTHDR(mhdr, cmsg) ((cmsg)->cmsg_len < sizeof(struct cmsghdr) || __WASIX_CMSG_LEN(cmsg) + sizeof(struct cmsghdr) >= __WASIX_MHDR_END(mhdr) - (unsigned char *)(cmsg) ? 0 : (struct cmsghdr *)__WASIX_CMSG_NEXT(cmsg))
      #endif
      #ifndef SCM_RIGHTS
      #define SCM_RIGHTS 0x01
      #endif
      #ifndef SOL_SOCKET
      #define SOL_SOCKET 1
      #endif
      pid_t fork(void);
      pid_t _Fork(int);
      /* WASIX has no xattr; declare so GIO compiles (stubs at link). */
      int setxattr(const char *, const char *, const void *, size_t, int);
      int lsetxattr(const char *, const char *, const void *, size_t, int);
      int removexattr(const char *, const char *);
      int lremovexattr(const char *, const char *);
      ssize_t getxattr(const char *, const char *, void *, size_t);
      ssize_t lgetxattr(const char *, const char *, void *, size_t);
      ssize_t fgetxattr(int, const char *, void *, size_t);
      int fsetxattr(int, const char *, const void *, size_t, int);
      int fremovexattr(int, const char *);
      ssize_t flistxattr(int, char *, size_t);
      ssize_t listxattr(const char *, char *, size_t);
      ssize_t llistxattr(const char *, char *, size_t);
      EOF
      # WASIX ships libresolv.a but no resolv.h; glib only needs res_query.
      cat > "$PWD/wasix-include/resolv.h" <<'EOF'
      #ifndef _WASIX_RESOLV_H
      #define _WASIX_RESOLV_H
      #include <sys/types.h>
      int res_query(const char *, int, int, unsigned char *, int);
      int res_search(const char *, int, int, unsigned char *, int);
      int dn_expand(const unsigned char *, const unsigned char *, const unsigned char *, char *, int);
      #endif
      EOF
      export CFLAGS="-include $PWD/wasix-compat.h -I$PWD/wasix-include ''${CFLAGS:-}"
    '';
    preBuild = ''
      # wasm-ld has no --start-group; meson emits it for every tool link.
      find . -name build.ninja -exec sed -i 's/--start-group//g; s/--end-group//g' {} +
    '';
    postPatch = ''
            # WASIX has no getxattr/libxattr; glib guards xattr use on HAVE_XATTR.
            substituteInPlace meson.build \
              --replace-fail "error('No getxattr implementation found in C library or libxattr')" "message('WASIX: xattr unavailable; disabling')" \
              --replace-fail "glib_conf.set('HAVE_XATTR', 1)" "# WASIX: xattr disabled"
            # WASIX has no res_query(); skip the configure hard-fail and provide a
            # failing stub so GIO links. getaddrinfo-based name lookup still works.
            substituteInPlace gio/meson.build \
              --replace-fail "error('Could not find res_query()')" "message('WASIX: res_query unavailable; using stub')"
            cat >> gio/gthreadedresolver.c <<'EOF'

      /* WASIX: no res_query/dn_expand in libc; failing stubs so GIO links. */
      int res_query (const char *dname, int class, int type, unsigned char *answer, int anslen)
      {
        (void) dname; (void) class; (void) type; (void) answer; (void) anslen;
        return -1;
      }
      int dn_expand (const unsigned char *msg, const unsigned char *eom, const unsigned char *src, char *dst, int dstsiz)
      {
        (void) msg; (void) eom; (void) src; (void) dst; (void) dstsiz;
        return -1;
      }
      unsigned ns_get16 (const unsigned char *src) { return ((unsigned) src[0] << 8) | src[1]; }
      unsigned long ns_get32 (const unsigned char *src)
      {
        return ((unsigned long) src[0] << 24) | ((unsigned long) src[1] << 16) | ((unsigned long) src[2] << 8) | (unsigned long) src[3];
      }
      EOF
            # WASIX matches none of glib's mtab platform blocks; provide a fallback.
            sed -i '1i #if defined(__wasi__)\nstatic const char *get_mtab_monitor_file(void){return 0;}\n#endif' gio/gunixmounts.c
            sed -i '/#error No _g_get_unix_mounts() implementation for system/d' gio/gunixmounts.c
            sed -i '/#error No g_get_mount_table() implementation for system/d' gio/gunixmounts.c
            # gtester links with --start-group, which wasm-ld rejects.
            sed -i "/gtester = executable('gtester'/,/meson.override_find_program('gtester', gtester)/d" glib/meson.build
            # WASIX EH sysroot lacks fork() and pthread affinity symbols; provide
            # real definitions so libglib's references resolve at link time.
            cat >> glib/gthread.c <<'EOF'

      #if defined(__wasi__)
      #include <errno.h>
      #include <pthread.h>
      #include <sched.h>
      pid_t fork (void) { errno = ENOSYS; return (pid_t) -1; }
      int __sched_cpucount (size_t setsize, const cpu_set_t *set) { (void) setsize; (void) set; return 1; }
      int pthread_getaffinity_np (pthread_t thread, size_t cpusetsize, cpu_set_t *cpuset) { (void) thread; (void) cpusetsize; (void) cpuset; return ENOSYS; }
      char *bind_textdomain_codeset (const char *domainname, const char *codeset);
      unsigned int if_nametoindex (const char *ifname);
      char *bind_textdomain_codeset (const char *domainname, const char *codeset) { (void) domainname; (void) codeset; return NULL; }
      unsigned int if_nametoindex (const char *ifname) { (void) ifname; return 0; }
      #endif
      EOF
            cat >> gio/gunixmounts.c <<'EOF'

      #if defined(__wasi__)
      static GList *_g_get_unix_mounts (void) { return NULL; }
      static GUnixMountEntry **_g_unix_mounts_get_from_file (const char *table_path, uint64_t *time_read_out, size_t *n_entries_out) { (void) table_path; if (time_read_out) *time_read_out = 0; if (n_entries_out) *n_entries_out = 0; return NULL; }
      static GList *_g_get_unix_mount_points (void) { return NULL; }
      static GUnixMountPoint **_g_unix_mount_points_get_from_file (const char *table_path, uint64_t *time_read_out, size_t *n_points_out) { (void) table_path; if (time_read_out) *time_read_out = 0; if (n_points_out) *n_points_out = 0; return NULL; }
      #endif
      EOF
    '';
    overrideAttrs = old: {
      buildInputs =
        builtins.filter
        (x: !(builtins.elem (x.pname or x.name or "") ["libsysprof-capture" "elfutils"]))
        (old.buildInputs or []);
      propagatedBuildInputs =
        builtins.filter
        (x: !(builtins.elem (x.pname or x.name or "") ["gettext" "libiconv"]))
        (old.propagatedBuildInputs or []);
      # Docs are disabled, so the devdoc output ends up empty and Nix removes
      # it; place a marker so the output is produced.
      postFixup =
        (old.postFixup or "")
        + ''
          mkdir -p "$devdoc" 2>/dev/null || true
          : > "$devdoc/.keep" 2>/dev/null || true
        '';
      mesonFlags =
        (old.mesonFlags or [])
        ++ [
          "-Ddocumentation=false"
          "-Dtests=false"
          "-Dintrospection=disabled"
          "-Dnls=disabled"
          "-Dselinux=disabled"
          "-Dlibmount=disabled"
          "-Dsysprof=disabled"
        ];
    };
  };

  # ---- Phase 2: 2D / text / toolkit substrate ----

  pixman = mkUpstreamLibrary {
    package = pkgsCross.pixman.override {
      libpng = self.libpng;
    };
    doCheck = false;
    preBuild = ''
      find . -name build.ninja -exec sed -i 's/--start-group//g; s/--end-group//g' {} +
    '';
    overrideAttrs = _old: {
      mesonFlags = ["-Dtests=disabled" "-Ddemos=disabled" "-Dgtk=disabled" "-Ddefault_library=static"];
    };
  };

  fribidi = mkUpstreamLibrary {
    package = pkgsCross.fribidi;
    doCheck = false;
    postPatch = ''
      # The bundled getopt CLI conflicts with libc getopt on wasm.
      sed -i "/subdir('bin')/d" meson.build
    '';
    preBuild = ''
      find . -name build.ninja -exec sed -i 's/--start-group//g; s/--end-group//g' {} +
    '';
    overrideAttrs = _old: {
      mesonFlags = ["-Ddocs=false" "-Dtests=false" "-Ddefault_library=static"];
      postFixup = ''
        mkdir -p "$devdoc" 2>/dev/null || true
        : > "$devdoc/.keep" 2>/dev/null || true
      '';
    };
  };

  harfbuzz = mkUpstreamLibrary {
    package = pkgsCross.harfbuzz.override {
      freetype = self.freetype;
      glib = self.glib;
      withGraphite2 = false;
      withIcu = false;
      withIntrospection = false;
    };
    doCheck = false;
    postPatch = ''
      # wasix++ rejects PIC with -fno-exceptions on the EH profile.
      find . -name meson.build -exec sed -i 's/-fno-exceptions//g' {} +
    '';
    preBuild = ''
      find . -name build.ninja -exec sed -i 's/-fno-exceptions//g; s/--start-group//g; s/--end-group//g' {} +
    '';
    overrideAttrs = old: {
      mesonFlags = (old.mesonFlags or []) ++ ["--native-file=${nativeFile}"];
    };
  };

  fontconfig = mkUpstreamLibrary {
    package = pkgsCross.fontconfig.override {
      expat = self.expat;
      freetype = self.freetype;
    };
    doCheck = false;
    preConfigure = ''
      cat > "$PWD/wasix-fcntl.h" <<'EOF'
      #include <fcntl.h>
      #ifndef F_GETLK
      #define F_GETLK 5
      #define F_SETLK 6
      #define F_SETLKW 7
      #define F_RDLCK 0
      #define F_WRLCK 1
      #define F_UNLCK 2
      #endif
      EOF
      export CFLAGS="-include $PWD/wasix-fcntl.h ''${CFLAGS:-}"
    '';
  };

  cairo = mkUpstreamLibrary {
    package = pkgsCross.cairo.override {
      fontconfig = self.fontconfig;
      freetype = self.freetype;
      glib = self.glib;
      libpng = self.libpng;
      pixman = self.pixman;
      zlib = self.zlib;
      x11Support = false;
      xcbSupport = false;
      gobjectSupport = true;
      lzo = null;
    };
    doCheck = false;
    postPatch = ''
      # meson's cc.has_function('ctime_r') probe is fooled by wasi's
      # __REDIR and reports no, but the wasix sysroot declares and
      # provides ctime_r. Force it on so cairo-ps-surface.c does not
      # define its own conflicting static ctime_r.
      sed -i "/configure_file(output: 'config.h', configuration: conf)/i conf.set('HAVE_CTIME_R', 1)" meson.build
      # cairo-ft.pc only carries fontconfig as a compile dependency, so a
      # static consumer (pango's cairo-ft probe) fails to resolve Fc*.
      substituteInPlace meson.build \
        --replace-fail "'deps': [freetype_dep]," "'deps': [freetype_dep, fontconfig_dep],"
    '';
    preBuild = ''
      # wasm-ld has no --start-group; meson wraps -lpthread/-lm in it.
      find . -name build.ninja -exec sed -i \
        's/-Wl,--start-group//g; s/-Wl,--end-group//g; s/--start-group//g; s/--end-group//g' {} +
    '';
    overrideAttrs = _old: {
      # nixpkgs' cairo cross-file evaluates a kernel map that throws for wasi;
      # supply the flags directly instead of forcing old.mesonFlags.
      mesonFlags = [
        "-Dgtk_doc=false"
        "-Dsymbol-lookup=disabled"
        "-Dspectre=disabled"
        "-Dglib=enabled"
        "-Dtests=disabled"
        "-Dxlib=disabled"
        "-Dxcb=disabled"
        # nixpkgs' meson hook forces -Dauto_features=enabled, so optional
        # deps become required. lzo is unused here (lzo = null).
        "-Dlzo=disabled"
        # Build a static archive. The shared link trips wasm-ld over
        # --start-group and the -soname value being read as an input.
        "-Ddefault_library=static"
      ];
      # Docs are disabled, so the devdoc output dir is empty.
      postFixup = ''
        mkdir -p "$devdoc" 2>/dev/null || true
        : > "$devdoc/.keep" 2>/dev/null || true
      '';
    };
  };

  pango = mkUpstreamLibrary {
    package = pkgsCross.pango.override {
      cairo = self.cairo;
      fribidi = self.fribidi;
      glib = self.glib;
      harfbuzz = self.harfbuzz;
      withIntrospection = false;
      x11Support = false;
      # pango defaults makeFontsConf's fontconfig to the plain wasm
      # fontconfig, which drags in the plain freetype and its brotli
      # dependency (whose CLI does not build on wasm).  Point it at the
      # closure's fontconfig instead.
      makeFontsConf = args: pkgsCross.makeFontsConf ({fontconfig = self.fontconfig;} // args);
      # pango's meson.build does not use libintl at all; nixpkgs only
      # propagates it. The real wasm gettext pulls a target bash that does
      # not configure cleanly, so use an inert stub to keep the build going.
      libintl = pkgsCross.runCommand "libintl-wasix-stub" {} ''
        mkdir -p $out/include $out/lib
      '';
    };
    doCheck = false;
    postPatch = ''
      # cairo is static here, so meson's cairo-ft dependency does not
      # propagate cairo's private libs and this probe fails on Fc* symbols
      # even though cairo was built with Fontconfig. Skip the false
      # negative.
      substituteInPlace meson.build \
        --replace-fail \
          "error('@0@ does not have the required FontConfig support'.format(b[0]))" \
          "message('assuming cairo-ft has the required FontConfig support')"
      # The CLI utils (pango-view/list/segmentation) are C++ programs that
      # link the C++ harfbuzz static archive and need the C++ runtime. We
      # do not need them for the GTK closure.
      substituteInPlace meson.build \
        --replace-fail "subdir('utils')" "# utils skipped: C++ CLI tools not needed"
    '';
    preBuild = ''
      # wasm-ld has no --start-group/--end-group.
      find . -name build.ninja -exec sed -i \
        's/-Wl,--start-group//g; s/-Wl,--end-group//g; s/--start-group//g; s/--end-group//g' {} +
    '';
    overrideAttrs = _old: {
      # nixpkgs' meson hook forces -Dauto_features=enabled, so every `auto`
      # feature becomes required. Pin each one explicitly.
      mesonFlags = [
        "-Ddefault_library=static"
        "-Ddocumentation=false"
        "-Dgtk_doc=false"
        "-Dman-pages=false"
        "-Dintrospection=disabled"
        "-Dbuild-testsuite=false"
        "-Dbuild-examples=false"
        "-Dfontconfig=enabled"
        "-Dlibthai=enabled"
        "-Dcairo=enabled"
        "-Dfreetype=enabled"
        "-Dxft=disabled"
        "-Dsysprof=disabled"
      ];
      # The CLI utils are skipped, so the bin output is empty.
      postFixup = ''
        mkdir -p "$bin" 2>/dev/null || true
        : > "$bin/.keep" 2>/dev/null || true
      '';
    };
  };

  gdk-pixbuf = mkUpstreamLibrary {
    package =
      (pkgsCross.gdk-pixbuf.override {
        glib = self.glib;
        libjpeg = self.libjpeg;
        libpng = self.libpng;
        libtiff = self.libtiff;
        withIntrospection = false;
        doCheck = false;
      }).overrideAttrs (old: {
        # Hook is target-built here and fails on wasi; not needed for a
        # static wasm closure. Apply before mkUpstreamLibrary appends wasixcc.
        nativeBuildInputs = builtins.filter (x: (x.pname or x.name or "") != "make-shell-wrapper-hook") (old.nativeBuildInputs or []);
        buildInputs = builtins.filter (x: (x.pname or x.name or "") != "make-shell-wrapper-hook") (old.buildInputs or []);
      });
    doCheck = false;
    preBuild = ''
      find . -name build.ninja -exec sed -i 's/--start-group//g; s/--end-group//g' {} +
    '';
  };

  graphene = mkUpstreamLibrary {
    package =
      (pkgsCross.graphene.override {
        glib = self.glib;
        withIntrospection = false;
        withDocumentation = false;
      }).overrideAttrs (old: {
        nativeBuildInputs = builtins.filter (x: (x.pname or x.name or "") != "make-shell-wrapper-hook") (old.nativeBuildInputs or []);
        buildInputs = builtins.filter (x: (x.pname or x.name or "") != "make-shell-wrapper-hook") (old.buildInputs or []);
      });
    doCheck = false;
  };

  libxkbcommon = mkUpstreamLibrary {
    package = pkgsCross.libxkbcommon.override {
      libxml2 = self.libxml2;
      wayland = self.wayland;
      wayland-protocols = self.wayland-protocols;
      withWaylandTools = false;
      libx11 = null;
      libxcb = null;
    };
    doCheck = false;
    preBuild = ''
      find . -name build.ninja -exec sed -i 's/--start-group//g; s/--end-group//g' {} +
    '';
    preConfigure = ''
      cat > "$PWD/wasix-fork.h" <<'EOF'
      #include <sys/types.h>
      #define fork() (-1)
      EOF
      export CFLAGS="-include $PWD/wasix-fork.h ''${CFLAGS:-}"
    '';
    overrideAttrs = _old: {
      mesonFlags = ["-Denable-x11=false" "-Denable-wayland=false" "-Denable-tools=false" "-Denable-docs=false" "-Ddefault_library=static"];
      postFixup = ''
        mkdir -p "$doc" 2>/dev/null || true
        : > "$doc/.keep" 2>/dev/null || true
      '';
    };
  };

  # libepoxy is pulled in by GTK4's GSK GL/NGL renderer even though we only
  # intend to use GSK_RENDERER=cairo. Build it without GLX/EGL/X11: it vendors
  # its own Khronos headers and uses wasix's dlopen stub for the runtime GL.
  libepoxy = mkUpstreamLibrary {
    package = pkgsCross.libepoxy.override {
      x11Support = false;
    };
    doCheck = false;
    overrideAttrs = old: {
      # GTK4's Wayland backend includes <epoxy/egl.h>, which libepoxy only
      # installs when EGL is enabled. GLX/X11 stay off; libepoxy vendors
      # the EGL headers it needs and loads the library via dlopen.
      mesonFlags = ["-Degl=yes" "-Dglx=no" "-Dx11=false" "-Dtests=false" "-Ddefault_library=static"];
      env =
        (old.env or {})
        // {
          CFLAGS = "-DEGL_NO_PLATFORM_SPECIFIC_TYPES -I${eglRegistry}/api";
        };
    };
  };

  # GTK4, Wayland-only, cairo first. There is no meson option to drop the
  # GL/NGL renderer, so libepoxy is still required; GSK_RENDERER=cairo is a
  # runtime choice.
  gtk4 = mkUpstreamLibrary {
    package =
      (pkgsCross.gtk4.override {
        x11Support = false;
        waylandSupport = true;
        vulkanSupport = false;
        trackerSupport = false;
        cupsSupport = false;
        broadwaySupport = false;
        xineramaSupport = false;
        compileSchemas = false;
        glib = self.glib;
        cairo = self.cairo;
        pango = self.pango;
        gdk-pixbuf = self.gdk-pixbuf;
        graphene = self.graphene;
        fribidi = self.fribidi;
        harfbuzz = self.harfbuzz;
        libepoxy = self.libepoxy;
        libxkbcommon = self.libxkbcommon;
        wayland = self.wayland;
        wayland-protocols = self.wayland-protocols;
        libpng = self.libpng;
        libjpeg = self.libjpeg;
        libtiff = self.libtiff;
        # libxml2 is only a native tool here (xmllint for
        # glib-compile-resources), and gettext provides msgfmt/xgettext; both
        # must be build-machine binaries, not the wasm ones.
        libxml2 = pkgs.buildPackages.libxml2;
        gettext = pkgs.buildPackages.gettext;
        # wrapProgram comes from makeWrapper's setup hook; use the native one.
        makeWrapper = pkgs.buildPackages.makeWrapper;
        # librsvg pulls the plain wasm cairo, which cannot even evaluate on
        # wasi. We do not need SVG pixbuf loading for first bring-up.
        librsvg = pkgsCross.runCommand "librsvg-wasix-stub" {} ''
          mkdir -p $out/include/librsvg-2.0 $out/lib/pkgconfig
        '';
        # gstreamer media is disabled (-Dmedia-gstreamer=disabled) and its
        # base/bad plugins pull the plain wasm pango/cairo.
        gst_all_1 = {
          gst-plugins-base = pkgsCross.runCommand "gst-plugins-base-wasix-stub" {} ''
            mkdir -p $out
          '';
          gst-plugins-bad = pkgsCross.runCommand "gst-plugins-bad-wasix-stub" {} ''
            mkdir -p $out
          '';
        };
        # nixpkgs lists the X11 libs in buildInputs unconditionally; they drag
        # in xorgproto/libglvnd which do not build on wasi. x11Support is off,
        # so stub them.
        libice = pkgsCross.runCommand "libice-wasix-stub" {} "mkdir -p $out";
        libsm = pkgsCross.runCommand "libsm-wasix-stub" {} "mkdir -p $out";
        libxcursor = pkgsCross.runCommand "libxcursor-wasix-stub" {} "mkdir -p $out";
        libxdamage = pkgsCross.runCommand "libxdamage-wasix-stub" {} "mkdir -p $out";
        libxi = pkgsCross.runCommand "libxi-wasix-stub" {} "mkdir -p $out";
        libxrandr = pkgsCross.runCommand "libxrandr-wasix-stub" {} "mkdir -p $out";
        libxrender = pkgsCross.runCommand "libxrender-wasix-stub" {} "mkdir -p $out";
        libxinerama = pkgsCross.runCommand "libxinerama-wasix-stub" {} "mkdir -p $out";
        libGL = pkgsCross.runCommand "libglvnd-wasix-stub" {} "mkdir -p $out";
        # Runtime data packages that drag in a plain wasm glib (and thus the
        # plain pcre2/zlib). Stub them for first bring-up.
        shared-mime-info = pkgsCross.runCommand "shared-mime-info-wasix-stub" {} ''
          mkdir -p $out/share
        '';
        gsettings-desktop-schemas = pkgsCross.runCommand "gsettings-desktop-schemas-wasix-stub" {} ''
          mkdir -p $out/share/glib-2.0/schemas
        '';
        # nativeBuildInputs are not spliced to the build machine here, and the
        # cross gobject-introspection pulls the target gobject-introspection,
        # which cannot even evaluate on wasi. Introspection is disabled, so a
        # harmless stub keeps the native input list satisfied.
        gobject-introspection = pkgsCross.runCommand "gobject-introspection-wasix-stub" {} ''
          mkdir -p $out/bin $out/lib
        '';
      }).overrideAttrs (old: {
        doCheck = false;
        # The tools are wasm; wrapping them with shell scripts is meaningless,
        # and the demos are not built. Skip nixpkgs' wrapProgram postInstall /
        # postFixup. Still require an installed static libgtk-4.a for programs.
        postInstall = ''
          if [ -f "$out/lib/libgtk-4.a" ]; then
            echo "gtk4: $out/lib/libgtk-4.a"
          elif [ -n "''${dev:-}" ] && [ -f "$dev/lib/libgtk-4.a" ]; then
            echo "gtk4: $dev/lib/libgtk-4.a"
          else
            echo "gtk4: missing libgtk-4.a (WASIX static install failed)" >&2
            find "$out" ''${dev:+"$dev"} -name 'libgtk*' 2>/dev/null || true
            exit 1
          fi
        '';
        postFixup = "";
        preBuild = ''
          # wasm-ld has no --start-group/--end-group.
          find . -name build.ninja -exec sed -i \
            's/-Wl,--start-group//g; s/-Wl,--end-group//g; s/--start-group//g; s/--end-group//g' {} +
        '';
        # The setup hook is target-built and pulls the target bash, which does
        # not configure on wasi. Not needed for a static wasm closure.
        nativeBuildInputs =
          builtins.filter (x: (x.pname or x.name or "") != "make-shell-wrapper-hook") (old.nativeBuildInputs or [])
          # gtk4 needs the build-machine glib tools (glib-compile-resources,
          # glib-mkenums, ...); the cross glib's bin is not on PATH.
          ++ [pkgs.buildPackages.glib];
        # Drop inputs we do not use: gstreamer media, the X11 stack, Wayland
        # libGL, and the gdk-pixbuf loaders (librsvg/isocodes/libtiff/libjpeg).
        # Re-add the closure libepoxy (self), not the plain wasm one.
        buildInputs = builtins.filter (
          input: let
            name = input.pname or input.name or "";
          in
            !(builtins.elem name [
              "gst-plugins-base"
              "gst-plugins-bad"
              "libice"
              "libsm"
              "libxcursor"
              "libxdamage"
              "libxi"
              "libxrandr"
              "libxrender"
              "librsvg"
              "isocodes"
              "libtiff"
              "libjpeg"
              "libGL"
              "libglvnd"
              "libepoxy"
            ])
        ) ((old.buildInputs or []) ++ [self.libepoxy]);
        env =
          (old.env or {})
          // {
            CFLAGS = ((old.env or {}).CFLAGS or "") + " -DEGL_NO_PLATFORM_SPECIFIC_TYPES -I${eglRegistry}/api -I${wasixLinuxInput}/include -I${librsvgStubHeaders} -DFE_UPWARD=0x800 -DFE_DOWNWARD=0x400 -DFE_TOWARDZERO=0xc00 -include ${wasixFtwShim}";
            # The tools link the C++ harfbuzz static archive, and libepoxy /
            # wayland-client need ppoll and dl*; bring in libc++ and the compat lib.
            LDFLAGS = ((old.env or {}).LDFLAGS or "") + " -lc++ -lc++abi -lunwind ${wasixCompat}/lib/libwasix-compat.a ${wasixWawonaWayland}/lib/libwawona-wayland.a -Wl,--wrap=connect -Wl,--wrap=sendmsg -Wl,--wrap=recvmsg -Wl,--wrap=poll -Wl,--wrap=close -Wl,--allow-undefined";
          };
        mesonFlags = [
          "-Dx11-backend=false"
          "-Dwayland-backend=true"
          "-Dbroadway-backend=false"
          "-Dwin32-backend=false"
          "-Dmacos-backend=false"
          "-Dandroid-backend=false"
          "-Dmedia-gstreamer=disabled"
          "-Dprint-cups=disabled"
          "-Dprint-cpdb=disabled"
          "-Dvulkan=disabled"
          "-Dcloudproviders=disabled"
          "-Dsysprof=disabled"
          "-Dtracker=disabled"
          "-Dcolord=disabled"
          "-Df16c=disabled"
          "-Daccesskit=disabled"
          "-Dintrospection=disabled"
          "-Ddocumentation=false"
          "-Dman-pages=false"
          "-Dbuild-demos=false"
          "-Dbuild-testsuite=false"
          "-Dbuild-examples=false"
          "-Dbuild-tests=false"
          "-Ddefault_library=static"
        ];
      });
    postPatch = ''
      # rsvg_dep is defined but never used; the old-version fallback is
      # required, so meson tries to download the librsvg wrap. Make it
      # optional so configure succeeds without librsvg.
      substituteInPlace meson.build \
        --replace-fail \
          "dependency('librsvg-2.0', version: ['>= 2.40.23', '< 2.41'])" \
          "dependency('librsvg-2.0', version: ['>= 2.40.23', '< 2.41'], required: false)"
      # Wawona SHM: the host owns the pool and the guest flushes pixels.
      cp ${./gtk4-wawona-gdkshm.c} gdk/wayland/gdkshm.c
      # GTK4's shared libgtk-4 trips wasm-ld (soname / --start-group).
      # Install one static libgtk-4.a that link_wholes gtk+css+gdk+gsk.
      # Aliasing libgtk=libgtk_static alone skips install and drops gdk/gsk.
      python3 - <<'PY'
      p = 'gtk/meson.build'
      s = open(p).read()
      start = s.index("libgtk = shared_library('gtk-4',")
      end = s.index("\n)\n", start) + 3
      s = (
        s[:start]
        + "libgtk = static_library('gtk-4',\n"
        + "  c_args: gtk_cargs + common_cflags,\n"
        + "  include_directories: [confinc, gdkinc, gskinc, gtkinc],\n"
        + "  dependencies: gtk_deps + [libgtk_css_dep, libgdk_dep, libgsk_dep],\n"
        + "  link_whole: [libgtk_static, libgtk_css, libgdk, libgsk ],\n"
        + "  install: true,\n"
        + ")\n"
        + s[end:]
      )
      open(p, 'w').write(s)

      p = 'gdk/wayland/gdkshm-private.h'
      s = open(p).read()
      s = s.replace(
        'struct wl_buffer *_gdk_wayland_shm_texture_get_wl_buffer',
        'void _gdk_wayland_shm_surface_flush (cairo_surface_t *surface);\n'
        'struct wl_buffer *_gdk_wayland_shm_texture_get_wl_buffer')
      open(p, 'w').write(s)

      p = 'gdk/wayland/gdksurface-wayland.c'
      s = open(p).read()
      s = s.replace(
        '  g_assert (_gdk_wayland_is_shm_surface (cairo_surface));',
        '  g_assert (_gdk_wayland_is_shm_surface (cairo_surface));\n'
        '\n'
        '  _gdk_wayland_shm_surface_flush (cairo_surface);')
      open(p, 'w').write(s)
      PY
    '';
    doCheck = false;
  };
}
