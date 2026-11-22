#!/usr/bin/env bash
# Synthesis-only run with GowinSynthesis, used to measure resource usage.
#
#   [TOP=entity] [GENERICS="NAME=value ..."] tools/synth.sh [name] [device]
#
#   name      output dir under build/ (default: syn)
#   device    9k  -> GW1NR-LV9QN88PC6/I5 (Tang Nano 9K, real target)
#             18k -> GW2AR-LV18QN88C8/I7 (only to get the per-module breakdown
#                    when the design does not fit the 9K: Gowin skips the
#                    hierarchical report on a resource-limit error)
#   GENERICS  overrides of emsx_core generic defaults, e.g.
#             GENERICS="ENABLE_OPLL=false ENABLE_RTC=false"
#             (applied to a copy of src/emsx_core.vhd inside build/<name>)
#
#   PNR=1     also place & route (+ bitstream) with src/board/tn9k.cst/.sdc,
#             e.g. TOP=tn9k_top PNR=1 tools/synth.sh tn9k 9k
#             bitstream: build/<name>/impl/pnr/<top>.fs
#
# Prints: Logic used/8640 (= LUT + ALU + 6*SSRAM), registers, BSRAM.
# Per-module breakdown: build/<name>/impl/gwsynthesis/*_syn_rsc.xml
set -euo pipefail

GW_SH=${GW_SH:-/c/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-syn}
case "${2:-9k}" in
  9k)  DEV="GW1NR-LV9QN88PC6/I5" ;;
  18k) DEV="GW2AR-LV18QN88C8/I7" ;;
  *)   echo "unknown device '$2'" >&2; exit 2 ;;
esac
TOP=${TOP:-emsx_core}
TOPGENERICS=${TOPGENERICS:-}
PNR=${PNR:-0}
GENERICS=${GENERICS:-}

OUT="$ROOT/build/$NAME"
rm -rf "$OUT"; mkdir -p "$OUT"
WIN_ROOT=$(cd "$ROOT" && pwd -W)
WIN_OUT=$(cd "$OUT" && pwd -W)

CORE="$WIN_ROOT/src/emsx_core.vhd"
if [ -n "$GENERICS" ]; then
  cp "$ROOT/src/emsx_core.vhd" "$OUT/emsx_core.vhd"
  for kv in $GENERICS; do
    k=${kv%%=*}; v=${kv#*=}
    # replace the default value in the generic declaration:  NAME : type := value;
    sed -i -E "s/^(\s*$k\s*:\s*[^:]+:=\s*)[^;)-]+/\1$v /" "$OUT/emsx_core.vhd"
    grep -qE "^\s*$k\s*:.*:=\s*$v\b" "$OUT/emsx_core.vhd" || { echo "generic $k not set" >&2; exit 2; }
  done
  CORE="$WIN_OUT/emsx_core.vhd"
fi

# TOPGENERICS: same, on a copy of src/board/tn9k_top.vhd (e.g. DBG_TRACE=true)
BTOP="$WIN_ROOT/src/board/tn9k_top.vhd"
if [ -n "$TOPGENERICS" ]; then
  cp "$ROOT/src/board/tn9k_top.vhd" "$OUT/tn9k_top.vhd"
  for kv in $TOPGENERICS; do
    k=${kv%%=*}; v=${kv#*=}
    sed -i -E "s/^(\s*$k\s*:\s*[^:]+:=\s*)[^;)-]+/\1$v /" "$OUT/tn9k_top.vhd"
    grep -qE "^\s*$k\s*:.*:=\s*$v\b" "$OUT/tn9k_top.vhd" || { echo "generic $k not set" >&2; exit 2; }
  done
  BTOP="$WIN_OUT/tn9k_top.vhd"
fi

{
  echo "set_device $DEV -device_version C"
  (cd "$ROOT" && find src -name '*.vhd' ! -name emsx_core.vhd ! -name tn9k_top.vhd | sort) |
    while read -r f; do echo "add_file -type vhdl $WIN_ROOT/$f"; done
  echo "add_file -type vhdl $CORE"
  echo "add_file -type vhdl $BTOP"
  echo "set_option -top_module $TOP"
  echo "set_option -vhdl_std vhd1993"
  echo "set_option -output_base_name $TOP"
  if [ "$PNR" = 1 ]; then
    echo "add_file -type cst $WIN_ROOT/${CST:-src/board/tn9k.cst}"
    echo "add_file -type sdc $WIN_ROOT/${SDC:-src/board/tn9k.sdc}"
    echo "set_option -use_mspi_as_gpio 1"
    echo "set_option -timing_driven 1"
    echo "set_option -place_option ${PLACE_OPT:-0}"
    echo "set_option -route_option ${ROUTE_OPT:-0}"
    echo "run all"
  else
    echo "run syn"
  fi
} > "$OUT/syn.tcl"

cd "$OUT"
set +e
"$GW_SH" syn.tcl > syn.out 2>&1
rc=$?
set -e
grep -E '^ERROR' syn.out || true
RPT="impl/gwsynthesis/${TOP}_syn.rpt.html"
if [ -f "$RPT" ]; then
  sed -e 's/<[^>]*>/\n/g' "$RPT" | sed 's/&nbsp//g' | grep -v '^\s*$' |
    grep -A1 -E '^\s*(Logic|Register|BSRAM)\s*$' | grep '/' | tr -s ' ' |
    paste -sd' ' | sed 's/^/resources: /'
fi
echo "warnings: $(grep -c '^WARN' syn.out || true)   exit=$rc   log=$OUT/syn.out"
if [ "$PNR" = 1 ]; then
  PR="impl/pnr/${TOP}.rpt.txt"
  [ -f "$PR" ] && grep -E '^\s*(Logic|Register|BSRAM|PLL|CLKDIV)' "$PR" | head -8 | sed 's/^/pnr: /'
  TR="impl/pnr/${TOP}_tr_content.html"
  [ -f "$TR" ] && echo "timing report: $OUT/$TR"
  ls impl/pnr/*.fs 2>/dev/null | sed 's/^/bitstream: /'
fi
exit $rc
