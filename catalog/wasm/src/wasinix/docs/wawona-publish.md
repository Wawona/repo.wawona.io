# Wawona publish profile (wasinix)

This fork (`github.com/Wawona/wasinix`) is the **Nix → WASIX / WebC** producer
for Wawona. It is not `nixpkgs2wasi`. Do not revive `n2w`.

## Registry target

| Field | Value |
|-------|--------|
| Registry host | `https://repo.wawona.io/wasm` |
| Package owner | `wawona` (Wasmer-style `wawona/<name>`) |
| ABI | Prefer `wasix` metadata; never label WASIX as store `wasi-p1` |
| Store P1 today | Still built in `Wawona/wasm-packages` allowlist (Pulley / Wasmtime) |

## Build + Wasmer smoke

Every active row in `smokes.toml` must pass under **Wasmer** in CI
(`smoke-wasix-package.sh`). Store P1/P2 uses Wasmtime in `wasm-packages`.

```bash
nix build .#wasmer.grep
./scripts/smoke-wasix-package.sh grep result/pkg/grep/bin/grep.wasm
nix build .#wasmerAll   # or .#all
```

Plain wasm: `nix build .#wasix.grep`. Wasmer/WebC layout lands under `result/pkg`.

## Publish (operator)

1. Build the Wasmer package on a Linux x86_64 Nix builder (GHA or lab).
2. Set package owner to `wawona` in `makeWasmerPackage` call sites (or pass
   `owner = "wawona"`).
3. `wasmer publish` (or future `wasinix publish`) against the wawona profile
   whose registry URL is `repo.wawona.io`.
4. Keep `/wasm/v1/index.json` for Mode A `wpm` until clients understand WebC /
   WASIX labels. Do not dump WASIX into P1 index rows.

## CLI coverage intent

Relevant everywhere Linux CLIs. Priority queue (wasinix recipes first when
upstream has them):

grep, sed, find, gzip, tar, less, nano, curl, wget, git, bash, make, cmake,
python3, openssl, xz, bzip2, diff, patch, xargs, file, rsync, tmux, vim, ssh.

Store-safe P1 subsets ship from `wasm-packages` (`cli-kit` + small ports) until
Wasmer is a product execute path for that target.
