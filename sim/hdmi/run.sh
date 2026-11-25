#!/usr/bin/env bash
# HDMI stream check: vdp2hdmi + hdmi_tx (GHDL) decoded by an independent
# receiver (receptor.js, Node). About 2 frames.
set -euo pipefail
export PATH=$PATH:/c/msys64/ucrt64/bin
cd "$(dirname "$0")"; ROOT=$(cd ../.. && pwd -W 2>/dev/null || pwd)
mkdir -p "$ROOT/build/sim/hdmi_tx"; cd "$ROOT/build/sim/hdmi_tx"
F="--std=08 -frelaxed"
for s in src/board/vdp2hdmi src/board/hdmi/tmds_encoder_2 src/board/hdmi/hdmi_tx sim/hdmi/tb_hdmi; do
  ghdl -a $F "$ROOT/$s.vhd"
done
ghdl -e $F tb
ghdl -r $F tb --ieee-asserts=disable
node "$ROOT/sim/hdmi/receptor.js"
