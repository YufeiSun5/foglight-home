extends Control
## Standalone UI review scene. Uses approved content and a volatile in-memory save.
## Not the default entry, not evidence of the 3D game or disk persistence.
const Flow = preload("res://src/app/game_flow.gd")
const UI = preload("res://src/presentation/ui/game_ui.gd")
const Save = preload("res://tests/ui/memory_save.gd")
const Content = preload("res://src/adapters/content_loader.gd")
var flow: RefCounted
var hud: Control

func _ready() -> void:
	var background = ColorRect.new()
	background.color = Color("263d45")
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var note = Label.new()
	note.text = "UI TEST HARNESS · Approved chapter text / in-memory save · No 3D scene"
	note.position = Vector2(24, 124)
	note.add_theme_color_override("font_color", Color("b6c9c6"))
	add_child(note)
	var result = Content.load_chapter()
	if not result.ok:
		note.text = result.error
		return
	flow = Flow.new(result.nodes, Save.new())
	hud = UI.new()
	add_child(hud)
	hud.intent_requested.connect(flow.submit)
	hud.bind_flow(flow)
	for argument in OS.get_cmdline_user_args():
		if argument == "--choices":
			flow.submit(flow.intent("skip"))
			flow.submit(flow.intent("begin", {"target": "meet"}))
			flow.submit(flow.intent("skip"))
		elif argument == "--wardrobe": flow.submit(flow.intent("open_wardrobe"))
		elif argument == "--journal": flow.submit(flow.intent("advance")); flow.submit(flow.intent("open_journal"))
		elif argument == "--pause": flow.submit(flow.intent("pause"))

func _exit_tree() -> void:
	if is_instance_valid(hud): hud.unbind_flow()
	flow = null
