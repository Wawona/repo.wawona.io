# Jailbreak test debs (rootless and rootful)

Both variants are rows in the root APT index (`Packages`, `debs/`). Sileo,
Irisin, Zebra, and Cydia use `https://repo.wawona.io/`. `/jailbreak/` is a bookmark onto
`/search/?channel=deb`. It is not a second package tree.

| Scheme | Architecture | Device |
|---|---|---|
| rootless | `iphoneos-arm64` | Dopamine, palera1n rootless |
| rootful | `iphoneos-arm` | checkra1n, unc0ver, palera1n rootful |
| RootHide | `iphoneos-arm64e` | RootHide |

Packages:

- `com.aspauldingcode.wawona.modeb.demo` rootless and, as a separate build,
  rootful. Framebuffer and JIT proof (IOMFB plasma, Hello text, fib HUD).
  Built by `Wawona/scripts/build-modeb-demo-tipa.sh` next to the TrollStore
  `.tipa`. Same signed binary. Not App Store.
- `com.aspauldingcode.wawona` rootless and, as a separate build, rootful
- `com.aspauldingcode.wawona.desktop-tweak` (`Depends: ellekit`, rootless)
- optional log-only smoke tweak

Build with `mkWawonaPackage` `jailbreakScheme = "rootless"` or `"rootful"`.
Never under `/wasm/`. Never in a store IPA.
