extends SceneTree
func _initialize():
 var flat=StandardMaterial3D.new()
 flat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 flat.albedo_color=Color(.65,.65,.65)
 var shader=flat.get_shader_rid()
 var code=RenderingServer.shader_get_code(shader)
 print(code)
 FileAccess.open("res://art_source/diagnostics/standard_flat.gdshader",FileAccess.WRITE).store_string(code)
 quit()
