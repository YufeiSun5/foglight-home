# Repair malformed exported tangent frames without changing geometry or materials.
# Curves and projected annuli can have degenerate UVs; their fallback glTF tangents
# must still be perpendicular to NORMAL. The source GLBs remain untouched.
extends RefCounted

static func apply(root: Node) -> Dictionary:
 var report: Dictionary = {
  "meshes": 0, "surfaces": 0, "vertices": 0, "repaired": 0,
  "fallbacks": 0, "invalid_normals": 0, "invalid_tangents": 0,
  "missing_tangent_surfaces": 0,
  "before": {"min_length": INF, "max_abs_dot": 0.0},
  "after": {"min_length": INF, "max_abs_dot": 0.0}
 }
 _visit(root, report)
 for key in ["before", "after"]:
  if report[key].min_length == INF:
   report[key].min_length = 0.0
 print("MESH_BASIS_REPAIR ", JSON.stringify(report))
 return report

static func _visit(node: Node, report: Dictionary) -> void:
 if node is MeshInstance3D and node.mesh is ArrayMesh:
  var old: ArrayMesh = node.mesh
  var repaired := ArrayMesh.new()
  repaired.resource_name = old.resource_name
  repaired.custom_aabb = old.custom_aabb
  repaired.blend_shape_mode = old.blend_shape_mode
  repaired.shadow_mesh = old.shadow_mesh
  for b in range(old.get_blend_shape_count()):
   repaired.add_blend_shape(old.get_blend_shape_name(b))
  for surface in range(old.get_surface_count()):
   var arrays: Array = old.surface_get_arrays(surface)
   var format := old.surface_get_format(surface)
   for attribute in range(Mesh.ARRAY_MAX):
    if (format & (1 << attribute)) == 0:
     arrays[attribute] = null
   var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
   var tangent_data = arrays[Mesh.ARRAY_TANGENT]
   if tangent_data != null and tangent_data.size() == normals.size() * 4:
    var tangents: PackedFloat32Array = tangent_data
    for index in range(normals.size()):
     report.vertices += 1
     var normal := normals[index]
     if not normal.is_finite() or normal.length_squared() < 0.00000001:
      report.invalid_normals += 1
      continue
     normal = normal.normalized()
     var offset := index * 4
     var original := Vector3(tangents[offset], tangents[offset + 1], tangents[offset + 2])
     var old_length := original.length()
     var old_dot := absf(normal.dot(original))
     if original.is_finite():
      report.before.min_length = minf(report.before.min_length, old_length)
      report.before.max_abs_dot = maxf(report.before.max_abs_dot, old_dot)
     else:
      report.invalid_tangents += 1
     var tangent := original - normal * normal.dot(original)
     if not tangent.is_finite() or tangent.length_squared() < 0.000001:
      # Pick the least-aligned coordinate axis for a numerically stable fallback.
      var axis := Vector3.RIGHT
      if absf(normal.y) <= absf(normal.x) and absf(normal.y) <= absf(normal.z):
       axis = Vector3.UP
      elif absf(normal.z) <= absf(normal.x) and absf(normal.z) <= absf(normal.y):
       axis = Vector3.BACK
      tangent = axis - normal * normal.dot(axis)
      report.fallbacks += 1
     tangent = tangent.normalized()
     # A second pass removes cancellation error near a parallel source tangent.
     tangent = (tangent - normal * normal.dot(tangent)).normalized()
     if not original.is_finite() or old_dot > 0.001 or absf(old_length - 1.0) > 0.001:
      report.repaired += 1
     tangents[offset] = tangent.x
     tangents[offset + 1] = tangent.y
     tangents[offset + 2] = tangent.z
     # Exported handedness is already +/-1; retain its sign, including fallbacks.
     tangents[offset + 3] = -1.0 if tangents[offset + 3] < 0.0 else 1.0
     report.after.min_length = minf(report.after.min_length, tangent.length())
     report.after.max_abs_dot = maxf(report.after.max_abs_dot, absf(normal.dot(tangent)))
    arrays[Mesh.ARRAY_TANGENT] = tangents
   else:
    report.missing_tangent_surfaces += 1
   # Keep every existing vertex, index, UV, color, bone and custom attribute array.
   # These static imported assets do not use blend shapes, but preserve any present.
   repaired.add_surface_from_arrays(old.surface_get_primitive_type(surface), arrays, old.surface_get_blend_shape_arrays(surface), _lods(old, surface), format & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
   repaired.surface_set_material(surface, old.surface_get_material(surface))
   repaired.surface_set_name(surface, old.surface_get_name(surface))
   report.surfaces += 1
  node.mesh = repaired
  report.meshes += 1
 for child in node.get_children():
  _visit(child, report)

static func _lods(mesh: ArrayMesh, surface: int) -> Dictionary:
 var data := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
 var result := {}
 var stride := RenderingServer.mesh_surface_get_format_index_stride(data.format, data.vertex_count)
 for lod in data.get("lods", []):
  var bytes: PackedByteArray = lod.index_data
  var indices := PackedInt32Array()
  indices.resize(bytes.size() / stride)
  for i in range(indices.size()):
   indices[i] = bytes.decode_u16(i * stride) if stride == 2 else bytes.decode_u32(i * stride)
  result[lod.edge_length] = indices
 return result
