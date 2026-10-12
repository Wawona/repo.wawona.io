{
  lib,
  stdenvNoCC,
  cargoWasix,
}:
stdenvNoCC.mkDerivation rec {
  pname = "wayland-bridge-smoke";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [cargoWasix];

  buildPhase = ''
    runHook preBuild
    export HOME="$PWD/.home"
    export CARGO_HOME="$HOME/.cargo"
    export RUSTUP_HOME="$HOME/.rustup"
    mkdir -p "$HOME" "$CARGO_HOME" "$RUSTUP_HOME"
    # Host imports are provided at execute time by Relay; allow undefined.
    export RUSTFLAGS="''${RUSTFLAGS:-} -C link-arg=-Wl,--allow-undefined"
    cargo-wasix wasix build --release
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp target/wasm32-wasmer-wasi/release/wayland-bridge-smoke.wasm \
      $out/bin/wayland-bridge-smoke.wasm
    runHook postInstall
  '';

  meta = {
    description = "WASIX Wayland one-frame smoke via wawona_wayland_* (Relay host)";
    homepage = "https://github.com/Wawona/wasinix";
    license = lib.licenses.mit;
  };
}
