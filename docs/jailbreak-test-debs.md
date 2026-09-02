# Test debs for vphone jb / Dopamine rootless

Publish under `/jailbreak/test/` while on `dma-buf-zero-copy`. Promote to live
`/jailbreak/` only with the development merge.

Packages:
- `com.aspauldingcode.wawona` rootless (`Architecture: iphoneos-arm64`)
- `com.aspauldingcode.wawona.desktop-tweak` (`Depends: ellekit`)
- optional `wawona-vphone-smoke` log-only tweak

Built from Wawona Mode B `.app` via `scripts/package-ios-mode-b.sh` and
`mkWawonaPackage.nix` `jailbreakScheme = "rootless"`. Never under `/wasm/`.
Never in store IPA.
