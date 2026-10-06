extends CharacterBody3D
const Art = preload("res://src/presentation/pixel_art.gd")
var who = "star"
var appearance: Dictionary = {"top": "shirt", "coat": "short", "color": "blue", "bottom": "work"}
var visual: AnimatedSprite3D
var direction = 0
var walking = false
var interaction_time = 0.0
var is_player = false
var controls_enabled = false
var floor_height = 0.7
func _ready() -> void:
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new(); shape.radius = 0.27; shape.height = 1.3
	collision.shape = shape; collision.position.y = 0.65; add_child(collision)
	visual = AnimatedSprite3D.new(); visual.pixel_size = 0.027; visual.position.y = 1.27
	visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	visual.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	visual.shaded = false
	add_child(visual)
	var shadow = MeshInstance3D.new(); var mesh = CylinderMesh.new(); mesh.top_radius = 0.43; mesh.bottom_radius = 0.43; mesh.height = 0.015; shadow.mesh = mesh
	var mat = StandardMaterial3D.new(); mat.albedo_color = Color(0.035, 0.065, 0.075, 0.7); mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; shadow.material_override = mat; shadow.position.y = 0.03; add_child(shadow)
	rebuild()
func rebuild() -> void:
	if not visual: return
	var frames = SpriteFrames.new(); frames.remove_animation("default")
	for action in ["idle", "walk", "interact"]:
		for dir in range(4):
			var name = action + str(dir); frames.add_animation(name); frames.set_animation_speed(name, 7 if action == "walk" else (5 if action == "interact" else 2))
			for f in range(4 if action != "interact" else 3): frames.add_frame(name, Art.sprite(who, appearance, dir, action, f))
	visual.sprite_frames = frames
	visual.play("idle" + str(direction))
func set_outfit(value: Dictionary) -> void:
	if appearance == value: return
	appearance = value.duplicate(true); rebuild()
func interact() -> void: interaction_time = 1.0
func _physics_process(delta: float) -> void:
	interaction_time = maxf(0, interaction_time - delta)
	var v = Vector2.ZERO
	if is_player and controls_enabled:
		v = Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))).normalized()
	var world = Vector3(v.x, 0, v.y) # Camera aligned to X/Z with a slight perspective angle.
	velocity = world * 3.5
	if not is_on_floor(): velocity.y = -8.0
	move_and_slide()
	# Solid boardwalk perimeter; no lethal falls.
	if is_player:
		position.x = clampf(position.x, -10.5, 10.5); position.z = clampf(position.z, -6.0, 6.5)
	walking = v.length() > 0
	if walking:
		direction = 2 if absf(v.x) > absf(v.y) and v.x < 0 else (3 if absf(v.x) > absf(v.y) else (1 if v.y < 0 else 0))
	var anim = ("interact" if interaction_time > 0 else ("walk" if walking else "idle")) + str(direction)
	if visual.animation != anim: visual.play(anim)
