# Packaging Guide for Wawona Software (Rootless + RootHide)

This guide provides technical specifications for packaging and distributing software via the Wawona repository, including older rootful jailbreaks and modern rootless jailbreaks such as Dopamine and RootHide.

## 1. Overview
Rootless and RootHide target modern devices, commonly iOS 15+. Wawona's Sileo
Mode B product itself has an **iOS 13.0** Mach-O floor: use the rootful
`iphoneos-arm` package where an older jailbreak requires it. Do not claim that
RootHide supports iOS 11-14.

### Key Difference: jbroot Path
- **Standard Rootless**: Uses a fixed path `/var/jb`.
- **RootHide**: Uses a **randomized** directory name for the "jbroot" for improved detection evasion.

## 2. Development Requirements

### include <roothide.h>
Software should include the RootHide header to handle path resolution dynamically. 
```c
#include <roothide.h>

// Use jbroot() to convert a virtual path to the actual system path
const char* path = jbroot("/var/mobile/Library/Wawona/config.plist");
```
When compiling for standard Rootless, these become empty stubs, ensuring 100% cross-compatibility.

### Entitlements
To function outside the standard app sandbox, binaries must be signed with the following entitlements:
```xml
<key>platform-application</key>
<true/>
<key>com.apple.private.security.no-sandbox</key>
<true/>
<key>com.apple.private.security.storage.AppBundles</key>
<true/>
<key>com.apple.private.security.storage.AppDataContainers</key>
<true/>
```

## 3. Building for RootHide
The easiest way to build compatible packages is using the RootHide fork of **Theos**.

1. **Build Step**:
   ```bash
   make package THEOS_PACKAGE_SCHEME=roothide
   ```
2. **Dynamic Linking**:
   RootHide uses `@loader_path/.jbroot/` in the `install_name` for libraries to ensure they can find dependencies regardless of the randomized jbroot path.

## 4. Repository Metadata
The Wawona repository automated scripts handle these fields for you, but for manual packaging, ensure the following are set in the `control` file:

- **Architecture** (this is what Sileo matches): `iphoneos-arm` rootful,
  `iphoneos-arm64` rootless, or `iphoneos-arm64e` RootHide. Termux is
  `aarch64`, not these.
- **Maintainer**: required. `Full Name <email>` where the name is the GitHub
  profile name (queried from `api.github.com/users/<login>`, never typed) and
  the email is in `maintainers.json`. Today that is
  `Alex Spaulding <aspauldingcode@gmail.com>` for GitHub user `aspauldingcode`.
- **RootHide Tag**: For packages specifically tested on RootHide, add `roothide: true` and `roothide::compatible` tagging.

Recipes must set `sileo.maintainers = [ "aspauldingcode" ];`. Run
`python3 scripts/check-packages.py` before publishing. Humans browse debs at
`/search/?channel=deb`. Sileo still uses `https://repo.wawona.io/` as the
source URL. `/jailbreak/` is a bookmark onto that catalog for **jailbroken iOS**
(rootless and rootful). Termux Android sideload debs use the same APT URL and
are **not jailbreak**; bookmark `/termux/`. Store `wpm` stays on `/wasm/v1`.

## 5. Directory Structure Guidelines
- **Data Storage**: Store all app/binary data in `/var/` within the jbroot.
- **Reserved Paths**: `/System/` in jbroot is reserved for system mirroring; do not store files there.
- **Macho Loading**: Executables, frameworks, or dylibs stored in `jbroot:/var` or `jbroot:/tmp` **cannot** be loaded by iOS security; place them in other jbroot directories.

## 6. Rootful, rootless, and RootHide (one deb each)

Sileo installs the stanza whose `Architecture` matches the device. Rootful and
rootless are different builds, not a renamed tree. The same package id may
appear twice in the root `Packages` index when the architectures differ.
`/jailbreak/` is only the Sileo bookmark onto `/search/?channel=deb`. It is
not a second APT tree. Never put these debs under `/wasm/`.

| Scheme | `jailbreakScheme` | dpkg `Architecture` | On-device prefix | Sileo control |
|---|---|---|---|---|
| rootless | `"rootless"` | `iphoneos-arm64` | `/var/jb` | `Tag: role::developer` |
| rootful | `"rootful"` | `iphoneos-arm` | `/` | `Tag: role::developer` |
| RootHide | `"roothide"` | `iphoneos-arm64e` | `/var/jb` (`jbroot()` at runtime) | `RootHide: true` and `Tag: role::tweak, roothide::compatible` |

`mkWawonaPackage` writes that `Architecture` from `jailbreakScheme`. The repo
`Release` file must list `iphoneos-arm` or rootful Sileo will not see the
index. GitHub names: `Wawona-{calver}-iOS-arm64-rootless.deb` and
`…-rootful.deb`. Deb filenames include the architecture
(`name_version_iphoneos-arm.deb`).

Rootless SpringBoard tweaks set `sileo.depends = "ellekit";`. Never link
ElleKit into an App Store IPA or a TrollStore `.tipa`.

Leave `jailbreakScheme` unset for an existing recipe that already sets
`sileo.architecture`. Do not set both to different arches.
