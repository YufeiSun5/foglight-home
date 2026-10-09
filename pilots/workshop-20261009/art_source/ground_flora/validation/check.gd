extends SceneTree
func _initialize():
	var script=load("/workspace/shared/foglight-town-pilot-20261009/src/ground_flora.gd")
	if not script:
		push_error("Ground flora load failed")
		quit(1)
		return
	var parent=Node3D.new()
	root.add_child(parent)
	var ground=script.apply(parent)
	print("GROUND_FLORA_OK nodes=",ground.get_child_count()," blades=",ground.get_meta("grass_blades")," tree_leaves=",ground.get_meta("tree_leaf_count"))
	quit()
