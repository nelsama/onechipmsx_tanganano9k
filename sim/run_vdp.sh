#!/usr/bin/env bash
# Build and run the VDP testbench with GHDL.
#
#   sim/run_vdp.sh <srcdir> <outdir> <screen> <lat> [cmdtest] [frames]
#
#   srcdir  directory holding the VDP sources (src/video + src/peripheral/ram.vhd),
#           e.g. "src" (working tree) or a golden snapshot made with
#           sim/make_golden.sh
#   outdir  build directory (one per srcdir), dumps go to <outdir>/dump/
#   screen  0 1 2 3 4 5 6 7 8 80   (see tb_vdp.vhd), or "build" to only compile
#   lat     VRAM read latency model in clk21m edges (0 = original SD-RAM timing)
#
# Environment: MEM=1 uses the PSRAM controller (src/memory/psram_msx.vhd with
# sim/psram_chan_model.vhd) instead of the latency model; RATIO (memclk /
# clk21m, default 4) and LC (latency code, default 3) configure it.
#
# Needs GHDL; on this machine: C:\msys64\ucrt64\bin (gcc must be on PATH too).
set -euo pipefail
export PATH=/c/msys64/ucrt64/bin:$PATH

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$1; OUT=$2; SCREEN=$3; LAT=$4; CMD=${5:-0}; FRAMES=${6:-3}
MEM=${MEM:-0}; RATIO=${RATIO:-4}; LC=${LC:-3}
case "$SRC" in /*) ;; *) SRC="$ROOT/$SRC" ;; esac
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
mkdir -p "$OUT/dump"
cd "$OUT"

GHDLFLAGS="--std=93c -fexplicit --ieee=synopsys -frelaxed"
STAMP="$OUT/.built"
MEMSRC="$ROOT/sim/psram_chan_model.vhd $ROOT/src/memory/psram_msx.vhd"
newest=$(find "$SRC/video" "$SRC/peripheral/ram.vhd" "$ROOT/sim/tb_vdp.vhd" $MEMSRC \
           -newer "$STAMP" 2>/dev/null | head -1 || true)
if [ ! -f "$STAMP" ] || [ -n "$newest" ]; then
  rm -f ./*.o ./*.cf tb_vdp tb_vdp.exe
  for f in $MEMSRC "$SRC/peripheral/ram.vhd" "$SRC/video/vdp_package.vhd" "$SRC/video/linebuf.vhd" \
           "$SRC/video/doublebuf.vhd" "$SRC/video/vga.vhd" "$SRC/video/spinforam.vhd" \
           "$SRC/video/sprite.vhd" "$SRC/video/text12.vhd" "$SRC/video/graphic123M.vhd" \
           "$SRC/video/graphic4567.vhd" "$SRC/video/vdp.vhd" "$ROOT/sim/tb_vdp.vhd"; do
    ghdl -a $GHDLFLAGS "$f" 2>&1 | grep -v -i "warning" || true
  done
  ghdl -e $GHDLFLAGS tb_vdp
  touch "$STAMP"
fi
[ "$SCREEN" = build ] && exit 0

if [ "$MEM" = 1 ]; then NAME="s${SCREEN}_p${RATIO}${LC}_c${CMD}"; else NAME="s${SCREEN}_l${LAT}_c${CMD}"; fi
ghdl -r $GHDLFLAGS tb_vdp -gSCREEN=$SCREEN -gLAT=$LAT -gCMDTEST=$CMD -gFRAMES=$FRAMES \
  -gUSE_PSRAM=$MEM -gRATIO=$RATIO -gLC=$LC \
  -gDUMPFILE="dump/$NAME.txt" --ieee-asserts=disable-at-0 2>&1 | grep -v -i "warning" || true
echo "$OUT/dump/$NAME.txt"
