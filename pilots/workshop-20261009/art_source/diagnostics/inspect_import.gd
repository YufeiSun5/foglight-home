extends SceneTree
func _init():
 for path in ["res://assets/workshop/foglight_workshop_runtime.glb","res://assets/workshop_props/workshop_props.glb"]:
  print("PATH ",path)
  var packed=load(path)
  var scene=packed.instantiate()
  inspect(scene)
  scene.free()
 quit()
func inspect(node):
 if node is MeshInstance3D:
  var mesh=node.mesh
  for i in range(mesh.get_surface_count()):
   var arr=mesh.surface_get_arrays(i)
   var normals=arr[Mesh.ARRAY_NORMAL]
   var tangents=arr[Mesh.ARRAY_TANGENT]
   var verts=arr[Mesh.ARRAY_VERTEX]
   var badn=0
   var badt=0
   var badv=0
   var zero=0
   var aligned=0
   var min_n=100.0
   var max_n=0.0
   for j in range(verts.size()):
    if not verts[j].is_finite(): badv+=1
    if not normals[j].is_finite(): badn+=1
    min_n=minf(min_n,normals[j].length())
    max_n=maxf(max_n,normals[j].length())
    if tangents!=null and tangents.size()>0:
     var t=Vector3(tangents[j*4],tangents[j*4+1],tangents[j*4+2])
     if not t.is_finite(): badt+=1
     if t.length()<0.1: zero+=1
     if absf(t.dot(normals[j]))>.99: aligned+=1
   print(node.name," surface ",i," ",mesh.surface_get_material(i).resource_name," format ",mesh.surface_get_format(i)," v ",verts.size()," badv ",badv," badn ",badn," badt ",badt," tzero ",zero," aligned ",aligned," nrange ",min_n," ",max_n)
 for c in node.get_children():inspect(c)
