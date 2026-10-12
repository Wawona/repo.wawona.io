# Libraries vs programs (wasinix)

wasinix has two product trees. Do not mix them.

| Tree | Path | What it is | Flake shape |
|------|------|------------|-------------|
| **Libraries** | `pkgs/libraries/` | Shared code: libc deps, text stack, **toolkits/frameworks** | `.#wasix.libraries.<profile>.<name>` |
| **Programs** | `pkgs/programs/` | Runnable CLIs / apps that *link* libraries | `.#wasix.<name>` / `.#wasmer.<name>` |

## Libraries (dependencies / frameworks / toolkits)

Build artifacts are archives and headers (`.a`, `.pc`, include trees).
Consumers link them. Catalog identity still uses upstream name + version, but
the unit is **not** a Wasmer “command” by itself.

Examples already in-tree: `zlib`, `openssl`, `freetype`, `libxml2`,
`libraries.ncurses` (`--without-progs`).

**GTK4 belongs here** (`pkgs/libraries/gtk.nix` and its closure). Same class
as cairo/pango, not the same class as `grep`.

## Programs

Build artifacts are binaries (often `.wasm` under `$out/bin`) meant to run
under Wasmer. Recipes take `libraries.*` as inputs when needed.

Examples: `grep`, `sed`, `nano`, `less`, `tar`. A future **GTK demo app**
(e.g. `gtk4-demo` or a Wawona sample) is a program that *depends on*
`libraries.gtk4`. It is not “gtk4 the program.”

## Split packages (same upstream, two roles)

`ncurses` is the standing example:

- `libraries.ncurses`: library only (`--without-progs`)
- `programs.ncurses`: same upstream with CLI tools (`--with-progs`)

That pattern is fine when upstream ships both. GTK4’s demos are optional
programs on top of the library; the library never moves into `pkgs/programs/`.

## Hard rejects

- Putting GTK / Qt / Cairo / GLib under `pkgs/programs/` because “we want a
  package”
- Calling a toolkit a CLI port without saying it is a library closure first
- Publishing a stub `gtk4` Wasmer command at fake `0.1.0`
- Labeling the GTK closure as store Pulley `/wasm/v1` P1

## Where GTK work lands

`pkgs/libraries/gtk.nix` (closure + Wayland fd bridge). Docs:
`docs/gtk4-wayland.md`, `docs/gtk-wasix-spike-report.md`.
