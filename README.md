# Wawona Repo

Hosted at [repo.wawona.io](https://repo.wawona.io)

## Channels (do not mix)

App Store / Play compliance is **wasm only**. Debs never go in store binaries.

| Path / artifact | Audience | Contents |
|-----------------|----------|----------|
| **`/search/`** | Humans | Chooser. Wasm and debs are never one list. |
| **`/search/?channel=wasm`** | Humans (Mode A) | App Store / Play wasm catalog for `wpm`. Store compliance. |
| **`/search/?channel=deb`** | Humans | APT debs. Two audiences on one `Packages` file. |
| **`/wasm/v1/`** | App Store, Play, macOS (`wpm`) | WASI `.wasm` packages for **Wawona Runtime**. Do not redirect this tree. |
| **`/` APT** (`Packages`, `debs/`) | Sileo, Irisin, Zebra, Cydia, **and** Termux | Same source URL `https://repo.wawona.io/`. Split by Architecture. |
| **`/jailbreak/`** | Jailbroken iOS (Sileo, then Irisin, then Zebra, then Cydia) | Bookmark onto the deb catalog. Rootless (`iphoneos-arm64`) and rootful (`iphoneos-arm`). Irisin is iOS 16 or later, rootless and roothide. Cydia is last, for older jailbreaks such as iOS 13. **Not** Termux. **Not** a second APT tree. |
| **`/termux/`** | Sideloaded Android (Termux) | Bookmark onto `aarch64` debs. **Not jailbreak.** **Not Play.** |
| **Mode B `.deb`** | Jailbroken iOS (Sileo, Irisin, Zebra, Cydia) | Full **Wawona Mode B** app for iOS 11+. **Never** submitted to App Store. |

`/wasm/`, `/deb/`, `/jailbreak/`, and `/termux/` HTML pages redirect humans into `/search/`. `wpm` still talks to `/wasm/v1/`. Sileo, Irisin, Zebra, Cydia, and Termux still talk to `/`.

### Wasm (App Store / Play)

Store / Play Wawona may download Wasm from `/wasm/v1` only. Never APT, never `.deb`.

### Jailbreak debs (iOS)

Rootless and rootful packages for Sileo, Irisin, Zebra, and Cydia ([docs/packaging.md](docs/packaging.md)). Wawona's Mode B `.deb` starts at iOS 11. The separate TrollStore `.tipa` starts at iOS 14 and is not one of these debs. Neither is an App Store binary.

### Termux debs (sideloaded Android)

Termux `apt` on a sideloaded Termux app. This is **not** Android jailbreak, **not** Magisk, and **not** Play Store.

Plan: [mode-a-b.md](https://github.com/Wawona/Wawona/blob/development/docs/mode-a-b.md),
[wasm-package-manager.md](https://github.com/Wawona/Wawona/blob/development/docs/wasm-package-manager.md).

Agents: read `.cursor/skills/repo-wawona-io-priors/SKILL.md` before editing.
Write new catalog learnings into those skills (rule `repo-wawona-io-agent-learn`).

## Historical note

Older docs said App Store builds must never touch this host. That was when the
host was APT-only. **`/wasm/v1`** is the store-safe exception. APT debs and
Mode B IPA remain off-limits inside store binaries.
