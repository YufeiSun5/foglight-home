# Workshop prop source

Original geometry and procedural image textures created specifically for the independent workshop pilot. The supplied workshop image was used as a composition/shape reference only. No source pixels, extracted game meshes, downloaded asset pack, external fonts, or remote service dependency are included.

## Deliverables

- `workshop_props.blend`: editable named component collections, metre scale, packed image textures.
- `build_workshop_props.py`: full reproducible Blender 4.3.2 geometry/export/preview script.
- `generate_textures.py`: reproducible NumPy/Pillow timber and metal PBR texture generator.
- `textures/`: two shared surface families (wood and metal), six deliberate color variants/materials.
- `../../assets/workshop_props/workshop_props.glb`: ten independently positionable merged assemblies, standard glTF metallic/roughness, normals, tangents and embedded textures.
- `props_overview.png`, `flywheel_detail.png`: asset-only Blender previews; not final Godot scene verification.
- `asset_stats.json`: geometry statistics and final GLB hash.
- `candidates/`: preserved initial export with tangent warning/failed denoising-preview log and second candidate with cart-handle overlap.

## Coordinates and integration

Blender units are metres, Z is up and the facade faces -Y. The asset should initially be instantiated at the project world origin with unit scale. Standard glTF export maps Blender (X,Y,Z) to engine (X,Z,-Y). No camera or lights are exported.

- Flywheel center: (-5.55, -1.25, 1.38), radius 1.19, highest Z 2.578. Primary open 8-spoke wheel, separate 36-tooth gear, meshing pinion, shaft, two pillow bearings, crank and connecting rod.
- Two-wheel handcart center: approximately (-4.55, -4.58, 0.75); shafts point toward +X. Visible wood spokes and fitted thin iron tyres.
- Workbench center: (1.95, -3.26, 1.04), top 2.2 × 0.8 m. Includes a lead-screw vise, joiner's hammer, plane, two chisels, tongs and one working board.
- Stool: (2.12, -4.04), seat Z 0.56.
- Olive chest: (-3.25, -3.52), 0.92 × 0.68 × 0.78 m.
- Door barrel: (-1.78, -3.07), 0.86 m tall.
- Outer supply crate: (4.20, -3.09), 0.85 × 0.73 × 0.76 m.
- Tall side crate: (4.73, -2.25), 0.67 × 0.63 × 0.97 m.
- Side barrel: (4.28, -1.62), 0.83 m tall.
- Small work keg: (-2.76, -2.98), 0.57 m tall.

Centre-front X near 0 and Y near -5 is intentionally clear for the original project character. Door/barrel and roof clearances still require parent scene visual verification.

## Materials

Wood boards use metric face UVs with longitudinal grain at 1.5 m U repeat and transverse 0.35 m V repeat. Barrel stave UVs follow the vertical stave length. Broad ring/cylinder metal surfaces use readable UVs without baked lighting. Roughness and tangent-space normal images are Non-Color; base color is sRGB. Geometry supplies seams, bevels, spokes, hoop thickness and open space, with no baked AO or black crack maps. Export copies are triangulated after bevel and weighted-normal evaluation to keep tangent-space consistent. Editable source geometry retains modifiers.

## Rebuild

Run `python art_source/workshop_props/generate_textures.py`, then run Blender using the project’s shared mutex and four threads:

`flock /workspace/shared/foglight-town-pilot-20261009/.qa/blender.lock blender -b -t 4 --python /workspace/shared/foglight-town-pilot-20261009/art_source/workshop_props/build_workshop_props.py`

No installation or external network is required. The preview deliberately avoids unavailable OpenImageDenoise support in this installed Blender build.
