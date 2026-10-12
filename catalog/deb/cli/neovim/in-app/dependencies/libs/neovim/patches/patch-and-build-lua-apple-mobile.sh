#!/usr/bin/env bash
# Patch bundled PUC Lua for Apple mobile, then build liblua.a.
set -euo pipefail

lua_src="$1"
install_top="$2"
make_prog="$3"
cflags="${4:-${MYCFLAGS:-${CFLAGS:-}}}"
root="$(cd "$(dirname "$0")" && pwd)"
ar_bin="${AR:-ar}"
ranlib_bin="${RANLIB:-ranlib}"
cc_bin="${CC:-cc}"

python3 "$root/patch-lua-loslib-apple-mobile.py" "$lua_src/loslib.c"

cd "$lua_src"
objs="lapi.o lcode.o ldebug.o ldo.o ldump.o lfunc.o lgc.o llex.o lmem.o lobject.o lopcodes.o lparser.o lstate.o lstring.o ltable.o ltm.o lundump.o lvm.o lzio.o lauxlib.o lbaselib.o ldblib.o liolib.o lmathlib.o loslib.o ltablib.o lstrlib.o loadlib.o linit.o"
for obj in $objs; do
  base="${obj%.o}"
  src="${base}.c"
  [ -f "$src" ] || continue
  "$cc_bin" -O2 -g3 -fPIC -Wall $cflags -c -o "$obj" "$src"
done
"$ar_bin" -rcs liblua.a $objs
"$ranlib_bin" liblua.a
