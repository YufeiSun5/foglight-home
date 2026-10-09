extends SceneTree
func _init():
 for m in ClassDB.class_get_method_list("RenderingServer"):
  if "mesh_get_surface" in m.name:print(m)
 for m in ClassDB.class_get_method_list("ArrayMesh"):
  if "lod" in m.name:print(m)
 var scene=load("res://assets/workshop/foglight_workshop_runtime.glb").instantiate()
 var mesh=scene.get_child(0).mesh
 var surface=RenderingServer.mesh_get_surface(mesh.get_rid(),0)
 print("surface keys ",surface.keys())
 print("LOD data ",surface.get("lods"))
 scene.free()
 quit()
