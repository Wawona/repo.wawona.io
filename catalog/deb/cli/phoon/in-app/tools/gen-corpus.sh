#!/usr/bin/env bash
# Capture a curated reference corpus from the original `phoon` binary into
# tests/reference/*.txt plus tests/reference/manifest.txt. These fixtures are
# the reference program's *output* and serve as the compatibility oracle for
# `cargo test`. Requires PHOON_REF (+ PHOON_FIXTIME on macOS for deterministic
# easter eggs). Run from the repo root.
set -eu

REF="${PHOON_REF:?set PHOON_REF}"
FIX="${PHOON_FIXTIME:-}"
OUT="tests/reference"
mkdir -p "$OUT"
MAN="$OUT/manifest.txt"

{
  echo "# phoon-rs reference corpus. Fields: name<TAB>numlines<TAB>unix_time<TAB>clock"
  echo "# Fixtures in tests/reference/<name>.txt are byte-exact stdout from the"
  echo "# reference \`phoon\` (TZ=UTC). Regenerate with tools/gen-corpus.sh."
} > "$MAN"

emit() { # name size "datestring" clock
  local name="$1" size="$2" date="$3" clock="$4"
  local epoch
  epoch="$(/bin/date -u -j -f "%d %b %Y %H:%M:%S" "$date" +%s)"
  local out="$OUT/$name.txt"
  if [ -n "$FIX" ]; then
    TZ=UTC DYLD_INSERT_LIBRARIES="$FIX" DYLD_FORCE_FLAT_NAMESPACE=1 FAKE_NOW="$clock" \
      "$REF" -l "$size" "$date" > "$out"
  else
    TZ=UTC FAKE_NOW="$clock" "$REF" -l "$size" "$date" > "$out"
  fi
  printf '%s\t%s\t%s\t%s\n' "$name" "$size" "$epoch" "$clock" >> "$MAN"
  echo "  $name  size=$size  t=$epoch  clock=$clock  ($(wc -c < "$out") bytes)"
}

N=1000000000  # no easter eggs

# Eight principal phases across the Jan 2000 lunation, at the default size.
emit new-moon        23 "06 Jan 2000 12:00:00" "$N"
emit waxing-crescent 23 "10 Jan 2000 12:00:00" "$N"
emit first-quarter   23 "14 Jan 2000 12:00:00" "$N"
emit waxing-gibbous  23 "17 Jan 2000 12:00:00" "$N"
emit full-moon       23 "21 Jan 2000 12:00:00" "$N"
emit waning-gibbous  23 "24 Jan 2000 12:00:00" "$N"
emit last-quarter    23 "28 Jan 2000 12:00:00" "$N"
emit waning-crescent 23 "01 Feb 2000 12:00:00" "$N"

# Every canned art size plus representative plain sizes, at one instant.
for s in 16 17 18 19 20 21 22 23 24 27 28 29 30 32 40; do
  emit "size-$s" "$s" "15 Jan 2000 12:00:00" "$N"
done

# Easter eggs and specials.
emit greencheese  23 "15 Jan 2000 11:59:58" "$N"   # 947937598 % 17 == 3
emit pumpkin19    19 "01 Oct 2001 12:00:00" 33      # October, 33 % 32 == 1
emit hubert29     29 "13 Jan 2000 12:00:00" 3       # clock % 23 == 3
emit hubert-cheat 23 "20 Jan 2000 12:00:00" 3       # near full, clock % 13 == 3

# Other years / decades.
emit year-1999    23 "09 Nov 1999 03:00:00" "$N"
emit year-2026    23 "08 Aug 2026 12:00:00" "$N"
emit year-2030    18 "01 Jan 2030 00:00:00" "$N"
emit year-2035    32 "15 Jun 2035 18:30:00" "$N"

echo "manifest: $MAN"
