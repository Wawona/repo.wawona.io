# ArtCraft Crafting Apps → Wawona `/wasm/v1`

Source map and WASI packaging status for the ArtCraft **Crafting Apps** suite
(`storytold/*craft`). Not the AI studio IDE [`storytold/artcraft`](https://github.com/storytold/artcraft).

Site index: <https://getartcraft.com/apps>.

## ABI gap (hard)

| Lane | Target | Stack | Wawona today |
|------|--------|-------|--------------|
| ArtCraft Web | `wasm32-unknown-unknown` | eframe/egui + WebGPU, wasm-bindgen, `cargo xtask web` | **Not** `/wasm/v1` |
| Wawona Runtime | `wasm32-wasip1` | Relay / `wpm` / Pulley; Wayland via host ABI for GUI | Catalog path |

Do not publish `*_bg.wasm` + JS glue as `component.wasm`. Browser web dists are
a different product surface.

Wawona builds run on **GitHub Actions** via `allowlist.toml` (`cargo-wasip1`),
not by mirroring every upstream flake. LightCraft has `flake.nix`; others are
Cargo + xtask.

## Crafting Apps matrix

All under `https://github.com/storytold/<repo>`. License: MIT OR Apache-2.0
unless noted. Version column is the latest release observed when this doc was
written; allowlist rows pin the packaging target.

| App | Repo | Analog | Upstream web | Wawona `/wasm/v1` status |
|-----|------|--------|--------------|-------------------------|
| EffectCraft | [effectcraft](https://github.com/storytold/effectcraft) | After Effects | `cargo xtask web` / `docs/web.md` (~58 MB) | **Withdrawn** from `/wasm/v1` until Wayland GUI; allowlist blocked |
| PhotoCraft | [photocraft](https://github.com/storytold/photocraft) | Photoshop | Web + xtask | `blocked` (no wasip1 recipe) |
| VectorCraft | [vectorcraft](https://github.com/storytold/vectorcraft) | Illustrator | Web + xtask | `blocked` |
| FilmCraft | [filmcraft](https://github.com/storytold/filmcraft) | Premiere | Web + xtask | `blocked` (also dep of EffectCraft media) |
| LightCraft | [lightcraft](https://github.com/storytold/lightcraft) | Lightroom | Web + xtask + flake.nix | `blocked` |
| PdfCraft | [pdfcraft](https://github.com/storytold/pdfcraft) | Acrobat | Web + xtask | `blocked` |
| DesignCraft | [designcraft](https://github.com/storytold/designcraft) | InDesign-class | Web + xtask | `blocked` |
| SoundCraft | [soundcraft](https://github.com/storytold/soundcraft) | Pro Tools | Web + xtask | `blocked` |
| WordCraft | [wordcraft](https://github.com/storytold/wordcraft) | Word | Web + xtask | `blocked` |
| DeckCraft | [deckcraft](https://github.com/storytold/deckcraft) | PowerPoint | Web + xtask | `blocked` |
| GridCraft | [gridcraft](https://github.com/storytold/gridcraft) | Excel | Web + xtask | `blocked` |
| CADCraft | [cadcraft](https://github.com/storytold/cadcraft) | AutoCAD | Web + xtask | `blocked` |
| craft-fonts | [craft-fonts](https://github.com/storytold/craft-fonts) | Fonts | N/A | Asset / dep only (not a Runtime package) |

Shared traits: egui desktop UI, MCP/CLI on many apps, browser path via eframe
web runner.

## EffectCraft inventory (v0.6.0)

Pinned release: **v0.6.0** (2026-10-08). Workspace version `0.6.0`, Rust 1.95+.

### Apps

| Crate | Path | Role | wasip1 |
|-------|------|------|--------|
| `effectcraft` | `apps/effectcraft` | Desktop egui + eframe (wgpu, wayland/x11) | No (native UI) |
| `effectcraft-web` | `apps/effectcraft-web` | Browser cdylib (`wasm32-unknown-unknown`) | Wrong ABI for Relay |
| `effectcraft-cli` | `apps/effectcraft-cli` | Headless render / MCP | Depends on `ui-egui` + `gpu`; not a drop-in wasip1 binary yet |

### Crates (selected)

| Crate | wasip1 `cargo check` (v0.6.0) |
|-------|-------------------------------|
| `effectcraft-time` | OK |
| `effectcraft-geom` | OK |
| `effectcraft-color` | OK |
| `effectcraft-keyframe` | OK |
| `effectcraft-expr` | OK (pulls model/path/text/effects/render/boa) |
| `effectcraft-engine` / `effectcraft-cli` | Expected fail or heavy (gpu, host, ui-egui, filmcraft codecs) |

### Pilot package (withdrawn)

| Catalog id | Upstream | Version | Status |
|------------|----------|---------|--------|
| `effectcraft-expr` | git tag `v0.6.0` | `0.6.0` | **Blocked / pruned** from live `/wasm/v1` |

Recipe tree may remain at `packages/effectcraft-expr` for a future republish.
Do not re-activate until there is a real **egui → Wayland** (`wl_shm` or later
GPU WSI) path for Crafting Apps. A CLI-only `check_syntax` slice is not the
product surface.

Pinned SHA for tag v0.6.0: `6943872cf65b3da1275f1e0f808b60b2e51d84dc`.

## Packaging rules

- `origin = "port"`: `version` = upstream release (`0.6.0`), `homepage` =
  project URL, `upstream_git` for freshness (`version_policy = git-tag`).
- Never forge Adobe product names. Catalog ids: `effectcraft-expr`,
  `effectcraft-cli` (blocked), `photocraft` (blocked), …
- Fan-out: other Craft apps are `status = blocked` in `allowlist.toml` until
  each has a green wasip1 recipe. Do not mass-publish red stubs.

## Related

- [package-versioning.md](package-versioning.md)
- [wawona.io Wayland wasm](https://wawona.io/docs/contributor/wayland-wasm/)
- Host ABI: [wawona.io wasm-host-abi](https://wawona.io/docs/contributor/wasm-host-abi/)
