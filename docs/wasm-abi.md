# Wasm ABI labels and later Wasmer registry

Authority for how packages on the **wasm channel** are classified and how the
**later** Wasmer-compatible registry will publish them. Deb / Sileo / Termux
packaging stays in [`packaging.md`](./packaging.md). Do not mix catalogs.

**Status today:** `/wasm/v1` serves Mode A `wpm` via `index.json` and
`.wasm` blobs. That path stays live.

**Status later (planned):** `repo.wawona.io/wasm` becomes a curated
Wasmer-compatible registry. Distribution unit is WebC (`.webc`) via
`wasmer publish`. Orchestration is upstream
[`wasix-org/wasinix`](https://github.com/wasix-org/wasinix), not a
Wawona-written nixpkgs converter. `nixpkgs2wasi` / `n2w` are retired. Do not
revive them. A later fork adds a `wawona` publication profile whose registry
URL is `repo.wawona.io`.

## Package names

Namespaced Wasmer-style names. ABI prefix in the name when useful:

| Example | Meaning |
|---------|---------|
| `wawona/wasi-p1-grep` | WASI Preview 1 CLI |
| `wawona/wasi-p2-…` | WASI Preview 2 / Component Model |
| `wawona/wasix-ripgrep` | WASIX (Wasmer-only POSIX) |

## One ABI label per package

Label from the **syscalls the binary actually uses**. Never mark a package P1
if it calls `fork`, threads, or WASIX sockets.

| Label | Target triple | What it may use | Runtimes / toolchain |
|-------|---------------|-----------------|----------------------|
| **WASI P1** | `wasm32-wasip1` | stdio, basic files | Wasmtime, Wasmer, WAMR, WasmEdge. C: wasi-sdk |
| **WASI P2** | `wasm32-wasip2` | Component Model. Wrap a P1 module plus the Preview 1 adapter with `wasm-tools component new` when needed | Component-capable runtimes |
| **WASIX** | `wasm32-wasix` | fork, threads, sockets, epoll, TTYs, signals, POSIX filesystem | **Wasmer only**. Toolchain: wasixcc, cargo-wasix, wasinix dev shell |

Coverage intent:

- **P1 CLI** is the large set (nixpkgs-sourced userspace that fits Preview 1).
- **WASIX** covers POSIX CLI and language runtimes that need real process /
  socket / TTY semantics.
- **Wayland clients and full desktops** wait on Mesa and the WASIX socket
  bridge into Wawona. Do not claim desktop wasm until those are proven.

## `wasmer.toml` metadata

Publish with `[package.metadata]` carrying at least:

| Key | Meaning |
|-----|---------|
| `abi` | `wasi-p1` \| `wasi-p2` \| `wasix` |
| `abi-target` | `wasm32-wasip1` \| `wasm32-wasip2` \| `wasm32-wasix` |
| `runtime` | Declared execute engines (e.g. `wasmer`, `wasmtime`) |
| `posix` | Whether POSIX process/FS surface is required |
| `wayland` | Whether the package is a Wayland client |

Provenance on every publish: source revision, rebuild command, and the ABI
label. CI builds the declared target, smoke-tests, **rejects a P1 package that
calls `fork`**, emits `.webc`, then `wasinix publish` (or `wasmer publish`
through the wawona profile).

## Phase order (when packaging work starts)

Not started in the tip that only adds this doc. Order when it starts:

1. **Fork wasinix.** Point the `wawona` publication profile at
   `repo.wawona.io/wasm`.
2. **P1 CLI set** (curated from nixpkgs via wasinix, not a Wawona converter):
   coreutils, busybox, grep, sed, awk, gzip, curl, wget, jq, git, make,
   cmake, CPython core, lua, sqlite3, openssl CLI.
3. **Five WASIX tools**, including bash and nix. wasinix already ships some
   WASIX packages (zlib, git). New recipes follow wasinix
   `docs/packaging.md`.
4. **One Wayland proof** (Weston terminal client), then a small GTK client.
   Open questions: libwayland-client and Mesa on `wasm32-wasix`, and how the
   WASIX socket reaches Wawona.

## Product rules (same-commit gate before WASIX is “runnable everywhere”)

Keep these as hard product law. When the first WASIX package is treated as
runnable beyond Wasmer-capable paths, update the listed rules **in the same
commit**. Until then, do not link Wasmer into macOS/Linux products and do not
claim WASIX runs on store Pulley.

| Constraint | Today | Later same-commit update |
|------------|-------|--------------------------|
| Store iOS / iPadOS through OS 26 | Pulley only | Unchanged: a WASIX package does **not** run on store Pulley |
| Store iOS / iPadOS 27+ Mode A | Wasmer WASIX in hidden WKWebView when `WasmerSDK` / `WWN_WASMER_IOS27` is linked; else Pulley | May run ABI-matching Wasmer packages when that path is linked |
| macOS / Linux | Wasmtime Cranelift; `wawona-relay-wasm` forbids a second Wasmer engine beside it | WASIX-as-Wasmer-only **changes** that rule. Do not land Wasmer link without updating `wawona-relay-wasm` and product docs |
| `wpm install` | Wasm bytecode / registry blobs | Stays bytecode (or WebC as Wasm package data). **Never** `docker pull`. Containers stay Machines kind `container` |

Hard rejects until the gate lands:

- Claim WASIX runs on store Pulley or on iOS / iPadOS ≤ 26 Mode A
- Link Wasmer into macOS / Linux “for WASIX” inside a docs-only or registry-only tip
- Treat `wpm` as a container or OCI runtime
- Auto-mirror all of nixpkgs into `/wasm/`
- Revive `nixpkgs2wasi` / `n2w` as the producer

## Today vs later (firewall)

| Surface | Today | Later |
|---------|-------|-------|
| Machine API | `/wasm/v1/index.json` + `.wasm` | Wasmer/WebC publish profile; keep or evolve `/wasm/v1` for `wpm` without breaking store clients |
| Humans | `/search/?channel=wasm` | Same channel; show ABI labels when present |
| Producer | Manual / curated blobs | wasinix + `wawona` profile |
| Deb APT | Separate | Still separate. Never one list |

See also: [`../wasm/README.md`](../wasm/README.md),
[Wawona `wasm-package-manager.md`](https://github.com/Wawona/Wawona/blob/development/docs/wasm-package-manager.md),
[`wawona-relay-wasm`](https://github.com/Wawona/Wawona/blob/development/docs/agent-rules/wawona-relay-wasm.md).
