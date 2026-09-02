# ElleKit tweak scaffold: Wawona SpringBoard Desktop smoke (rootless)

Rootless Sileo only. `Depends: ellekit`. Never linked into store IPA or TrollStore `.tipa`.

```bash
# After Theos + THEOS_PACKAGE_SCHEME=rootless:
# make package
```

Control sketch:

```
Package: com.aspauldingcode.wawona.desktop-tweak
Depends: ellekit, firmware (>= 15.0)
Architecture: iphoneos-arm64
Description: Wawona Desktop/LockScreen SpringBoard inject (Mode B Sileo)
```

Tweak logs on load so vphone `jb` guests can prove the repo package installed:

```objc
__attribute__((constructor)) static void wawona_desktop_tweak_init(void) {
  NSLog(@"[WawonaDmabuf] op=present os=ios sink=iomfb client=ellekit_tweak copy=zero scaffolding");
}
```

Full Logos hooks for SpringBoard greeter land with the Desktop Mode B product.
Publish under `repo.wawona.io/jailbreak/` (test pocket until merge).
