# Original workshop-pilot ground and flora

This is a new, original reconstruction for the independent workshop pilot. It does not restore, recover, or claim to match any lost r17/r24 scene.

## Reference and contract
- Inspected the actual user-supplied `ChatGPT 圖片 2026年10月9日 下午09_48_25-4.png` pixels before implementation.
- The reference image is not a background, texture, or copied asset.
- Units are meters. Godot X = Blender X; Godot Y = Blender Z; Godot Z = -Blender Y.
- Main building footprint stays clear in X -8.25 to 4.5, Z -3.05 to 3.70.
- Actor staging point (0,0,5) retains 1.3 m clear radius.
- Landscape is a foreground and immediate background treatment only. No full-town map is implied.

## Integration
Use the runtime generator:
Use `preload("res://src/ground_flora.gd").apply(parent_node)`.

The headless-created `.scn` passed node-count reload but later failed meaningful MultiMesh transform verification: the dummy renderer returned zero transforms. That candidate is preserved under `art_source/ground_flora/validation/headless_structure_only_not_runtime.scn` and must not be used as a runtime asset. Native rendering-context serialization remains unverified.

The generator produces one Node3D with 18 renderer children. It does not change the main scene, camera, lighting/environment, house, props, or actor.

## Editable sources
- `src/ground_flora.gd`: original deterministic geometry, materials, seed, placement rules.
- `art_source/ground_flora/build_assets.gd`: rebakes the scene and individual shared mesh resources.
- Failed headless `.scn`: preserved as validation evidence, not a usable baked scene.
- Shared binary `.res` files: curved grass blade, folded broad leaf, shallow cup flower, seven angular rock variants.
- Fixed random seed: 20261009.

## Construction
- 31,145 broad, swept, creased grass leaves in irregular multi-leaf clumps, with short road-edge transition, soil gaps and sparse dry accents. Two grass MultiMesh nodes; no per-leaf nodes.
- 32,760 individually curved broadleaf canopy leaves, attached to fourteen overlapping crown clusters per tree, plus joined tapered trunks and branches. One canopy MultiMesh node.
- Additional roadside herb leaves, thin flower stems, and seven-petal ivory cups. Flower faces are tilted in variable directions; petals are genuinely curved surfaces, not textured cards or white stars.
- Seven non-spherical layered rock plate meshes and sparse half-buried path chips. Big irregular faces remain visible.
- Two short weathered fence runs composed into one mesh.
- Soft terrain heights and a wide bare sandy-earth approach for the actor and workshop, with a right-hand path fork.

## Materials and provenance
All geometry and currently included materials are authored for this pilot. There are no downloaded third-party dependencies in this ground/flora package. Reference-derived visual guidance does not imply ownership of the reference artwork.

The soil currently uses an original procedural earth/gravel shader. Real scanned PBR sourcing was attempted by the separate materials worker but no files were obtained. This is a provisional material, not a claimed scan or final realism result. Planned external texture filenames must not be referenced as if they exist.

## Validation
- Godot 4.6.3 headless parser, mesh generation, and full instantiation passed.
- Baked PackedScene reloaded with all 17 children, but that structural test was insufficient: headless dummy MultiMesh transforms read back as zero. The `.scn` candidate is quarantined; use the runtime source.
- First validation failed because the default user-data directory was not writable; the failed log is retained. Validation subsequently uses writable XDG directories inside this component's validation folder.
- Native camera-frame visual validation belongs to the integration lead. Headless construction does not establish scene image quality.

## Rebuild
From the project root, run Godot headlessly against the included validation project with XDG_DATA_HOME, XDG_CACHE_HOME, and XDG_CONFIG_HOME pointing to the corresponding writable validation subdirectories, then use `--script ../build_assets.gd`. The build script uses the explicitly assigned project absolute path.

## Building-placement integration revision
The building/props moved by Godot (3.2,0,-1.2). The active forbidden flora footprint is X -5.05..7.70, Z -4.25..2.50. The character clear radius and foreground road center are unchanged. The right-hand road corridor now runs X 10.1..12.3. To avoid re-sprinkling, the original random layout is still generated, then only conflicting vegetation is removed; all surviving transforms and tree/rock shapes remain unchanged. The old empty footprint has not been repopulated.

## Frontface correction after native r1
Native frame r1 exposed a serious terrain winding error: the upper ground was backface-culled. Godot SurfaceTool uses clockwise fronts; a measured [0,2,1] sample generated normal (0,-1,0). The terrain now uses [0,1,2] for (0,1,0). Grass, broadleaf, flowers, and rock top surfaces were corrected as well, with measured average upward normal Y of 0.44935, 0.95114, and 0.96367 for the leaf/flower prototypes. Vegetation albedos and backlighting were reduced after the same frame showed excessive fluorescence. Lighting, camera, placement, and foliage counts were not changed. Native r2 remains the integration lead's next check.

## Backdrop revision after actual r2 review
The actual r2 native frame was inspected: terrain rendering and foliage color improved, but the finite ground rectangle and single near-tree layer left large empty dark background gaps. The existing near grid and original foreground/trees are retained. Coarse continuous terrain rings now extend to X +/-65 and Z -90; this is a scenic back slope, not a developed map. A staggered distant crown layer and low understory use 84 irregular closed editable crown lobes, plus only 3,660 additional shared surface leaves (about 11% over the 32,760 original tree leaves). Four additional MultiMesh render nodes bring the renderer child count to 21. Terrain upward normals and outward crown normals are numerically checked. No camera, lighting, house, foreground herb placement, or rock changes were made. The pale geometric rock appearance remains explicitly deferred. Native r3 is pending the integration lead.

## Closed crown volumes rejected after native diagnostic frame
The actual `material-r2-no-compression/engine_frame.png` was inspected. The closed crown bodies read as visible potatoes/spheres, and the unbroken yellow rear slope was visibly worse. All closed crown instances and their live source methods were removed. The rejected source and `.res` resources remain under this component's source/validation history. The same 3,660 real curved leaves are now concentrated into six irregular distant crowns; total render nodes are 18. The background ground transitions from sandy earth to muted forest-soil green over Z -3..-15, and the extra distant undulation is reduced by roughly half to protect the sky. Foreground texture/geometry, original grass and tree leaves, lighting, camera, house, and rocks are unchanged. Next native review uses the lead's lower camera.
