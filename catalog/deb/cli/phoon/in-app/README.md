# wwn-phoon-rs

[![CI](https://github.com/Wawona/wwn-phoon-rs/actions/workflows/ci.yml/badge.svg)](https://github.com/Wawona/wwn-phoon-rs/actions/workflows/ci.yml)

An independent, dependency-free **Rust** implementation that reproduces the
behavior and terminal output of the historical [`phoon`](https://acme.com/software/phoon/)
moon-phase utility by Jef Poskanzer.

`phoon-rs` is a **clean-room** work. It is *not* a port or translation of the
original `phoon` source code:

- The astronomy is implemented from published references (Duffett-Smith /
  Meeus, as used by John Walker's `moontool`).
- The ASCII renderer, CLI, and date-handling behavior are derived from the
  original program's *observable output* and documentation — never from its C
  source.

The reference program's *output* is used only as a compatibility **test
oracle**: for a given instant, `phoon-rs` produces byte-for-byte identical
terminal output. See `tests/reference/` for the committed golden corpus and
`tests/compat.rs` for the check.

```text
Original phoon                 phoon-rs
       @@@@@                          @@@@@
     @@@@@@@@@                      @@@@@@@@@
    @@@@@@@@@@@                    @@@@@@@@@@@
   @@@@@@@@@@@@@                  @@@@@@@@@@@@@
    @@@@@@@@@@@                    @@@@@@@@@@@
     @@@@@@@@@                      @@@@@@@@@
       @@@@@                          @@@@@

diff <(phoon …) <(phoon-rs …)   →   zero differences
```

## License

MIT. See [`LICENSE`](LICENSE).

`phoon-rs` reproduces the behavior of the historical `phoon` utility by Jef
Poskanzer; it shares no source code with it.

## Using it

### As a CLI

```bash
phoon                       # the moon right now, default size (23 lines)
phoon -l 29                 # a larger moon
phoon 08 Aug 2026 12:00:00  # the moon at a specific instant
```

`phoon-rs` interprets times as **UTC** for deterministic, portable output. To
compare against the reference program, run it with `TZ=UTC`.

### As a library

```rust
use phoon_rs::Moon;

let moon = Moon::at(1_754_654_400); // Unix seconds, UTC
let art = moon.render(23);          // ASCII art, sized to 23 lines
print!("{art}");
```

### In-process (C ABI)

For embedding inside another process (this is how Wawona's shell tools use it),
the crate exports a C entry point matching the CLI:

```c
#include "phoon.h"
int rc = phoon_main(argc, argv);   // same argv/exit code as the CLI
```

The library is built as `libphoon_rs.a` (Apple platforms, static) or
`libphoon_rs.so` (Android), so no subprocess, libc port, or C compiler is
required at the call site.

## Layout

```text
src/
  lib.rs        public Moon API
  bin/phoon.rs  standalone CLI
  ffi.rs        phoon_main C ABI entry point
  caltime.rs    dependency-free UTC calendar arithmetic
  lunar.rs      moon-phase model (Duffett-Smith / Meeus)
  geometry.rs   disc geometry + terminator span
  render.rs     ASCII rendering + captions + easter eggs
  dateparse.rs  behavioral date parser
  cli.rs        argument handling / error text / exit codes
  data/*.txt    reconstructed background frames (data, not source)
tests/
  reference/    committed golden corpus (reference program output)
  compat.rs     byte-for-byte compatibility check
  units.rs      unit tests
dependencies/libs/phoon/   per-platform Nix staticlib recipes
```

## Building

```bash
cargo build --release          # CLI + static/rlib/cdylib
cargo test                     # unit + compatibility tests

# Host-native CLI (macOS on Darwin, Linux on Linux):
nix run .#phoon
nix run .                      # same — default app/package is host phoon
nix run .#phoon -- -l 18

# Explicit platform packages (also used by Wawona):
nix build .#phoon-macos        # Darwin hosts
nix build .#phoon-linux        # Linux hosts
```

## Wawona integration

This repo is an **L3** node in the Wawona dependency DAG: it depends only on
`wwn-toolchain`. Wawona merges `registryFragment.phoon` and links the
in-process static lib, dispatching to `phoon_main` from the bundled shell.
