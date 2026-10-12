# PHP WASIX Libraries

This directory builds static ZTS `libphp` artifacts for WASIX.

The exported packages are:
- `php83ZTS`
- `php85ZTS`

Both are assembled from upstream `php/php-src`, plus a small version-specific patch stack and a shared WASIX build flow.

## Layout

- `default.nix`: exports the versioned packages.
- `versions.nix`: pins upstream PHP sources, shared configure flags, bundled extension sources, and per-version patch lists.
- `mk-php-zts.nix`: shared derivation that applies patches, injects bundled extensions, configures PHP, and installs the resulting headers and SAPI artifacts.
- `patches/`: patch stacks extracted from the historical fork and organized by version.

## Source Strategy

The intent is to avoid carrying a long-lived PHP fork.

Each PHP version is built from an upstream `php-src` commit pinned in `versions.nix`. Any WASIX- or embedding-specific source modifications live as explicit patch files in this directory. That keeps the delta reviewable and makes it practical to add more PHP versions later.

For a new version, the expected flow is:
1. Pin the upstream `php-src` commit and hash in `versions.nix`.
2. Add a version-specific patch stack under `patches/`.
3. Reuse `mk-php-zts.nix` unless the new version truly needs a different build flow.

## Build Flow

`mk-php-zts.nix` performs the build in four stages.

### 1. Patch and bundle sources

The derivation starts from upstream `php-src` and then:
- applies the Nix-level `patches` list
- replaces selected `ext/*` directories with pinned upstream extension sources from `bundledExtensions`
- applies any extension-local patches after copying those sources in
- runs `patchShebangs` on the build scripts and bundled extension trees

Today the bundled extensions are:
- `igbinary`
- `imagick`

`imagick` also carries a local patch so it can be built correctly in this bundled/static WASIX setup.

## 2. Configure

The builder uses `wasixcc` and friends from `toolchain`, then exports a large set of `*_CFLAGS` / `*_LIBS` variables derived from the profile-aware shared library set under `pkgs/libraries`. PHP itself no longer depends on the external `php-wasix-deps` repository. Instead, it links against explicit Nix library derivations such as:
- `zlib`
- `xz`
- `libxml2`
- `sqlite`
- `openssl`
- `icu`
- `libpng`
- `libjpeg`
- `freetype`
- `libwebp`
- `libzip`
- `libsodium`
- `oniguruma`
- `libpq`
- `imagemagick`

Important configure characteristics:
- target is `wasm32-wasi`
- build is static, with shared libraries disabled
- ZTS is enabled
- embed SAPI is enabled as `static`
- CGI and phpdbg are disabled
- many common extensions are enabled directly at configure time, including `pdo`, `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `mysqli`, `gd`, `intl`, `curl`, `zip`, `mbstring`, `sodium`, `ftp`, `igbinary`, and `imagick`
- PostgreSQL support is wired through a temporary merged `libpq` prefix built from the `libpq` dev and library outputs, because upstream PHP expects a single prefix for `--with-pgsql`

The configure flags live mostly in `versions.nix`, with version-specific additions layered on top.

## 3. Build

The build phase runs:

```sh
make -j${NIX_BUILD_CORES:-1} install-headers install-sapi
```

This is intentional. We are not trying to produce a normal host PHP installation; we are building the headers and SAPI artifacts needed by the WASIX embedding flow.

## 4. Install

The derivation copies the staged install tree from `install/` into `$out`.

## Important Human Factors

### OPCache is sensitive to build-flow drift

The original fork had working opcache support, and the current Nix build depends on reproducing the same important conditions.

The critical points are:
- PHP 8.3 still needs the extracted opcache patch stack from `patches/common/` and still passes `--enable-opcache`.
- PHP 8.5 is different upstream and does not use the same `--enable-opcache` flag behavior.
- The PHP build itself currently uses `WASIXCC_WASM_EXCEPTIONS=yes` in `mk-php-zts.nix`.

With `wasixcc 0.4.x`, `WASM_EXCEPTIONS=yes` selects the exnref EH sysroots (`sysroot-exnref-eh*`), while `legacy` selects the older EH sysroots (`sysroot-eh*`). Keep PHP and `phpix` on the same mode or you will end up mixing incompatible sysroot/runtime assumptions.

If opcache regresses, check build configuration before assuming the patch stack is incomplete.

### The library set is part of the contract

The PHP builder still depends on a fairly specific dependency surface, but that surface now comes from explicit Nix derivations rather than an external monorepo. If you change library names, output layouts, header locations, or static library names in `pkgs/libraries`, expect PHP configure and link behavior to change.

Two details matter in practice:
- `mk-php-zts.nix` computes include paths and library search paths directly from each derivation output
- `phpix` reuses the `phpExtraLibDirs` exported by the PHP derivation, so PHP and `phpix` stay in sync on the link search path

At the moment, the PHP packages are intentionally wired only to the `exnrefEh` library profile. If you add `eh`, `ehpic`, or `exnrefEhpic` PHP builds later, keep the full dependency graph on one profile and do not mix library variants.

### Bundled extensions are intentionally pinned separately from PHP

`igbinary` and `imagick` are not taken from the old PHP fork. They are fetched from their upstream repositories and injected into `ext/` during `postPatch`. This keeps the PHP patch stack smaller and makes extension upgrades more composable, but it also means extension breakage can come from either:
- PHP core changes
- extension source changes
- the extension-local patch set

### Prefer version data over builder forks

When adding another PHP version, put version-specific data in `versions.nix` first:
- upstream source pin
- patch list
- extra configure flags
- extension overrides, if needed

Only fork `mk-php-zts.nix` if the build phases or environment really diverge. Reusing one builder is the main mechanism that keeps multiple PHP versions maintainable.

### Validate with real builds

A successful evaluation is not enough here. Small toolchain or exception-model changes can alter configure-time feature detection or runtime behavior. For changes that touch opcache, extensions, toolchain versions, or configure flags, run a real `nix build` for the affected PHP version.

### ImageMagick needs extra scrutiny

`ImageMagick` is the least upstream-clean dependency in the PHP stack right now. Compared to the other PHP libraries, it needs more WASIX-specific handling:
- a small portability patch around `fork()`
- removal of target-inappropriate delegate/build dependencies
- explicit `zstd` headers because the TIFF coder includes `zstd.h` directly

If `imagick` breaks, inspect the `imagemagick` entry in `pkgs/libraries/default.nix` before assuming the PHP builder is wrong.
