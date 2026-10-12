#!/usr/bin/env bash
# Build one recipe package to out/<name>/<ver>/component.wasm
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: build-package.sh <name>}"
RECIPES="$ROOT/recipes.json"

meta="$(python3 - "$RECIPES" "$NAME" <<'PY'
import json, sys
recipes = json.load(open(sys.argv[1]))
name = sys.argv[2]
for p in recipes["packages"]:
    if p["name"] == name:
        print(p["path"])
        print(p["version"])
        print(p["bin"])
        print(p["abi"])
        raise SystemExit(0)
raise SystemExit(f"unknown package: {name}")
PY
)"
path="$(echo "$meta" | sed -n '1p')"
version="$(echo "$meta" | sed -n '2p')"
bin="$(echo "$meta" | sed -n '3p')"
abi="$(echo "$meta" | sed -n '4p')"

if [[ "$abi" != "wasi-p1" ]]; then
  echo "only wasi-p1 builds in this slice (got $abi)" >&2
  exit 1
fi

cd "$ROOT/$path"
cargo build --release --target wasm32-wasip1 --bin "$bin"

out="$ROOT/out/$NAME/$version"
mkdir -p "$out"
cp "target/wasm32-wasip1/release/${bin}.wasm" "$out/component.wasm"
# Reject P1 modules that import wasi_snapshot_preview1 fork-like WASIX names.
if command -v wasm-objdump >/dev/null 2>&1; then
  if wasm-objdump -x "$out/component.wasm" 2>/dev/null | grep -Eiq 'import.*\b(fork|pthread|wasix)\b'; then
    echo "P1 package imports forbidden WASIX/fork symbols" >&2
    exit 1
  fi
fi
python3 - "$out/component.wasm" "$out/digest.txt" <<'PY'
import hashlib, pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
digest = "sha256:" + hashlib.sha256(data).hexdigest()
pathlib.Path(sys.argv[2]).write_text(digest + "\n")
print(digest)
PY
echo "built $out/component.wasm"
