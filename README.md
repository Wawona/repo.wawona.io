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
| **`/` APT** (`Packages`, `debs/`) | Jailbroken iOS APT clients **and** Termux | Same source URL `https://repo.wawona.io/`. Split by Architecture. |
| **`/jailbreak/`** | Jailbroken iOS | Bookmark onto the deb catalog. Rootless (`iphoneos-arm64`) and rootful (`iphoneos-arm`). **Not** Termux. **Not** a second APT tree. |
| **`/termux/`** | Sideloaded Android (Termux) | Bookmark onto `aarch64` debs. **Not jailbreak.** **Not Play.** |
| **Mode B `.deb`** | Jailbroken iOS | Full **Wawona Mode B** app for iOS 13+. **Never** submitted to App Store. |

`/wasm/`, `/deb/`, `/jailbreak/`, and `/termux/` HTML pages redirect humans into `/search/`. `wpm` still talks to `/wasm/v1/`. Jailbreak APT clients and Termux still talk to `/`. Do not rank iOS package managers in UI copy.

### Wasm (App Store / Play)

Store / Play Wawona may download Wasm from `/wasm/v1` only. Never APT, never `.deb`.

### Jailbreak debs (iOS)

Rootless and rootful packages for jailbreak APT clients ([docs/packaging.md](docs/packaging.md)). Wawona's Mode B `.deb` starts at iOS 13. The separate TrollStore `.tipa` starts at iOS 14 and is not one of these debs. Neither is an App Store binary.

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
