extends SceneTree
func _initialize():
	var src=load("/workspace/shared/foglight-town-pilot-20261009/src/ground_flora.gd")
	for kind in ["_blade_mesh","_leaf_mesh","_flower_mesh"]:
		var mesh=src.call(kind)
		var arrays=mesh.surface_get_arrays(0)
		var normal_y=0.0
		for n in arrays[Mesh.ARRAY_NORMAL]:normal_y+=n.y
		print(kind," vertexcount=",arrays[Mesh.ARRAY_VERTEX].size()," average normal Y=",normal_y/arrays[Mesh.ARRAY_NORMAL].size())
	quit()
