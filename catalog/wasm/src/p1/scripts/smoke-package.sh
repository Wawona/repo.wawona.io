#!/usr/bin/env bash
# Smoke-test one built package with Wasmtime (WASI P1 / P2 only).
# Writes out/<name>/<version>/smoke-result.json (pass|fail).
# Exit 0 = pass, 1 = fail. Never use Wasmer here (WASIX = wasinix lane).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: smoke-package.sh <name>}"
RECIPES="$ROOT/recipes.json"
RESULT_DIR=""

write_result() {
  local status="$1"
  local detail="${2:-}"
  local path="${RESULT_DIR}/smoke-result.json"
  mkdir -p "$RESULT_DIR"
  python3 - "$path" "$NAME" "${version:-}" "${abi:-}" "$status" "$detail" "${rc:-}" <<'PY'
import json, sys
path, name, version, abi, status, detail, rc = sys.argv[1:8]
payload = {
    "name": name,
    "version": version or None,
    "abi": abi or None,
    "runtime": "wasmtime",
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
  local msg="$1"
  echo "smoke failed $NAME: $msg" >&2
  write_result fail "$msg" || true
  exit 1
}

eval "$(python3 - "$RECIPES" "$NAME" <<'PY'
import json, shlex, sys
recipes = json.load(open(sys.argv[1]))
name = sys.argv[2]
for p in recipes["packages"]:
    if p["name"] == name:
        print(f"version={shlex.quote(p['version'])}")
        print(f"abi={shlex.quote(p.get('abi') or 'wasi-p1')}")
        expect = p.get("smoke_expect")
        print(f"smoke_expect={shlex.quote('' if expect is None else expect)}")
        args = p.get("smoke_args") or []
        print(f"smoke_args_json={shlex.quote(json.dumps(args))}")
        stdin = p.get("smoke_stdin")
        print(f"smoke_stdin={shlex.quote('' if stdin is None else stdin)}")
        print(f"smoke_exit={int(p.get('smoke_exit') or 0)}")
        raise SystemExit(0)
raise SystemExit(f"unknown package: {name}")
PY
)"

RESULT_DIR="$ROOT/out/$NAME/$version"
wasm="$RESULT_DIR/component.wasm"
[[ -f "$wasm" ]] || fail "missing $wasm"

case "$abi" in
  wasi-p1|wasi-p2) ;;
  wasix)
    fail "abi=wasix belongs in wasinix (Wasmer). Do not smoke with wasmtime here."
    ;;
  *)
    fail "unsupported abi=$abi (want wasi-p1 or wasi-p2)"
    ;;
esac

if ! command -v wasmtime >/dev/null 2>&1; then
  fail "wasmtime required for WASI P1/P2 smoke"
fi

mapfile -t smoke_args < <(python3 -c 'import json,sys; [print(a) for a in json.loads(sys.argv[1])]' "$smoke_args_json")

# P2 components need the component-model feature on older Wasmtime; v25+ enables it.
wasmtime_cmd=(wasmtime run)
if [[ "$abi" == "wasi-p2" ]]; then
  wasmtime_cmd=(wasmtime run -W component-model)
fi

# Do not pass a bare "--" after the module: wasmtime forwards it to the guest.
set +e
if [[ -n "$smoke_stdin" ]]; then
  if [[ ${#smoke_args[@]} -gt 0 ]]; then
    out="$(printf '%s' "$smoke_stdin" | "${wasmtime_cmd[@]}" "$wasm" "${smoke_args[@]}" 2>&1)"
  else
    out="$(printf '%s' "$smoke_stdin" | "${wasmtime_cmd[@]}" "$wasm" 2>&1)"
  fi
  rc=$?
else
  if [[ ${#smoke_args[@]} -gt 0 ]]; then
    out="$("${wasmtime_cmd[@]}" "$wasm" "${smoke_args[@]}" 2>&1)"
  else
    out="$("${wasmtime_cmd[@]}" "$wasm" 2>&1)"
  fi
  rc=$?
fi
set -e

if [[ "$NAME" == "wasi-true" ]]; then
  [[ "$rc" -eq 0 ]] || fail "wasi-true rc=$rc out=$out"
  write_result pass "rc=0"
  echo "smoke ok $NAME runtime=wasmtime abi=$abi rc=0"
  exit 0
fi

want_rc="${smoke_exit:-0}"
[[ "$rc" -eq "$want_rc" ]] || fail "rc=$rc want=$want_rc out=$out"

if [[ "$want_rc" -ne 0 ]]; then
  write_result pass "rc=$rc (expected non-zero)"
  echo "smoke ok $NAME runtime=wasmtime abi=$abi rc=$rc"
  exit 0
fi

if [[ -n "$smoke_expect" ]]; then
  echo "$out" | grep -Fq "$smoke_expect" || fail "missing substring $smoke_expect (got: $out)"
fi

write_result pass "ok"
echo "smoke ok $NAME runtime=wasmtime abi=$abi"
