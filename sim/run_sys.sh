#!/usr/bin/env bash
# Whole-system boot simulation (sim/tb_sys.vhd) with GHDL.
#   sim/run_sys.sh [image] [ms]           e.g. sim/run_sys.sh build/bios/OCM-BIOS.DAT 30
#   FASTBOOT=1 sim/run_sys.sh ...         skip the 256 KB flash copy of the IPL:
#       the image is preloaded in the PSRAM model and a copy of the IPL-ROM
#       with "CALL F0A0h" (the copy loop, at F08Ah) replaced by NOPs is used
set -euo pipefail
export PATH=/c/msys64/ucrt64/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG=$(cd "$(dirname "${1:-$ROOT/build/bios/OCM-BIOS.DAT}")" && pwd)/$(basename "${1:-OCM-BIOS.DAT}")
SIMTIME=${2:-20}
FASTBOOT=${FASTBOOT:-0}
OUT="$ROOT/build/sim/sys$FASTBOOT"; mkdir -p "$OUT"; cd "$OUT"
F="--std=93c -fexplicit --ieee=synopsys -frelaxed"
EXCL="! -name psram_chan.vhd"
EXTRA=""
if [ "$FASTBOOT" = 1 ]; then
  python - "$ROOT/src/peripheral/iplrom.vhd" iplrom_fastboot.vhd <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
it = list(re.finditer(r'X"([0-9A-Fa-f]{2})"', s))
assert [it[i].group(1).upper() for i in (0x8A, 0x8B, 0x8C)] == ['CD', 'A0', 'F0']
for i in (0x8C, 0x8B, 0x8A):
    m = it[i]; s = s[:m.start()] + 'X"00"' + s[m.end():]
open(sys.argv[2], 'w', encoding='utf-8').write(s)
PY
  EXCL="$EXCL ! -name iplrom.vhd"
  EXTRA="$OUT/iplrom_fastboot.vhd"
fi
FILES=$(cd "$ROOT" && find src -name '*.vhd' ! -path 'src/board/*' ! -path 'src/test/*' $EXCL | sed "s#^#$ROOT/#")
rm -f work-obj93.cf
ghdl -i $F $FILES $EXTRA "$ROOT/sim/psram_chan_model.vhd" "$ROOT/sim/tb_sys.vhd"
ghdl -m $F tb_sys 2>&1 | grep -v -i "warning" | grep -v "^analyze\|^elaborate\|^ *\^\|F : std\|extra_mode" || true
ghdl -r $F tb_sys -gIMAGE="$IMG" -gSIMTIME_MS=$SIMTIME -gFASTBOOT=$FASTBOOT -gPCTIME=${PCTIME:-0} -gCLEARTEST=${CLEARTEST:-0} --ieee-asserts=disable 2>&1 | grep -v -i warning
