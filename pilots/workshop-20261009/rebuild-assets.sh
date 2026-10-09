#!/bin/bash
set -euo pipefail
cd /workspace/shared/foglight-town-pilot-20261009
mkdir -p .qa assets/workshop assets/workshop_props
exec 9>.qa/blender.lock
flock 9
export OMP_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4
python art_source/workshop/make_textures.py
python art_source/workshop/refine_roof_textures.py
blender -b -t 4 --python art_source/workshop/build_workshop_refined.py
blender -b -t 4 --python art_source/workshop/refine_roof_normals.py
blender -b -t 4 --python art_source/workshop/refine_workbay_plaster.py
blender -b -t 4 --python art_source/workshop/export_refined3_runtime.py
python art_source/workshop_props/generate_textures.py
blender -b -t 4 --python art_source/workshop_props/build_workshop_props.py
blender -b -t 4 --python art_source/workshop_props/build_workwall_props.py
