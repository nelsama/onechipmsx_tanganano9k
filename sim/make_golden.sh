#!/usr/bin/env bash
# Snapshot the VDP sources of a git revision (default: tag/commit "vdp-golden")
# into build/sim/golden_src, to produce reference dumps:
#   sim/make_golden.sh [rev]
#   sim/run_vdp.sh build/sim/golden_src build/sim/golden <screen> 0
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REV=${1:-vdp-golden}
rm -rf "$ROOT/build/sim/golden_src"; mkdir -p "$ROOT/build/sim/golden_src"
git -C "$ROOT" archive "$REV" src | tar -x -C "$ROOT/build/sim/golden_src" --strip-components=1
echo "golden sources from $(git -C "$ROOT" rev-parse --short "$REV")"
