{ }:
{
  channel = "wasm";
  kind = "cli";
  abi = "wasi-p1";
  pname = "hello-wasi";
  wayland = false;
  src = ../../src/p1;
}
