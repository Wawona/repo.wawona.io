#!/usr/bin/env bash
# Compare phoon-rs stdout against a reference `phoon` binary, byte-for-byte.
#
#   PHOON_REF=/path/to/phoon PHOON_FIXTIME=/path/to/fixtime.dylib \
#     tools/compat-check.sh
#
# The reference is run with TZ=UTC and a fixed time() (FAKE_NOW) via the
# interpose dylib; phoon-rs is run with the matching PHOON_NOW so both programs
# see the same wall clock for the easter-egg selection.
set -u

REF="${PHOON_REF:?set PHOON_REF}"
FIX="${PHOON_FIXTIME:-}"
MINE="${MYPHOON:-target/debug/phoon}"

run_ref() { # size date fake_now
  local size="$1" date="$2" now="$3"
  if [ -n "$FIX" ]; then
    TZ=UTC DYLD_INSERT_LIBRARIES="$FIX" DYLD_FORCE_FLAT_NAMESPACE=1 FAKE_NOW="$now" "$REF" ${size:+-l "$size"} ${date:+"$date"}
  else
    TZ=UTC FAKE_NOW="$now" "$REF" ${size:+-l "$size"} ${date:+"$date"}
  fi
}
run_mine() { # size date phoon_now
  local size="$1" date="$2" now="$3"
  TZ=UTC PHOON_NOW="$now" "$MINE" ${size:+-l "$size"} ${date:+"$date"}
}

SIZES=(16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 32 40 50 "")
PASS=0; FAIL=0; FIRST_SHOWN=0
NOW=1000000000

check() { # size date now label
  local size="$1" date="$2" now="$3" label="$4"
  local a b
  a="$(run_ref "$size" "$date" "$now" | od -An -tx1)"
  b="$(run_mine "$size" "$date" "$now" | od -An -tx1)"
  if [ "$a" = "$b" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    if [ "$FIRST_SHOWN" -lt 6 ]; then
      FIRST_SHOWN=$((FIRST_SHOWN+1))
      echo "MISMATCH [$label] size='$size' date='$date' now=$now"
      diff <(run_ref "$size" "$date" "$now") <(run_mine "$size" "$date" "$now") | head -20
      echo "----"
    fi
  fi
}

# Broad phase/size sweep across ~11 years.
start=946684800   # 2000-01-01 UTC
step=690000       # ~8 days -> sweeps phase space
count="${COUNT:-120}"
for i in $(seq 0 $((count-1))); do
  e=$((start + i*step))
  d="$(/bin/date -u -r "$e" +"%-d %b %Y %H:%M:%S")"
  for s in "${SIZES[@]}"; do
    check "$s" "$d" "$NOW" "sweep"
  done
done

# GREENCHEESE: pick timestamps with t % 17 == 3.
gc=0
for i in $(seq 0 5000); do
  e=$((start + i*97))
  if [ $((e % 17)) -eq 3 ]; then
    d="$(/bin/date -u -r "$e" +"%-d %b %Y %H:%M:%S")"
    check 23 "$d" "$NOW" "greencheese"
    check 18 "$d" "$NOW" "greencheese"
    gc=$((gc+1)); [ "$gc" -ge 6 ] && break
  fi
done

# hubert29: FAKE_NOW % 23 == 3.
check 29 "13 Jan 2000 12:00:00" 3 "hubert29"
check 29 "6 Jan 2000 00:00:00" 3 "hubert29"
# hubert cheat: near-full date, any size, FAKE_NOW % 13 == 3.
check 23 "21 Jan 2000 04:40:00" 3 "hubert-cheat"
check 18 "20 Jan 2000 12:00:00" 3 "hubert-cheat"

# pumpkin19: October, clocknow % (33 - mday) == 1. Oct 1 -> 33-1=32 -> now%32==1.
check 19 "1 Oct 2001 12:00:00" 33 "pumpkin"     # 33 % 32 == 1
check 19 "5 Oct 2001 06:00:00" 29 "pumpkin"     # 33-5=28; 29 % 28 == 1

# no-date (uses PHOON_NOW / FAKE_NOW as the instant): compare default + sizes.
check ""  "" "$NOW" "no-date-default"
check 23  "" "$NOW" "no-date"
check 18  "" 946702800 "no-date-18"

# --- error-path parity: stderr + exit code (stdout is empty for both) ---
err_check() { # label args...
  local label="$1"; shift
  local ra rb ea eb
  ra="$(TZ=UTC "$REF" "$@" 2>&1 >/dev/null)"; ea=$?
  rb="$(TZ=UTC "$MINE" "$@" 2>&1 >/dev/null)"; eb=$?
  # Normalize argv[0] in usage text so only the message shape is compared.
  ra="${ra//$REF/PROG}"; rb="${rb//$MINE/PROG}"
  if [ "$ra" = "$rb" ] && [ "$ea" = "$eb" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "ERR-MISMATCH [$label]: exit ref=$ea mine=$eb"
    echo "  ref : $ra"
    echo "  mine: $rb"
  fi
}
err_check "illegal-date"  "not a date"
err_check "illegal-iso"   "2000-01-06"
err_check "illegal-slash" "01/06/2000"
err_check "bad-flag"      "-x"
err_check "l-no-num"      "-l"
err_check "l-nan"         "-l" "abc"
err_check "too-many-args" "1" "2" "3" "4"

echo "======================================"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
