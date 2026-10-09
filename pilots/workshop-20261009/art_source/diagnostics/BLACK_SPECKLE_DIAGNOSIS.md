# Workshop black-speckle diagnosis

Verified 2026-10-09, using actual native Godot frames captured by the scene lead.

## Result and minimum fix

The speckles are triggered by the anisotropic sampling path in this tested cloud rendering combination. Changing building/prop StandardMaterial3D.texture_filter from TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC to TEXTURE_FILTER_LINEAR_WITH_MIPMAPS removes the visible black speckles while retaining the original Standard materials, albedo/roughness/normal maps and PBR parameters. No shader replacement or exposure remapping is required.

The supported conclusion is limited to Godot 4.6.3, GL Compatibility, Mesa 25.0.7-2+deb13u1, llvmpipe (LLVM 19.1.7, 256 bits), and these imported meshes. This does not establish a bug on other GPUs, backends or driver versions. Singular UV derivatives are the likely trigger; the precise driver-internal failure was not investigated.

## Evidence

- Failure with original material sampling: `.qa/material-r2-tbn/engine_frame.png`. TBN has already been corrected, yet speckles remain on roof seams, flywheel/cart rims, barrel hoops and cloth edging.
- Successful sampler-only change from that diagnostic state: `.qa/material-r2-no-aniso/engine_frame.png`. Original Standard materials and actual textures remain; the affected curved surfaces are visually clean.
- Plain unshaded Standard material still failed: `.qa/material-r2-flat/engine_frame.png`. The test still inherited the anisotropic filter assignment in `_visit`.
- A constant-color ShaderMaterial with no texture sample was clean: `.qa/material-r2-shader-flat/engine_frame.png`.
- Disabling sun shadows, mesh LOD, import compression or MSAA did not remove the defect. Clearing shadow_mesh and disabling culling did not remove it either; their frames are retained under `.qa/`.
- The installed Godot binary's Standard shader generation strings include an albedo texture sample multiplied by the albedo uniform, explaining why a plain Standard material still exercises a sampler path. See `standard_shader_binary_excerpt.txt`.

Native-frame hashes and fixed-region exact-black counts are recorded in `black_speckle_evidence.json`. Counts are supporting pixel measurements, not a substitute for inspecting the full native frames.

## Source defects that remain

The source UV contract needs repair even though ordinary mipmapped filtering avoids the visible failure:

- Roof-seam surface: 46,208 of 47,180 triangles have zero-area UV0 mappings. Exported curves lose useful UVs when combined with the architectural UV layer.
- The prop ring function projects every face into XZ. Its cylindrical side faces therefore collapse in UV space. Rings/hoops need an angle-versus-depth unwrap; their flat end faces may retain planar UVs.
- Generated curve tubes, including cloth hems, need nondegenerate length-versus-circumference UVs before export. Mesh joins should use one deliberately populated material UV layer.
- Invalid fallback tangents are a separate real defect. `src/mesh_basis_repair.gd` repairs 68,298 of 307,121 imported vertex tangent frames; max absolute normal/tangent dot product changes from 1.0 to 8.94e-8. This repair alone did not eliminate the speckles.

The tangent helper leaves source GLBs untouched. Headless verification confirms preserved positions, indices, UVs, other present vertex attributes, material references, generated LODs and shadow meshes. Shadow meshes have the exact same position triangles as their color meshes.

No degenerate or duplicate triangles were found in the workshop runtime mesh or affected ring/hoop surfaces. A separate workbench-iron surface contains 64 zero-area triangles; it is not the cause of the diagnosed speckled regions and remains a source cleanup item.

## Follow-up boundary

Use ordinary linear mipmapped sampling for this cloud pilot. Repair the source UVs and regenerate valid tangents before reconsidering anisotropic filtering. Retest native frames after any future exporter, backend or driver change; do not assume this renderer workaround is universally required.
