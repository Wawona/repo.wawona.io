# GTK-on-WASIX spike — status report

Date: 2026-10-10 (canonical tree: 2026-10-12)
Canonical: `github.com/Wawona/wasinix` branch `development`
Author of record (spike): `insomnia-creator <69950985+insomnia-creator@users.noreply.github.com>`

## Goal

Prove the WASIX lane for GTK4: build the toolkit **library** closure with
`wasixcc` + the WASIX sysroot under `pkgs/libraries/`, then run a program that
links it under Wawona Relay (Wasmer + `wawona_wayland_*` host imports). Not
Pulley `/wasm/v1` P1. Not `pkgs/programs/gtk4`.

**Status: Phases 1-4 library build GREEN on tip.** Runtime Wayland/GTK program
smokes are the remaining completion work (see Still open).

## Result

CI workflow `GTK WASIX libs` (`.github/workflows/gtk-wasix-libs.yml`),
matrix of `.#wasix.libraries.exnrefEh.<pkg>` on ubuntu-24.04:

| Package | State |
|---|---|
| `libffi` | ✅ green (wasix-org backend, real archive) |
| `pcre2` | ✅ green |
| `expat` | ✅ green |
| `wayland-protocols` | ✅ green |
| `wayland` | ✅ green (client-only build) |
| `glib` | ✅ green (libglib/libgobject/libgio build) |

Both assigned blockers (`fork` and Wayland `cmsg`) are resolved.

## The two blockers

### 1. `fork` (and cmsg) hidden by the wasm-EH headers

`wasix` sysroot `include/unistd.h` declares `fork` only when:

```
#if defined(__wasilibc_unmodified_upstream) || !defined(__wasm_exception_handling__)
```

The default profile is `exnrefEh`, so `__wasm_exception_handling__` is defined
and `fork` is **not declared**. Same guard hides `struct cmsghdr`,
`CMSG_*` and `SCM_RIGHTS` in `sys/socket.h` (only `struct msghdr` survives).

`__wasilibc_unmodified_upstream` is too broad: it pulls in a missing
`bits/errno.h`. The fix is a **force-included compat header** (`wasix-compat.h`)
written in each recipe's `preConfigure` and added with
`CFLAGS="-include $PWD/wasix-compat.h"`:

- declares `fork`/`_Fork`
- defines `struct cmsghdr`, `CMSG_*`, `SCM_RIGHTS` (wayland + glib)
- declares the xattr family for glib (later made unnecessary by disabling xattr)

**Important:** the WASIX EH sysroot *declares* `fork` but does **not define**
it. `libc.a` has no usable `fork` symbol in this profile. Real stubs are now
added in `glib/gthread.c` (see below). So the product rule stands: GTK on
WASIX must not rely on `fork`; `posix_spawn` is available for `g_spawn`.

### 2. Wayland

Solved by:
- `wayland` built **client-only**: drop the `signalfd`/`timerfd` requirement
  from `meson.build` and delete the `libwayland-server` block from
  `src/meson.build` (GTK needs client only).
- `epoll-shim` forced to `emptyDirectory` and `libffi = self.libffi`.
- `PF_LOCAL` → `AF_UNIX` in `wayland-client.c`.
- `wl_os_socket_peercred` fallback (`return -1`) for the `#error` platform case.
- cmsg compat from blocker 1.

Whether the *functional* fd bridge (`wawona_wayland_sendmsg` / host SHM) is
needed is still open: it lives in `wwn-wasm` (`src/host.rs`) and the raw
`examples/wayland-shm` client. libwayland currently compiles and links; the
runtime bridge is a follow-up.

## `glib` link-time stubs (current frontier)

`libglib`/`libgobject`/`libgio` **compile**. Remaining failures are undefined
symbols at tool link (`gobject-query` etc.), each added as a stub in
`pkgs/libraries/gtk.nix` → glib `postPatch`:

- `fork`, `__sched_cpucount`, `pthread_getaffinity_np` → `glib/gthread.c`
- `bind_textdomain_codeset`, `if_nametoindex` → `glib/gthread.c`
- `_g_get_unix_mounts`, `_g_unix_mounts_get_from_file`,
  `_g_get_unix_mount_points`, `_g_unix_mount_points_get_from_file`
  → `gio/gunixmounts.c`

Also in the glib recipe:
- `__wasilibc_unmodified_upstream` was tried and reverted; use the compat header.
- `resolv.h` shim (`wasix-include/resolv.h`) + failing `res_query`/`dn_expand`
  stubs appended to `gio/gthreadedresolver.c`.
- xattr disabled by commenting out `glib_conf.set('HAVE_XATTR', 1)` in meson.
- `-Dnls=disabled`, `-Dintrospection=disabled`, `-Dselinux=disabled`,
  `-Dlibmount=disabled`, `-Dsysprof=disabled`, target `libsysprof-capture`
  overridden to `emptyDirectory`.
- `gtester` target removed from `glib/meson.build` (links with
  `--start-group`, which `wasm-ld` rejects).
- `preBuild`: strip `--start-group`/`--end-group` from `build.ninja` so all
  glib tool links work.

## Key discoveries (worth keeping)

1. `isWasix` is **unused in nixpkgs**; `pkgsCross.wasix.*` is plain
   `wasm32-unknown-wasi`. It is broken for the GTK closure (libffi Emscripten,
   epoll-shim signals). **WASIX is the correct lane.**
2. Upstream libffi 3.5.x has only an Emscripten wasm backend. Use
   **`wasix-org/libffi`** (pinned `09cbf7d6`), which has `src/wasm32`.
3. The wasix-org libffi git archive ships **no `configure`/`Makefile.in`**, and
   nixpkgs' libffi recipe has no `autoreconfHook` — so configure/build/install
   silently did nothing (empty outputs). Fixes: `pkgs.autoreconfHook` +
   `pkgs.texinfo` (for `makeinfo`).
4. libffi's multi-output fixup moves `.a`/headers/`.pc`; the `.pc` must use
   `$dev/include` (never `$out/include`, which is removed → clang
   `-Wmissing-include-dirs` is fatal in glib).
5. `wasm-ld` has no `--start-group`.
6. `libffi` job logs are often unavailable via `gh run view --job --log`;
   `gh api repos/<o>/<r>/actions/jobs/<id>/logs` works.

## Files touched

All in `wasinix`:

- `pkgs/libraries/gtk.nix` — the whole spike closure (libffi, pcre2, expat,
  wayland, wayland-protocols, glib recipes + patches/stubs).
- `pkgs/libraries/default.nix` — wires `gtk.nix` into `baseLibraries`.
- `.github/workflows/gtk-wasix-libs.yml` — CI matrix.
- `flake.nix` — removed `self.submodules` (dead phpix submodule).
- `vendor/phpix/README.md` — placeholder replacing the 404 submodule.
- (uncommitted) `docs/gtk-wasix-spike-report.md` — this file.

## How to resume tomorrow

```bash
cd /Users/it/Projects/Wawona/wasinix
git log --oneline -1                      # expect >= 20dc8aa
gh run list -R insomnia-creator/wasinix --workflow "GTK WASIX libs" --limit 3
# read a failing job:
JID=$(gh run list -R insomnia-creator/wasinix --workflow "GTK WASIX libs" --limit 1 \
      --json databaseId --jq '.[0].databaseId')
gh run view "$JID" -R insomnia-creator/wasinix --json jobs \
  --jq '.jobs[] | "\(.name) \(.status)/\(.conclusion // "-")"'
# then: gh api repos/insomnia-creator/wasinix/actions/jobs/<jobid>/logs
```

Next actions:
1. Add the remaining GTK closure nodes to `wasinix`:
   `pixman`, `cairo`, `harfbuzz`, `fribidi`, `fontconfig`, `pango`,
   `gdk-pixbuf`, `graphene`, `libepoxy`, `libxkbcommon`, then `gtk4`
   (Wayland-only, `GSK_RENDERER=cairo` first).
2. Then the `wwn-wasm` host ABI work for the Wayland fd bridge and the
   `wwn-gtk` native/consumer integration.
3. `Wawona/wwn-gtk` still needs to be created by an org admin (only
   `insomnia-creator/wwn-gtk` exists).

## Phase 2 status (2026-10-10)

Added pixman, fribidi, harfbuzz, fontconfig, cairo, pango, gdk-pixbuf,
graphene, libxkbcommon to `pkgs/libraries/gtk.nix` and the CI matrix.
**All 15 nodes green.**

Key fixes beyond Phase 1:

- **wasixcc `--version` SIGPIPE** (root cause of the cairo/pango flake):
  `wasixccenv` let the compiler inherit stdout, so autoconf/meson version
  probes that close the read end killed clang with SIGPIPE. Patched in
  `pkgs/toolchain/wasixcc-version-sigpipe.patch` to capture and re-emit.
- **cairo**: nixpkgs' cross-file throws for wasi, so supply `mesonFlags`
  directly; `-Dlzo=disabled` (the meson hook forces `auto_features=enabled`);
  `HAVE_CTIME_R=1` (the `cc.has_function` probe is fooled by wasi's
  `__REDIR`); build static (the shared link trips wasm-ld over
  `--start-group`/soname); add fontconfig to the `cairo-ft` link deps; mark
  the empty `devdoc` output.
- **pango**: `makeFontsConf` defaulted to the plain wasm fontconfig, pulling
  the plain freetype and its wasi-unbuildable brotli CLI; point it at the
  closure fontconfig. Replaced `libintl` (the wasm gettext drags in a target
  bash that does not configure) with an inert stub. Pinned every meson
  feature (`build-testsuite`, `-Ddefault_library=static`); skipped the
  false-negative `cairo-ft` FontConfig link probe, the C++ CLI utils, and
  the empty `bin` output.
- **wasm-ld** has no `--start-group`/`--end-group`; strip them from
  `build.ninja` in `preBuild` where meson emits them (cairo, pango,
  harfbuzz, libxkbcommon).
- pixman/fribidi static libs and CLI drops, gdk-pixbuf/graphene
  `make-shell-wrapper-hook` filter, empty `doc`/`devdoc` outputs marked.

CI: added a Nix store cache (`nix-community/cache-nix-action`) and a
one-shot retry for the wasixcc flake.

Commits: Phase 1 is one squashed commit `02d71b1`; Phase 2 is one squashed
commit on top. Deferred to the GPU phase: `libepoxy` (no EGL/GL on wasm).

## Phase 3 status (2026-10-11)

Added `libepoxy` and `gtk4` to the closure and CI matrix. **All 17 nodes
green.**

GTK4 4.20, Wayland-only, `GSK_RENDERER=cairo` first:

- **libepoxy** is required by GSK's GL/NGL renderer (there is no meson option
  to drop it). Built with EGL on, GLX/X11 off, static. Vendored the Khronos
  EGL headers (EGL-Registry) since wasi has none;
  `-DEGL_NO_PLATFORM_SPECIFIC_TYPES` gives `void *` natives.
- **gtk4 knobs**: `x11-backend=false`, `wayland-backend=true`,
  `vulkan/tracker/cups/broadway/introspection/documentation` off,
  `media-gstreamer=disabled`, `f16c=disabled`, `default_library=static`.
- **Build-machine tools**: native `glib` (glib-compile-resources), native
  `libxml2` (xmllint), native `gettext` (msgfmt), native `makeWrapper`;
  `gobject-introspection` stubbed (introspection off).
- **Stubbed/thinned inputs** that pull plain-wasm subgraphs or X11:
  `librsvg`, `gst_all_1`, `shared-mime-info`, `gsettings-desktop-schemas`,
  `libice`/`libsm`/`libX*`/`libGL`; `isocodes` stays.
- **Patched `gtk/meson.build`**: the unused `rsvg_dep` fallback is
  `required: false`; `libgtk` aliases the static target (the shared
  `libgtk-4` link trips wasm-ld).
- **Compat shims**: `<linux/input.h>` (BTN_* codes), inert `librsvg/rsvg.h`
  (static-inline no-ops), inert `ftw()`,
  `FE_UPWARD`/`FE_DOWNWARD`/`FE_TOWARDZERO`, and a small wasm
  `libwasix-compat.a` providing `ppoll` (wayland) and
  `dlopen`/`dlsym`/`dlerror` (libepoxy).
- gtk4 links only as a static lib; its CLI tools build, but the shell
  `wrapProgram` fixups are skipped.

Commits: Phase 1, Phase 2 and Phase 3 are each one squashed commit.

## Phase 4 status (2026-10-11)

The runtime lane: the **guest side of the Wayland fd bridge** (connection +
SHM).

- New `wasinix/pkgs/libraries/wawona-wayland.c`: `--wrap` shims for
  `connect` / `sendmsg` / `recvmsg` / `poll` / `close` that route
  libwayland's transport through the host imports (module `env`,
  registered also as `wawona_socket`):
  `wawona_wayland_connect`, `wawona_wayland_sendmsg`, `wawona_socket_recv`,
  `wawona_socket_close`, `wawona_wayland_shm_create`,
  `wawona_wayland_shm_write`, `wawona_socket_close`. Non-Wayland fds fall
  through to the real libc calls, so the shim is inert off Relay. The host
  returns a **synthetic** fd for the Wayland stream, so the shim keeps a
  guest-fd to host-fd map.
- New `wasinix/pkgs/libraries/gtk4-wawona-gdkshm.c` replaces GTK4's
  `gdk/wayland/gdkshm.c`: the host owns the `wl_shm` file
  (`wawona_wayland_shm_create`), the guest draws into heap memory, and GDK
  flushes pixels to the host (`wawona_wayland_shm_write`) right before
  `wl_surface_attach` (`_gdk_wayland_shm_surface_flush`, called from
  `gdk_wayland_surface_attach_image`).
- Built by `wasixWawonaWayland` and linked into gtk4 with
  `-Wl,--wrap=...` + `-Wl,--allow-undefined`. **17/17 green.**

Still open (completion plan):
- **Wayland bridge smoke** (`pkgs/programs/wayland-bridge-smoke`): one SHM
  frame via Relay host imports (`wawona_wayland_*`).
- **GTK program smoke** (`pkgs/programs/gtk4-hello`): link `libraries.gtk4`,
  one toplevel frame under Relay (Wasmer). Never name the program `gtk4`.
- **Product wire**: Machines/Relay launch on Wasmer hosts (not Pulley).
- **Known stubs (not v1 blockers):** inert librsvg (no SVG), GSK cairo only
  (GL/NGL unused), X11/gstreamer stubs.

## Known limits

| Item | State |
|------|--------|
| SVG textures | inert `librsvg` stub |
| GSK renderer | `GSK_RENDERER=cairo` first; GL/NGL linked unused |
| Store Pulley / iOS ≤ 26 Mode A | forbidden for this WASIX toolkit |
| Tip library CI | `.github/workflows/gtk-wasix-libs.yml` on `development`/`main` |

## Repo pointers

- Canonical: `github.com/Wawona/wasinix@development` (`pkgs/libraries/gtk.nix`)
- Taxonomy: `docs/libraries-vs-programs.md`, `docs/gtk4-wayland.md`
- Host ABI: `Relay/import/wasm/src/host.rs` (`wawona_wayland_*`)
- Canonical ABI: `repo.wawona.io/docs/wasm-abi.md` (nixpkgs2wasi retired;
  wasinix is the WASIX producer of record)
