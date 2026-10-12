{
  makeWasmerPackage,
  gtk4-hello,
}:
makeWasmerPackage {
  package = gtk4-hello;
  name = "gtk4-hello";
  owner = "wawona";
  version = gtk4-hello.version;
  description = gtk4-hello.meta.description or "Hello, Wayland World! GTK4 WASIX";
  license = "MIT";
  metadata = {
    abi = "wasix";
    abi-target = "wasm32-wasix";
    runtime = "wasmer";
    posix = true;
    wayland = true;
    wawona-host = "wawona_wayland_*";
  };
  commands = [
    {
      name = "gtk4-hello";
      module = "gtk4-hello";
      wasm = "gtk4-hello.wasm";
      output = "gtk4-hello.wasm";
    }
  ];
}
