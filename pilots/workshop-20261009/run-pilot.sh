#!/bin/bash
set -euo pipefail
cd /workspace/shared/foglight-town-pilot-20261009
export OMP_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4
exec /usr/local/bin/godot --path . --rendering-method gl_compatibility --audio-driver Dummy --resolution 1672x941 -- --out="res://.qa/${1:-material-r1}" "${@:2}"
