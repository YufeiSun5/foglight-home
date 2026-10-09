extends SceneTree
func _initialize():
	for order in [[0,2,1],[0,1,2]]:
		var vertices=[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1)]
		var st=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for idx in order: st.add_vertex(vertices[idx])
		st.generate_normals()
		print("WINDING ",order," NORMALS ",st.commit_to_arrays()[Mesh.ARRAY_NORMAL])
	quit()
