# ElleKit tweak scaffold: Wawona SpringBoard Desktop smoke (rootless)

Rootless Sileo only. `Depends: ellekit`. Never linked into a store IPA or a
TrollStore `.tipa`.

```bash
# After Theos + THEOS_PACKAGE_SCHEME=rootless:
# make package
```

The published `.deb` is a row in the root APT index (`debs/`, `Packages`).
Sileo uses `https://repo.wawona.io/`. `/jailbreak/` is the bookmark onto
`/search/?channel=deb`, not the package tree.

Control sketch (`jailbreakScheme = "rootless"`):

```
Package: com.aspauldingcode.wawona.desktop-tweak
Depends: ellekit, firmware (>= 15.0)
Architecture: iphoneos-arm64
Tag: role::developer
Description: Wawona Desktop/LockScreen SpringBoard inject (Mode B Sileo)
```

Tweak logs on load so a jailbreak guest can prove the package installed:

```objc
__attribute__((constructor)) static void wawona_desktop_tweak_init(void) {
  NSLog(@"[WawonaDmabuf] op=present os=ios sink=iomfb client=ellekit_tweak copy=zero scaffolding");
}
```

Full Logos hooks for a SpringBoard greeter land with the Desktop Mode B product.
