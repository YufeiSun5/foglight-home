# Additional workshop wall props

`assets/workshop_props/workwall_props.glb` is an additive asset. It does not replace or modify the original workshop_props.glb. Use the same scene origin and parent translation as the workshop. Source is Blender metres/Z-up/front -Y; GLB performs normal Y-up conversion.

- Three-tier shelf occupies X -0.56 to +0.76, shelf Z 1.00/1.53/2.08 and front Y -0.77. Its top uprights reach Z 2.62. This stays between the front structural post and existing right window.
- Two slender left tools (joiner's mallet, blacksmith tongs) occupy X -1.65 to -0.86, Z about 1.75 to 2.62. The narrow rail and open tool shapes preserve most of the left plaster face.
- One tensioned frame saw hangs right of the existing window, X 2.79 to 3.23, Z 1.65 to 2.49.
- Shelf objects are one open carpenter's tote, two visibly different oil cans, one hand plane and one spare bearing ring. No repeated wall of tiny objects.

Files:

- `build_workwall_props.py`: generator, borrowing the original generator's basic helpers and material definitions.
- `workwall_props.blend`: editable component source before export evaluation.
- `workwall_props_export_verified.blend`: evaluated/export-equivalent meshes with original component collections hidden; contains the exact repaired UV topology used for delivery.
- `workwall_preview.png`: Blender asset-only placement/silhouette review; final Godot view belongs to the parent scene.
- `workwall_stats.json`, `workwall_validation.json`, `workwall_hashes.json`: geometry, UV/TBN checks and hashes.

UV/TBN findings addressed at source-generation time: ring sides and a few rounded cylinder bevels can inherit collapsed UV triangles. The generator evaluates modifiers, drops near-zero-area bevel triangles, and reconstructs only degenerate UV islands using each triangle's local geometric basis. Base colors, normal texture strengths and roughness are unchanged. Final exported UV areas are nonzero, all normal/tangent pairs satisfy abs(dot(N,T)) < 0.01 (observed maximum 0.0001344), and prior failed candidates are preserved under `candidates/`.
