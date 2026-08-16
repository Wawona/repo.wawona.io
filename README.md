# Wawona Repo

Hosted at [repo.wawona.io](https://repo.wawona.io)

## Two channels (do not mix)

| Path | Audience | Contents |
|------|----------|----------|
| **`/wasm/`** | App Store, Play, macOS Wawona | WASI `.wasm` packages for **Wawona Runtime** only |
| **`/jailbreak/`** (APT / Sileo) | Jailbroken iOS (+ Termux where applicable) | **`.deb` tweaks** (Desktop, anowaW Mode B, …) |

### Wasm channel (Mode A — store-safe)

Store / Play builds of Wawona may download **Wasm bytecode** from `/wasm/` as
input to the reviewed in-app WASI interpreter. Packages are **not** iOS/Android
apps and **not** Mach-O/ELF.

Plan: [Wawona `docs/wasm-package-manager.md`](https://github.com/Wawona/Wawona/blob/development/docs/wasm-package-manager.md).

### Jailbreak channel (Mode B — stays)

This repo continues to host a **Debian APT flat repo** for jailbroken iOS
(Procursus / Sileo) and related tweak packaging. See [docs/packaging.md](docs/packaging.md).

**Store-shaped Wawona binaries must never link, list, or install from the
jailbreak APT tree.** Website Mode B docs may; the App Store IPA must not.

## Historical note

Older docs said App Store builds must never touch `repo.wawona.io` at all —
that was when this host was APT-only. The Wasm path is the store-safe exception;
the firewall is now **path-based**, not host-based.
