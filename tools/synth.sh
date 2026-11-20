#!/usr/bin/env bash
# Synthesis-only run with GowinSynthesis, used to measure resource usage.
#
#   tools/synth.sh [name] [device]
#
#   name    output dir under build/ (default: syn)
#   device  9k  -> GW1NR-LV9QN88PC6/I5 (Tang Nano 9K, real target)
#           18k -> GW2AR-LV18QN88C8/I7 (only to get the per-module breakdown
#                  when the design does not fit the 9K: Gowin skips the
#                  hierarchical report on a resource-limit error)
#
# Per-module breakdown: build/<name>/impl/gwsynthesis/*_syn_rsc.xml
# Logic used = LUT + ALU + 6*SSRAM (that is how Gowin counts against 8640).
set -euo pipefail

GW_SH=${GW_SH:-/c/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-syn}
case "${2:-9k}" in
  9k)  DEV="GW1NR-LV9QN88PC6/I5" ;;
  18k) DEV="GW2AR-LV18QN88C8/I7" ;;
  *)   echo "unknown device '$2'" >&2; exit 2 ;;
esac
TOP=${TOP:-emsx_top}

OUT="$ROOT/build/$NAME"
rm -rf "$OUT"; mkdir -p "$OUT"
WIN_ROOT=$(cd "$ROOT" && pwd -W)

{
  echo "set_device $DEV -device_version C"
  echo "add_file -type vhdl $WIN_ROOT/xil_pll4x.vhd"
  (cd "$ROOT" && find src -name '*.vhd' ! -path 'src/peripheral/pll4x.vhd' | sort) |
    while read -r f; do echo "add_file -type vhdl $WIN_ROOT/$f"; done
  echo "set_option -top_module $TOP"
  echo "set_option -vhdl_std vhd1993"
  echo "set_option -output_base_name $TOP"
  echo "run syn"
} > "$OUT/syn.tcl"

cd "$OUT"
set +e
"$GW_SH" syn.tcl > syn.out 2>&1
rc=$?
set -e
grep -E '^ERROR' syn.out || true
echo "warnings: $(grep -c '^WARN' syn.out || true)   exit=$rc   log=$OUT/syn.out"
exit $rc
