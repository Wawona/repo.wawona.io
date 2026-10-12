# GTK4 on Wawona (WASIX library + deb)

GTK4 is a **library / toolkit**, not a program. It lives under
`pkgs/libraries/` (closure: glib, cairo, pango, wayland-client, …). See
`docs/libraries-vs-programs.md`.

A GTK *app* (demo or real client) is a separate `pkgs/programs/` recipe that
links `libraries.gtk4`. Do not name that program `gtk4`.

| Channel | Repo / tree | Runtime |
|---------|-------------|---------|
| WASIX library | `wasinix` `.#wasix.libraries.*.gtk4` | Link into Wasmer guests |
| WASIX program | `pkgs/programs/gtk4-hello`, `wayland-bridge-smoke` | Relay Wasmer + `wawona_wayland_*` |
| Deb | `repo.wawona.io` Wayland packages | Jailbreak iOS, Termux, Linux. Upstream process |

Hard rejects:

- `pkgs/programs/gtk4` (toolkit misfiled as CLI)
- App Store no-fork patches for GTK
- Labeling WASIX GTK as Pulley `/wasm/v1` P1
- Stub `gtk4` at fake `0.1.0`
- Claiming green from plain `wasmer run` without Relay host imports

Build:

```bash
nix build .#wasix.libraries.exnrefEh.gtk4
nix build .#wasmer.wayland-bridge-smoke
nix build .#wasmer.gtk4-hello
WAWONA_RELAY_RUN='…' WAYLAND_DISPLAY=wayland-0 \
  ./scripts/smoke-wayland-relay.sh gtk4-hello
```

`gtk4-hello` shows **Hello, Wayland World!** (GTK4). Set `GTK4_HELLO_SMOKE=1`
to quit after map for automated one-frame proofs.

Publish to `repo.wawona.io` as **`wasi=wasix`** (never P1):

```bash
# GHA: Publish gtk4-hello (WASIX) → stages wasm/v1 + index row
gh workflow run 'Publish gtk4-hello (WASIX)' --repo Wawona/wasinix
```

Library CI: `.github/workflows/gtk-wasix-libs.yml` on `development`/`main`.
