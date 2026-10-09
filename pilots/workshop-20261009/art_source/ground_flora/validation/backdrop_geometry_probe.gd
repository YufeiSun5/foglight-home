extends SceneTree
func _initialize():
	var src=load("/workspace/shared/foglight-town-pilot-20261009/src/ground_flora.gd")
	var parent=Node3D.new()
	root.add_child(parent)
	var field=src.apply(parent)
	var arr=field.get_node("SoftStoneEarth_PathAndBanks").mesh.surface_get_arrays(0)
	var min_y=1.0
	var minimum=Vector3.INF
	var maximum=-Vector3.INF
	for n in arr[Mesh.ARRAY_NORMAL]: min_y=min(min_y,n.y)
	for v in arr[Mesh.ARRAY_VERTEX]:minimum=minimum.min(v);maximum=maximum.max(v)
	assert(min_y>0.65)
	print("TERRAIN_NORMAL_MIN_Y=",min_y," EXTENT=",minimum," TO ",maximum)
	assert(field.get_meta("backdrop_crown_volumes")==0)
	assert(field.get_meta("backdrop_added_leaves")==3660)
	assert(field.get_child_count()==18)
	print("BACKDROP_LEAVES=",field.get_meta("backdrop_added_leaves")," VOLUMES=",field.get_meta("backdrop_crown_volumes"))
	quit()
