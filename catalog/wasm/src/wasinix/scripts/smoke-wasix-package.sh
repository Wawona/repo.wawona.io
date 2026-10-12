#!/usr/bin/env bash
# Smoke one WASIX package with Wasmer. Never Wasmtime (that is wasm-packages P1/P2).
# Usage: smoke-wasix-package.sh <name> [wasm-path]
# Looks up expectations in smokes.toml. Writes out/smoke/<name>.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: smoke-wasix-package.sh <name> [wasm-path]}"
WASM_PATH="${2:-}"
OUT_DIR="$ROOT/out/smoke"
mkdir -p "$OUT_DIR"

write_result() {
  local status="$1"
  local detail="${2:-}"
  python3 - "$OUT_DIR/$NAME.json" "$NAME" "$status" "$detail" "${rc:-}" <<'PY'
import json, sys
path, name, status, detail, rc = sys.argv[1:6]
payload = {
    "name": name,
    "abi": "wasix",
    "runtime": "wasmer",
    "status": status,
    "detail": detail,
}
if rc != "":
    try:
        payload["exit_code"] = int(rc)
    except ValueError:
        pass
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
print(f"wrote {path} status={status}")
PY
}

fail() {
  echo "smoke failed $NAME: $1" >&2
  write_result fail "$1" || true
  exit 1
}

eval "$(python3 "$ROOT/scripts/read_smokes.py" env "$NAME")"
smoke_stdin="$(python3 -c 'import base64,sys; sys.stdout.write(base64.b64decode(sys.argv[1]).decode("utf-8"))' "$smoke_stdin_b64")"

if [[ "$smoke_status" == "skip" ]]; then
  write_result skip "${smoke_reason:-skipped}"
  echo "smoke skip $NAME: ${smoke_reason:-}"
  exit 0
fi

if ! command -v wasmer >/dev/null 2>&1; then
  fail "wasmer required for WASIX smoke"
fi

if [[ -z "$WASM_PATH" ]]; then
  for cand in \
    "$ROOT/result/pkg/$NAME/bin/$wasm_name" \
    "$ROOT/result/bin/$wasm_name" \
    "$ROOT/out/wasm/$NAME/$wasm_name" \
    "$ROOT/out/$NAME/$wasm_name"
  do
    if [[ -f "$cand" ]]; then
      WASM_PATH="$cand"
      break
    fi
  done
fi
[[ -n "$WASM_PATH" && -f "$WASM_PATH" ]] || fail "wasm not found for $NAME (pass path as \$2)"

mapfile -t smoke_args < <(python3 -c 'import json,sys; [print(a) for a in json.loads(sys.argv[1])]' "$smoke_args_json")

set +e
if [[ -n "$smoke_stdin" ]]; then
  if [[ ${#smoke_args[@]} -gt 0 ]]; then
    out="$(printf '%s' "$smoke_stdin" | wasmer run "$WASM_PATH" -- "${smoke_args[@]}" 2>&1)"
  else
    out="$(printf '%s' "$smoke_stdin" | wasmer run "$WASM_PATH" 2>&1)"
  fi
  rc=$?
else
  if [[ ${#smoke_args[@]} -gt 0 ]]; then
    out="$(wasmer run "$WASM_PATH" -- "${smoke_args[@]}" 2>&1)"
  else
    out="$(wasmer run "$WASM_PATH" 2>&1)"
  fi
  rc=$?
fi
set -e

want_rc="${smoke_exit:-0}"
[[ "$rc" -eq "$want_rc" ]] || fail "rc=$rc want=$want_rc out=$out"

if [[ -n "$smoke_expect" ]]; then
  echo "$out" | grep -Fq "$smoke_expect" || fail "missing substring $smoke_expect (got: $out)"
fi

write_result pass "ok"
echo "smoke ok $NAME runtime=wasmer abi=wasix"
