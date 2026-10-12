{
  stdenvNoCC,
  cargoWasix,
}:
stdenvNoCC.mkDerivation {
  pname = "crabsay";
  version = "0.1.0";

  # Upstream github.com/nevzheng/crabsay is gone (404). In-tree smoke binary.
  src = ./.;

  nativeBuildInputs = [cargoWasix];

  buildPhase = ''
    runHook preBuild
    export HOME="$PWD/.home"
    export CARGO_HOME="$HOME/.cargo"
    export RUSTUP_HOME="$HOME/.rustup"
    mkdir -p "$HOME" "$CARGO_HOME" "$RUSTUP_HOME"
    cargo-wasix wasix build --release
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp target/wasm32-wasmer-wasi/release/crabsay.wasm "$out/bin/crabsay.wasm"
    runHook postInstall
  '';
}
