{
  makeWasmerPackage,
  wayland-bridge-smoke,
}:
makeWasmerPackage {
  package = wayland-bridge-smoke;
  name = "wayland-bridge-smoke";
  commands = [
    {
      name = "wayland-bridge-smoke";
      module = "wayland-bridge-smoke";
      wasm = "wayland-bridge-smoke.wasm";
      output = "wayland-bridge-smoke.wasm";
    }
  ];
}
