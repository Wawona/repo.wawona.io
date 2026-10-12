# watchOS: no iland DRM/GL backend (platform-targets matrix).
args: import ./compositor-apple-mobile.nix (args // { enableIlandDrm = false; })
