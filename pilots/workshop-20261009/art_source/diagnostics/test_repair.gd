extends SceneTree
const Repair = preload("res://src/mesh_basis_repair.gd")
func _init():
 var root=Node3D.new()
 for path in ["res://assets/workshop/foglight_workshop_runtime.glb","res://assets/workshop_props/workshop_props.glb"]:
  root.add_child(load(path).instantiate())
 var originals={}
 for scene in root.get_children():
  for mesh_node in scene.get_children():
   if mesh_node is MeshInstance3D:
    originals[mesh_node]=mesh_node.mesh
 var report=Repair.apply(root)
 for node in originals:
  var old=originals[node]
  var new_mesh=node.mesh
  for surface in range(old.get_surface_count()):
   var a=old.surface_get_arrays(surface)
   var b=new_mesh.surface_get_arrays(surface)
   for attribute in range(Mesh.ARRAY_MAX):
    if attribute==Mesh.ARRAY_TANGENT or attribute==Mesh.ARRAY_NORMAL or (old.surface_get_format(surface) & (1 << attribute)) == 0:continue
    assert(a[attribute]==b[attribute],str(node.name," surface ",surface," changed attribute ",attribute))
   assert(old.surface_get_material(surface)==new_mesh.surface_get_material(surface))
   assert(Repair._lods(old,surface)==Repair._lods(new_mesh,surface))
  assert(old.shadow_mesh==new_mesh.shadow_mesh)
 print("REPAIR_PRESERVATION_PASS ",originals.size()," meshes checked")
 root.free()
 quit()
