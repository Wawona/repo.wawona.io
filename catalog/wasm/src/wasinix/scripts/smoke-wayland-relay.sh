#!/usr/bin/env bash
# Run a WASIX Wayland/GTK smoke under a host that provides wawona_wayland_*.
# Plain `wasmer run` without those imports fails closed (by design).
#
# Usage:
#   ./scripts/smoke-wayland-relay.sh wayland-bridge-smoke [path/to.wasm]
#   ./scripts/smoke-wayland-relay.sh gtk4-hello [path/to.wasm]
#
# Requires:
#   - WAYLAND_DISPLAY (or XDG_RUNTIME_DIR/wayland-0) from a live Wawona compositor
#   - WAWONA_RELAY_RUN: command that executes WASIX with Relay host imports
#     Example: export WAWONA_RELAY_RUN='nix run github:Wawona/Relay#… --'
#
# Writes out/smoke/<name>.json (status pass|fail|skip).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: smoke-wayland-relay.sh <wayland-bridge-smoke|gtk4-hello> [wasm]}"
WASM_PATH="${2:-}"
OUT_DIR="$ROOT/out/smoke"
mkdir -p "$OUT_DIR"

write_result() {
  local status="$1"
  local detail="${2:-}"
  python3 - "$OUT_DIR/$NAME.json" "$NAME" "$status" "$detail" <<'PY'
import json, sys
path, name, status, detail = sys.argv[1:5]
payload = {
    "name": name,
    "abi": "wasix",
    "runtime": "relay-wasmer",
    "suite": "wayland",
    "status": status,
    "detail": detail,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
print(f"wrote {path} status={status}")
PY
}

if [[ -z "${WAWONA_RELAY_RUN:-}" ]]; then
  write_result skip "WAWONA_RELAY_RUN unset; need Relay host for wawona_wayland_*"
  exit 0
fi

if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${XDG_RUNTIME_DIR:-}" ]]; then
  write_result fail "WAYLAND_DISPLAY / XDG_RUNTIME_DIR unset"
  exit 1
fi

if [[ -z "$WASM_PATH" ]]; then
  case "$NAME" in
    wayland-bridge-smoke)
      WASM_PATH="$(nix build --no-link --print-out-paths "$ROOT#wasmer.wayland-bridge-smoke")/pkg/wayland-bridge-smoke/bin/wayland-bridge-smoke.wasm"
      ;;
    gtk4-hello)
      WASM_PATH="$(nix build --no-link --print-out-paths "$ROOT#wasmer.gtk4-hello")/pkg/gtk4-hello/bin/gtk4-hello.wasm"
      ;;
    *)
      write_result fail "unknown package $NAME"
      exit 1
      ;;
  esac
fi

test -f "$WASM_PATH" || { write_result fail "missing wasm $WASM_PATH"; exit 1; }

# shellcheck disable=SC2086
if $WAWONA_RELAY_RUN "$WASM_PATH"; then
  write_result pass "relay execute ok"
else
  write_result fail "relay execute failed"
  exit 1
fi
