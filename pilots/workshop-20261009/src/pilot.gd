extends Node3D
const Flora = preload("res://src/ground_flora.gd")
var camera: Camera3D
var output_dir := "res://.qa/material-r1"
var frame := 0
func _ready() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): output_dir=arg.trim_prefix("--out=")
 DirAccess.make_dir_recursive_absolute(output_dir)
 get_viewport().msaa_3d=Viewport.MSAA_DISABLED if OS.get_cmdline_user_args().has("--no-msaa") else Viewport.MSAA_4X
 get_viewport().mesh_lod_threshold=0.0
 get_viewport().scaling_3d_mode=Viewport.SCALING_3D_MODE_BILINEAR
 get_viewport().scaling_3d_scale=2.0
 RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
 _environment()
 Flora.apply(self)
 var building:=Node3D.new()
 building.name="IndependentWorkshopAssembly"
 building.position=Vector3(3.2,0,-1.2)
 add_child(building)
 building.add_child(load("res://assets/workshop/foglight_workshop_refined3_runtime.glb").instantiate())
 building.add_child(load("res://assets/workshop_props/workshop_props.glb").instantiate())
 building.add_child(load("res://assets/workshop_props/workwall_props.glb").instantiate())
 camera=Camera3D.new()
 camera.name="ReferenceCamera"
 camera.fov=22.0
 camera.near=0.15
 camera.far=150.0
 camera.position=Vector3(-17.94555,6.67057,30.91667)
 add_child(camera)
 camera.look_at(Vector3(0,2.8,5),Vector3.UP)
 camera.current=true
 _actor()
 var basis_report=preload("res://src/mesh_basis_repair.gd").apply(building)
 FileAccess.open(output_dir+"/basis_report.json",FileAccess.WRITE).store_string(JSON.stringify(basis_report,"\t"))
 _audit(building)
func _environment() -> void:
 var env:=Environment.new()
 env.background_mode=Environment.BG_SKY
 var sky:=Sky.new()
 var sky_mat:=ProceduralSkyMaterial.new()
 sky_mat.sky_top_color=Color(0.12,0.38,0.67)
 sky_mat.sky_horizon_color=Color(0.48,0.69,0.85)
 sky_mat.ground_bottom_color=Color(0.20,0.23,0.17)
 sky_mat.ground_horizon_color=Color(0.65,0.73,0.76)
 sky_mat.sky_curve=0.4
 sky.sky_material=sky_mat
 env.sky=sky
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color=Color(0.59,0.68,0.82)
 env.ambient_light_energy=0.42
 env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 env.tonemap_exposure=1.0
 env.fog_enabled=false
 env.glow_enabled=false
 var world:=WorldEnvironment.new()
 world.environment=env
 add_child(world)
 var sun:=DirectionalLight3D.new()
 sun.name="WarmAfternoonSun"
 sun.rotation_degrees=Vector3(-43,-38,0)
 sun.light_color=Color(1.0,0.94,0.80)
 sun.light_energy=1.25
 sun.shadow_enabled=not OS.get_cmdline_user_args().has("--no-shadows")
 sun.directional_shadow_max_distance=70
 sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
 sun.shadow_bias=0.12
 sun.shadow_normal_bias=1.3
 add_child(sun)
func _actor() -> void:
 var mesh:=QuadMesh.new()
 mesh.size=Vector2(2.125,2.125)
 var mat:=ShaderMaterial.new()
 mat.shader=load("res://src/actor_pilot.gdshader")
 mat.set_shader_parameter("atlas",load("res://assets/character/idle.png"))
 var node:=MeshInstance3D.new()
 node.name="OriginalActor_IdleScaleReference"
 node.mesh=mesh
 node.material_override=mat
 node.position=Vector3(0,35.0*1.7/64.0,5)
 add_child(node)
 node.rotation.y=camera.rotation.y
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
func _audit(building:Node) -> void:
 var audit:Dictionary={"scene":"new independent workshop pilot", "viewport": [1672,941],"msaa_3d":get_viewport().msaa_3d,"scaling_3d_scale":get_viewport().scaling_3d_scale,"camera_position":str(camera.position),"camera_rotation":str(camera.rotation_degrees),"fov":camera.fov,"building_position":str(building.position),"materials":[],"original_character":"idle cell0; scale reference only; not missing r24 recovery"}
 _visit(building,audit.materials)
 FileAccess.open(output_dir+"/runtime_contract.json",FileAccess.WRITE).store_string(JSON.stringify(audit,"\t"))
func _visit(node:Node,arr:Array) -> void:
 if node is MeshInstance3D:
  var inst:=node as MeshInstance3D
  if OS.get_cmdline_user_args().has("--no-shadow-mesh") and inst.mesh is ArrayMesh:
   inst.mesh.shadow_mesh=null
  if OS.get_cmdline_user_args().has("--shader-flat"):
   var pure:=ShaderMaterial.new()
   pure.shader=load("res://src/flat_diagnostic.gdshader")
   inst.material_override=pure
  if OS.get_cmdline_user_args().has("--flat"):
   var flat:=StandardMaterial3D.new()
   flat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
   flat.albedo_color=Color(0.65,0.65,0.65)
   inst.material_override=flat
  for i in range(inst.mesh.get_surface_count()):
   var m:=inst.get_active_material(i)
   if m is StandardMaterial3D:
    if OS.get_cmdline_user_args().has("--double-sided"): m.cull_mode=BaseMaterial3D.CULL_DISABLED
    m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    var a=m.albedo_texture
    arr.append({"name":m.resource_name,"albedo":str(m.albedo_color),"normal":m.normal_enabled,"roughness_texture":m.roughness_texture!=null,"mipmaps":a.get_image().has_mipmaps() if a else null})
 for c in node.get_children(): _visit(c,arr)
func _process(_delta:float) -> void:
 frame+=1
 if frame==4: _capture.call_deferred()
func _capture() -> void:
 await RenderingServer.frame_post_draw
 var img:=get_viewport().get_texture().get_image()
 img.save_png(output_dir+"/engine_frame.png")
 var stats={"rendered_image":[img.get_width(),img.get_height()],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"rendering_method":RenderingServer.get_current_rendering_method(),"note":"static cloud native GUI capture; not a production performance acceptance"}
 FileAccess.open(output_dir+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(stats,"\t"))
 print("PILOT_CAPTURE_READY ",output_dir)

func _unhandled_key_input(event:InputEvent) -> void:
 if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: get_tree().quit()
