# Packaging Guide for Wawona Software (Rootless + RootHide)

This guide provides technical specifications for packaging and distributing software via the Wawona repository, ensuring compatibility with modern iOS jailbreaks like Dopamine (Rootless) and RootHide.

## 1. Overview
The primary goal is supporting **iphoneos-arm64e** architecture on iOS 15.0 - 17.0+. Both Rootless and RootHide are "root-less" environments, meaning they do not have access to the `/` root filesystem and instead operate within a designated sandbox or "jbroot".

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

- **Architecture**: `iphoneos-arm64` OR `iphoneos-arm64e`
- **Maintainer**: required. `Full Name <email>` where the name is the GitHub
  profile name (queried from `api.github.com/users/<login>`, never typed) and
  the email is in `maintainers.json`. Today that is
  `Alex Spaulding <aspauldingcode@gmail.com>` for GitHub user `aspauldingcode`.
- **RootHide Tag**: For packages specifically tested on RootHide, add `roothide: true` and `roothide::compatible` tagging.

Recipes must set `sileo.maintainers = [ "aspauldingcode" ];`. Run
`python3 scripts/check-packages.py` before publishing.

## 5. Directory Structure Guidelines
- **Data Storage**: Store all app/binary data in `/var/` within the jbroot.
- **Reserved Paths**: `/System/` in jbroot is reserved for system mirroring; do not store files there.
- **Macho Loading**: Executables, frameworks, or dylibs stored in `jbroot:/var` or `jbroot:/tmp` **cannot** be loaded by iOS security; place them in other jbroot directories.
