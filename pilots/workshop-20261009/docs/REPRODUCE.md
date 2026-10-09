# Independent workshop feasibility pilot

This is newly authored source for the 2026-10-09 workshop pilot. It does not restore the earlier missing project or accepted grass r17. The supplied workshop image guides 3D observation only and is not embedded as a texture/background. Distant environment remains a simplified study.

## Tools and launch

Verified available authoring tools: Godot 4.6.3 and Blender 4.3.2. No extra software or external generation service has been installed or called.

1. Restore the project to `/workspace/shared/foglight-town-pilot-20261009` (current generators use this explicit cloud path).
2. Run Godot editor import: `godot --headless --audio-driver Dummy --editor --path . --import`.
3. On a real desktop run `./run-pilot.sh material-r1`. The scene is `src/pilot.tscn`; window title Foglight Workshop Pilot.
4. The native running scene captures its viewport and runtime material/AA contract under `.qa/<label>/`. Headless dummy rendering is not a visual pass.

The project intentionally excludes authoring files from Godot scanning with `art_source/.gdignore`. Render assets are GLB, not direct .blend imports.

## Rebuild authoring assets

Within the project path, run `python art_source/workshop/make_textures.py`, then `blender -b -t 4 --python art_source/workshop/build_workshop.py`, then `blender -b -t 4 --python art_source/workshop/export_runtime.py`. For props, run the corresponding `generate_textures.py` and `build_workshop_props.py`. Use the `.qa/blender.lock` flock when multiple workers are present. The ground and flora are rebuilt at runtime by `src/ground_flora.gd` and do not rely on the headless-serialized MultiMesh scene.

## Source and licensing

All workshop, props, ground and plant geometry and procedural textures are original editable work authored for this pilot. The original character idle atlas is copied from the user's authorized foglight-home repository at a pinned commit. Its provenance and original source license/notes are in `assets/character/`. It is only a scale reference in this scene, not the reference image's character.

`art_source/materials/manifest.json` lists CC0 PBR candidates. Their downloads failed; they are not used. No claim is made that scan textures were imported.

## Current validation boundary (r3)

The complete r3 native frame has been viewed; terrain winding and black sampling artifacts are corrected. The workshop/frontage remains a simplified feasibility result rather than high-quality reference fidelity. No gameplay, world-map performance, or user-hardware performance is certified.

## Current complete build

Use `./rebuild-assets.sh` for the current refined3 + props + tool-wall pipeline. It uses only the installed Blender/Python libraries and serializes Blender with flock. Current generators have already run successfully individually; a clean extraction full rebuild has not been rerun at this checkpoint. The companion Runtime-M2 archive contains the exact three GLBs used by r3, so importing/running does not require rebuilding Blender assets. Extract source and runtime archives over the same project root. No installer or exported game executable is included.

The source archive includes the original 2D comparison input, Tripo preparation specification and skill docs as separate authoring references. These are not in the running scene.

For a sandboxed headless dependency check, set XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME to writable directories inside the authorized workspace. A first attempt without a writable application-data directory crashed before scene load; the bounded retry passed. See CHECKPOINT_VALIDATION.json.

The frozen optional multi-view control study lives in art_source/tripo_workshop/. Its five 1000px orthographic renders share one source model, and its Blender source is included because it is small. It is separate from the running hand-modeled r3 pilot and from any future Tripo result.
