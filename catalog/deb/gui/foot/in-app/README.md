# wwn-foot

[![CI](https://github.com/Wawona/wwn-foot/actions/workflows/ci.yml/badge.svg)](https://github.com/Wawona/wwn-foot/actions/workflows/ci.yml)

Wawona's [foot](https://codeberg.org/dnkl/foot) terminal port, cross-compiled
in-process for Apple platforms (iOS/iPadOS/tvOS/watchOS/visionOS) and Android.

Patch-overlay model: pristine foot source is fetched and patched at build time.
Built with [wwn-toolchain](https://github.com/Wawona/wwn-toolchain).

## Use

```nix
inputs.wwn-foot.url = "github:Wawona/wwn-foot";
registry = wwn-toolchain.lib.baseRegistry // wwn-foot.registryFragment;
```

## Standalone build

```sh
nix build .#foot-ios
nix build .#foot-macos
```

## License

MIT for the Wawona Nix packaging / patches (see `LICENSE`). foot itself is MIT;
its source is fetched from upstream at build time.
