{ }:
{
  channel = "wasm";
  kind = "cli";
  abi = "wasi-p1";
  pname = "protocol-probe";
  wayland = true;
  src = ../../src/p1;
}
