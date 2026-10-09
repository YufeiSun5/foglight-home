# Diagnostic helper: rebuilds meshes in memory only, leaving source meshes and GLBs untouched.
# Call sanitize(root) before capture to test malformed tangent-basis responsibility.
extends RefCounted
static func sanitize(root:Node, remove_tangents:bool=false) -> Dictionary:
 var counts={"vertices":0,"orthogonalized":0,"fallbacks":0,"surfaces":0}
 _visit(root,remove_tangents,counts)
 return counts
static func _visit(node:Node,remove_tangents:bool,counts:Dictionary):
 if node is MeshInstance3D:
  var old=node.mesh
  var mesh=ArrayMesh.new()
  for i in range(old.get_surface_count()):
   var arr=old.surface_get_arrays(i)
   var normals=arr[Mesh.ARRAY_NORMAL]
   var ts=arr[Mesh.ARRAY_TANGENT]
   if ts!=null and ts.size()>0:
    if remove_tangents:
     arr[Mesh.ARRAY_TANGENT]=null
    else:
     for j in range(normals.size()):
      var n:Vector3=normals[j].normalized()
      var tangent=Vector3(ts[j*4],ts[j*4+1],ts[j*4+2])
      counts.vertices+=1
      if absf(tangent.dot(n))>0.001 or tangent.length()<0.5: counts.orthogonalized+=1
      tangent-=n*tangent.dot(n)
      if tangent.length_squared()<0.000001:
       var helper=Vector3.UP if absf(n.y)<0.9 else Vector3.RIGHT
       tangent=helper.cross(n)
       counts.fallbacks+=1
      tangent=tangent.normalized()
      ts[j*4]=tangent.x
      ts[j*4+1]=tangent.y
      ts[j*4+2]=tangent.z
     arr[Mesh.ARRAY_TANGENT]=ts
   mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
   mesh.surface_set_material(i,old.surface_get_material(i))
   counts.surfaces+=1
  node.mesh=mesh
 for child in node.get_children():_visit(child,remove_tangents,counts)
