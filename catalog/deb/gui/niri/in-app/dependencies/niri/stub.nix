# Port stub for niri. Evaluates cleanly (so registryFragment merges and CI can
# enumerate the target) but fails the build with a clear message until the real
# cross-compiled port lands. Replace with a proper derivation per platform.
{ ... }:
throw "wwn-niri: niri port is not implemented yet (scaffold only). See README.md port plan."
