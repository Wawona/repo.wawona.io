# Chess for Wawona

WASI Preview 1 Wayland client with a software-rendered 2D board. Standard,
Crazyhouse, Suicide and Losers; pointer/touch input, UCI/SAN moves and drops,
promotion choices, undo/redo and optional computer play as Black.

Run `wasm ./component.wasm`. Once published: `wpm install chess-wawona`,
then `wasm chess-wawona`. Games are in memory only; no persistence, network,
speech, recording or 3D board in this frontend. Keyboard text assumes US evdev
keycodes. The package requests Wayland, with no filesystem or network access.

Source and build instructions: https://github.com/cube-one-ber/chess-for-linux/tree/cd308076abf666738ff1698966e3f94a9ac9129d/wasm

Built by GitHub Actions with Rust 1.95.0 for `wasm32-wasip1`, reusing the native application's
Rust rules and engine. The transport/font adapt Wawona's MIT example.
See LICENSE, LICENSE.wawona and licenses/ for notices.

Validation: compiled-wasm pointer, touch, keyboard and computer-reply checks,
resize, ping/pong, SHM cleanup and a real buffer commit to headless Weston.
Apple/Android Wawona device validation is still pending.

Digest: sha256:b7b008a45e01d7d14f2cdd28d03c3b9680a9fe3193db99202758d16f17deec0a
