#!/usr/bin/env bash
# Plays a VDP VGA dump (from sim/run_vdp.sh) into src/board/vdp2hdmi.vhd and
# checks the 720x480p output pixel by pixel against the expected 5/4 scaling.
#   sim/run_vdp2hdmi.sh [vdp dump] (default: golden screen 5)
set -euo pipefail
export PATH=/c/msys64/ucrt64/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IN=$(cd "$(dirname "${1:-$ROOT/build/sim/golden/dump/s5_l0_c0.txt}")" && pwd)/$(basename "${1:-s5_l0_c0.txt}")
OUT="$ROOT/build/sim/hdmi"; mkdir -p "$OUT"; cd "$OUT"
F="--std=93c -fexplicit --ieee=synopsys -frelaxed"
ghdl -a $F "$ROOT/src/board/vdp2hdmi.vhd" "$ROOT/sim/tb_vdp2hdmi.vhd"
ghdl -e $F tb_vdp2hdmi
ghdl -r $F tb_vdp2hdmi -gINFILE="$IN" -gOUTFILE=hdmi.txt -gFRAMES=4 2>&1 | grep -v -i warning || true
python - "$IN" hdmi.txt <<'PY'
import sys, itertools
V=open(sys.argv[1]).read().split('\n')[:-1]
lines=[];cur=None;hd='1'
for t in V:
    rgb,s=t.split()
    if hd=='1' and s[0]=='0':
        if cur is not None: lines.append(cur)
        cur=[]
    cur.append(rgb); hd=s[0]
lines.append(cur)
x8=lambda h:((int(h,16)&63)<<2)|((int(h,16)&63)>>4)
H=open(sys.argv[2]).read().split('\n')[:-1]
act=[t.split()[0] for t in H if t.split()[1][2]=='1']
bad=0
for y in range(480):
    for x in range(720):
        if 9<=x<712:
            c=lines[y+39][121+(x-9)*4//5]; e='%02X%02X%02X'%(x8(c[0:2]),x8(c[2:4]),x8(c[4:6]))
        else: e='000000'
        bad+=act[y*720+x]!=e
hs=[len(list(g)) for k,g in itertools.groupby(t.split()[1][0] for t in H) if k=='0']
print('HDMI frame: %d clocks (855x524=%d), active %d, pixel mismatches %d, hsync widths %s'
      %(len(H),855*524,len(act),bad,sorted(set(hs))))
sys.exit(1 if bad or len(H)!=855*524 else 0)
PY
