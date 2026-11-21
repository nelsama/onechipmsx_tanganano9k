#!/usr/bin/env bash
# Run the working-tree VDP with VRAM latency LAT (default 4) on every screen
# mode (+ command / CPU tests) and compare with the golden dumps
# (made by sim/make_golden.sh + sim/run_vdp.sh ... 0).
#   sim/check_vdp.sh [lat] [screens...]
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
LAT=${1:-4}; shift || true
SCREENS=${*:-"0 80 1 2 3 4 5 6 7 8"}
OUT=${OUT:-build/sim/dut2}
bash sim/run_vdp.sh src $OUT build 0 || exit 1
# at most JOBS simulations at a time (launching many fresh .exe at once
# has hung them on Windows)
JOBS=${JOBS:-3}
{ for s in $SCREENS; do echo "$s 0"; done; echo "5 1"; echo "8 1"; } |
  xargs -P "$JOBS" -L 1 sh -c 'bash sim/run_vdp.sh src '"$OUT"' $0 '"$LAT"' $1 2 > '"$OUT"'/log_s$0_c$1.txt 2>&1'
fail=0
for s in $SCREENS; do
  g=build/sim/golden/dump/s${s}_l0_c0.txt; d=$OUT/dump/s${s}_l${LAT}_c0.txt
  if cmp -s "$g" "$d"; then echo "screen $s: OK"; else
    n=$(diff "$g" "$d" | grep -c '^<'); first=$(cmp "$g" "$d" | sed 's/.*line //'); echo "screen $s: DIFF $n lines (first at line $first)"; fail=1; fi
done
for s in 5 8; do
  g=build/sim/golden/dump/s${s}_l0_c1.txt; d=$OUT/dump/s${s}_l${LAT}_c1.txt
  cmp -s "$g" "$d" && v1=OK || { v1=DIFF; fail=1; }
  cmp -s "$g.vram" "$d.vram" && v2=OK || { v2=DIFF; fail=1; }
  echo "screen $s cmd test: video $v1, VRAM $v2, $(grep -h 'read-back' $OUT/log_s${s}_c1.txt)"
done
exit $fail
