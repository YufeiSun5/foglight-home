extends Node3D
const Actor = preload("res://src/presentation/actor.gd")
var player: CharacterBody3D
var actors: Dictionary = {}
var camera: Camera3D
var beacon: OmniLight3D
var beam: MeshInstance3D
var ferry: Node3D
var elapsed = 0.0
var relit = false
var points = {"board": Vector3(-8, 0.7, 3), "bag": Vector3(-7, 0.7, 5), "meet": Vector3(-1, 0.7, -1.5), "repair": Vector3(0, 0.7, -4), "cabin": Vector3(7, 0.7, 0.5), "mirror": Vector3(8.5, 0.7, -0.7), "depart": Vector3(4, 0.7, 5), "route": Vector3(-6, 0.7, 5)}
func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new(); m.albedo_color = color; m.roughness = 0.7
	if glow > 0: m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = glow
	return m
func box(at: Vector3, size: Vector3, color: Color, solid = false, parent: Node3D = self) -> MeshInstance3D:
	var n = MeshInstance3D.new(); var mesh = BoxMesh.new(); mesh.size = size; n.mesh = mesh; n.material_override = material(color); n.position = at; parent.add_child(n)
	if solid:
		var b = StaticBody3D.new(); var c = CollisionShape3D.new(); var sh = BoxShape3D.new(); sh.size = size; c.shape = sh; b.add_child(c); b.position = at; parent.add_child(b)
	return n
func cylinder(at: Vector3, radius: float, height: float, color: Color, top = -1.0, parent: Node3D = self) -> MeshInstance3D:
	var n = MeshInstance3D.new(); var mesh = CylinderMesh.new(); mesh.top_radius = radius if top < 0 else top; mesh.bottom_radius = radius; mesh.height = height; mesh.radial_segments = 12; n.mesh = mesh; n.position = at; n.material_override = material(color); parent.add_child(n); return n
func label(text: String, at: Vector3, color = Color("c9d9ce"), size = 26) -> Label3D:
	var l = Label3D.new(); l.text = text; l.font = load("res://assets/fonts/NotoSansSC.ttf"); l.font_size = size; l.pixel_size = 0.011; l.outline_size = 8; l.modulate = color; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.position = at; add_child(l); return l
func lamp(at: Vector3) -> void:
	cylinder(at + Vector3(0, 1.2, 0), 0.055, 2.4, Color("383c40"))
	var glass = box(at + Vector3(0, 2.3, 0), Vector3(0.25, 0.37, 0.25), Color("f4ce85")); glass.material_override = material(Color("f4ce85"), 2)
	cylinder(at + Vector3(0, 2.57, 0), 0.23, 0.18, Color("313c48"), 0.03)
	var light = OmniLight3D.new(); light.position = at + Vector3(0, 2.2, 0); light.light_color = Color("ffd5a0"); light.light_energy = 1.6; light.omni_range = 6; add_child(light)
func _ready() -> void:
	var env = WorldEnvironment.new(); var e = Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color("264155"); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("7694ac"); e.ambient_light_energy = 0.38
	e.fog_enabled = true; e.fog_light_color = Color("4f718b"); e.fog_density = 0.0045; e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; env.environment = e; add_child(env)
	var moon = DirectionalLight3D.new(); moon.rotation_degrees = Vector3(-55, -25, 0); moon.light_color = Color("aec9ef"); moon.light_energy = 0.65; moon.shadow_enabled = true; add_child(moon)
	# Real animated 3D water surface, with lamps reflected by moving highlights.
	var water = MeshInstance3D.new(); var plane = PlaneMesh.new(); plane.size = Vector2(160, 160); plane.subdivide_width = 40; plane.subdivide_depth = 40; water.mesh = plane; water.position.y = -0.55
	var shader = Shader.new(); shader.code = "shader_type spatial; render_mode cull_disabled; void vertex(){ VERTEX.y += sin(VERTEX.x*0.45+TIME*0.7)*0.08+cos(VERTEX.z*0.7+TIME*0.6)*0.04; } void fragment(){ float r=(sin(VERTEX.x*2.1+VERTEX.z*0.4+TIME*0.6)+cos(VERTEX.z*3.1+VERTEX.x*0.6+TIME*0.5))*0.25+0.5; ALBEDO=mix(vec3(0.035,0.13,0.18),vec3(0.1,0.27,0.32),pow(r,8.0)); METALLIC=0.5; ROUGHNESS=0.28; }"
	var wm = ShaderMaterial.new(); wm.shader = shader; water.material_override = wm; add_child(water)
	# Continuous boardwalk. Individual planks show perspective and cast real shadows.
	box(Vector3(0, 0.35, 0), Vector3(23, 0.55, 15), Color("483d36"), true)
	for x in range(-22, 23):
		for z in range(-3, 4):
			var rng = abs((x * 17 + z * 31) % 5) * 0.017
			box(Vector3(x * 0.5, 0.635, z * 2.1), Vector3(0.475, 0.08, 2.065), Color(0.3 + rng, 0.265 + rng, 0.23 + rng))
	for x in range(-10, 12, 3):
		for z in [-7.0, 7.0]:
			cylinder(Vector3(x, -0.1, z), 0.17, 2.1, Color("4e433a")); cylinder(Vector3(x, 1.1, z), 0.1, 1.0, Color("756355"))
	# Back railing and a lowered front edge keep silhouettes readable.
	box(Vector3(0, 1.42, -7), Vector3(22, 0.1, 0.11), Color("9a8269"))
	for x in [-9, -4, 2, 9]: lamp(Vector3(x, 0.7, 3.5 if x == -9 or x == 9 else -5.8))
	# A working lighthouse in a separate 3D skyline island.
	cylinder(Vector3(-9, -0.6, -13), 5, 2.8, Color("354c51"), 3.8)
	cylinder(Vector3(-9, 5.3, -13), 1.5, 10.5, Color("8d9995"), 1.1)
	for y in [1.5, 4.0, 7.0]: cylinder(Vector3(-9, y, -13), 1.54 - y * 0.04, 0.25, Color("556872"))
	cylinder(Vector3(-9, 11, -13), 1.8, 1.0, Color("36464f"))
	cylinder(Vector3(-9, 11.8, -13), 1.45, 0.8, Color("e8c783")); cylinder(Vector3(-9, 12.8, -13), 2, 1.0, Color("3b4955"), 0.1)
	for i in range(6):
		var a = i * TAU / 6; box(Vector3(-9 + cos(a)*1.5, 11.8, -13 + sin(a)*1.5), Vector3(0.1, 1.3, 0.1), Color("394651"))
	# Distant hillside houses are meshes, not a flat backdrop.
	for i in range(15):
		var x = float(i * 4 - 25); var z = -24.0 - float(i % 3) * 4
		var h = 3.0 + float(i % 4)
		box(Vector3(x, h/2 - 0.5, z), Vector3(3.2, h, 4), Color("3f535f"))
		var roof = cylinder(Vector3(x, h + 0.4, z), 2.7, 2.2, Color("2d3f51"), 0); roof.rotation.y = PI / 4
		for y in range(1, int(h), 2): box(Vector3(x - 0.6, y, z + 2.02), Vector3(0.4, 0.6, 0.08), Color("b6a570")).material_override = material(Color("b6a570"), 1)
	# Notice board and spare maps.
	box(Vector3(-8, 1.4, 2.2), Vector3(1.55, 1.2, 0.2), Color("5d4939"), true); box(Vector3(-8, 1.46, 2.33), Vector3(1.23, 0.85, 0.025), Color("c6b897")); cylinder(Vector3(-8, 0.8, 2.2), 0.09, 1.5, Color("594c40"))
	label("雾港 · 招募绘图师", Vector3(-8, 2.35, 2.2), Color("e4d6b6"), 19)
	# The central lantern mechanism, staged automatically in story.
	cylinder(Vector3(0, 0.9, -4.5), 1.05, 0.5, Color("404b53")); cylinder(Vector3(0, 1.6, -4.5), 0.38, 1.2, Color("9e8a5b"))
	for i in range(3):
		var ring = TorusMesh.new(); ring.inner_radius = 0.55; ring.outer_radius = 0.68
		var n = MeshInstance3D.new(); n.mesh = ring; n.material_override = material(Color("b7a573")); n.position = Vector3(0, 1.55+i*0.16, -4.5); add_child(n)
	box(Vector3(0, 2.35, -4.5), Vector3(0.42, 0.52, 0.42), Color("f0d697")).material_override = material(Color("f0d697"), 3)
	beacon = OmniLight3D.new(); beacon.position = Vector3(0, 2.4, -4.5); beacon.light_color = Color("ffce86"); beacon.light_energy = 2; beacon.omni_range = 9; add_child(beacon)
	beam = box(Vector3(0, 2.3, -9.5), Vector3(0.9, 0.3, 10), Color("dfc17e")); var bm = material(Color(0.9,0.79,0.49,0.08), 1); bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; beam.material_override = bm; beam.visible = false
	label("引灯台", Vector3(0, 3.3, -4.5), Color("e9d3a6"), 23)
	# Open-front cabin: actual walls occlude sprites, optional mirror/wardrobe inside.
	box(Vector3(8, 0.82, -0.9), Vector3(5, 0.3, 5), Color("8d6d4d"))
	box(Vector3(8, 2.3, -3.2), Vector3(5.2, 3.0, 0.18), Color("5d4e44"), true)
	box(Vector3(10.5, 2.2, -0.9), Vector3(0.18, 2.8, 4.8), Color("594f47"), true)
	for x in [6.5, 9.5]:
		box(Vector3(x, 2.65, -3.05), Vector3(1, 1.1, 0.06), Color("9baeb0")); box(Vector3(x, 2.65, -3.0), Vector3(0.05, 1.1, 0.05), Color("4d4841"))
	box(Vector3(8, 1.45, 0), Vector3(2.0, 0.14, 1.2), Color("9e7954"), true)
	for x in [7.25, 8.75]: box(Vector3(x, 1.0, 0), Vector3(0.09, 0.9, 0.09), Color("70583f"))
	box(Vector3(8.8, 1.8, -1.9), Vector3(1.0, 1.7, 0.16), Color("ac9477"), true); box(Vector3(8.8, 1.82, -1.79), Vector3(0.78, 1.35, 0.025), Color("85aab4"))
	box(Vector3(6.3, 1.8, -2.5), Vector3(1.25, 1.8, 0.65), Color("5a4539"), true); box(Vector3(6.3, 1.8, -2.14), Vector3(0.04, 1.5, 0.06), Color("bfa276"))
	label("船舱 / 衣柜", Vector3(7.9, 3.4, -2.4), Color("e8d6ae"), 24)
	lamp(Vector3(9.3, 0.8, -2.2))
	# Crates make movement and sprite depth testable.
	for at in [Vector3(-4, 1.12, 1), Vector3(-4.8, 1.1, 1.3), Vector3(3, 1.1, 2.4)]:
		box(at, Vector3(0.8, 0.9, 0.8), Color("6b5743"), true)
		box(at + Vector3(0, 0, 0.41), Vector3(0.7, 0.08, 0.03), Color("aa8860"))
	# Ferry with hull, mast and folded sail.
	ferry = Node3D.new(); ferry.position = Vector3(5, 0, 10); add_child(ferry)
	cylinder(Vector3(0, 0, 0), 1.35, 0.8, Color("4d3e36"), 1.8, ferry).scale = Vector3(1,1,2.2)
	box(Vector3(0, 0.45, 0), Vector3(2.7, 0.16, 5), Color("98785b"), false, ferry)
	cylinder(Vector3(0, 3, 0), 0.06, 6, Color("705e4b"), -1, ferry)
	box(Vector3(0.1, 3.9, 0), Vector3(0.1, 2.6, 1.6), Color("b8ae95"), false, ferry)
	box(Vector3(0, 1.1, 1), Vector3(2, 1.2, 1.8), Color("615246"), false, ferry)
	box(Vector3(0, 1.15, 1.92), Vector3(0.6, 0.4, 0.08), Color("edc981"), false, ferry).material_override = material(Color("edc981"), 2)
	label("短程听潮 · 随时返回", Vector3(-6, 1.7, 5.5), Color("9fc8c4"), 19)
	label("离港栈桥", Vector3(4, 1.8, 5.6), Color("dfcdac"), 20)
	player = Actor.new(); player.is_player = true; player.position = Vector3(-7, 0.72, 4); add_child(player)
	for spec in [["shen", Vector3(-1,0.72,-1.5), "沈砚舟"], ["xu",Vector3(2.6,0.72,-2.2), "许知微"], ["qi",Vector3(4.6,0.72,-2), "祁岚"]]:
		var actor = Actor.new(); actor.who = spec[0]; actor.position = spec[1]; actor.appearance.coat = "long"; add_child(actor); actors[spec[0]] = actor; label(spec[2], actor.position + Vector3(0,2.7,0), Color("ccd9d4"), 19)
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 23.5; camera.position = Vector3(0, 15, 23); camera.far = 150; camera.current = true; add_child(camera); camera.look_at(Vector3(0, 2, -3))
func _process(delta: float) -> void:
	elapsed += delta
	if ferry: ferry.position.y = sin(elapsed*0.7)*0.07
	if beacon: beacon.light_energy = 2.2 if relit else 1.4 + sin(elapsed*2)*0.3
	if camera and player:
		var follow = Vector3(player.position.x * 0.22, 15, 23 + player.position.z * 0.18)
		camera.position = camera.position.lerp(follow, delta * 2)
		camera.look_at(Vector3(player.position.x * 0.22, 2, -3 + player.position.z * 0.18))
func nearest() -> String:
	var best = ""; var distance = 2.1
	for id in points:
		var d = Vector2(player.position.x, player.position.z).distance_to(Vector2(points[id].x, points[id].z))
		if d < distance: distance = d; best = id
	for id in actors:
		var d = player.position.distance_to(actors[id].position)
		if d < distance: distance = d; best = id
	return best
func set_state(s: Dictionary) -> void:
	player.set_outfit(s.appearance)
	relit = s.flags.get("relit", false); beam.visible = relit
