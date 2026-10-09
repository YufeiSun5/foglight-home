extends SceneTree
## Run with the included validation project and writable XDG directories.
func _initialize():
	var base="/workspace/shared/foglight-town-pilot-20261009/"
	var source=load(base+"src/ground_flora.gd")
	var holder=Node3D.new()
	root.add_child(holder)
	var landscape=source.apply(holder)
	for child in landscape.get_children():
		child.owner=landscape
	var packed=PackedScene.new()
	var result=packed.pack(landscape)
	assert(result==OK,"Could not pack landscape")
	var grass_multi=landscape.get_node("CurvedGrass_ClumpedRoadVerges").multimesh
	var transform_available=grass_multi.get_instance_transform(0).origin.length()>0.1
	if transform_available:
		assert(ResourceSaver.save(packed,base+"assets/ground_flora/ground_flora.scn")==OK)
	else:
		print("PACKEDSCENE_SKIPPED: Dummy renderer does not retain valid MultiMesh readback. Use static apply in a real renderer.")
	assert(ResourceSaver.save(source._blade_mesh(),base+"assets/ground_flora/curved_grass_blade.res")==OK)
	assert(ResourceSaver.save(source._leaf_mesh(),base+"assets/ground_flora/folded_broad_leaf.res")==OK)
	assert(ResourceSaver.save(source._flower_mesh(),base+"assets/ground_flora/ivory_cup_flower.res")==OK)
	for i in range(7):
		assert(ResourceSaver.save(source._rock_mesh(710+i),base+"assets/ground_flora/broken_rock_%02d.res"%i)==OK)
	print("ASSETS_SAVED nodes=",landscape.get_child_count()," grass=",landscape.get_meta("grass_blades")," trees=",landscape.get_meta("tree_leaf_count"))
	if transform_available:
		var reload_scene=load(base+"assets/ground_flora/ground_flora.scn").instantiate()
		assert(reload_scene.get_child_count()==18)
		assert(reload_scene.get_node("CurvedGrass_ClumpedRoadVerges").multimesh.get_instance_transform(0).origin.length()>0.1)
		print("SERIALIZED_SCENE_AND_TRANSFORM_RELOAD_OK")
		reload_scene.free()
	quit()
