extends SceneTree
var counter=0
func _init():
 for path in ["res://assets/workshop/foglight_workshop_runtime.glb","res://assets/workshop_props/workshop_props.glb"]:
  var scene=load(path).instantiate()
  visit(scene)
  scene.free()
 quit()
func visit(node):
 if node is MeshInstance3D:
  var mesh=node.mesh
  var shadow=mesh.shadow_mesh
  if shadow:
   print(node.name," shadow surfaces ",shadow.get_surface_count()," vs ",mesh.get_surface_count())
   for si in range(mesh.get_surface_count()):
    var a=mesh.surface_get_arrays(si)
    var b=shadow.surface_get_arrays(si)
    print(" surface ",si," formats ",mesh.surface_get_format(si)," ",shadow.surface_get_format(si)," counts ",a[0].size()," ",b[0].size()," aabb ",mesh.get_aabb()," ",shadow.get_aabb())
    var id=str(counter,"_",si)
    FileAccess.open("res://art_source/diagnostics/vertices_"+id+".bin",FileAccess.WRITE).store_buffer(a[0].to_byte_array())
    FileAccess.open("res://art_source/diagnostics/shadow_"+id+".bin",FileAccess.WRITE).store_buffer(b[0].to_byte_array())
    FileAccess.open("res://art_source/diagnostics/vindices_"+id+".bin",FileAccess.WRITE).store_buffer(a[12].to_byte_array())
    FileAccess.open("res://art_source/diagnostics/sindices_"+id+".bin",FileAccess.WRITE).store_buffer(b[12].to_byte_array())
   counter+=1
 for c in node.get_children():visit(c)
