extends SceneTree
const GameUI = preload("res://src/presentation/ui/game_ui.gd")
const GameFlow = preload("res://src/app/game_flow.gd")
const MemorySave = preload("res://tests/ui/memory_save.gd")
const Content = preload("res://src/adapters/content_loader.gd")
const Appearance = preload("res://src/presentation/ui/appearance_view.gd")
var checks = 0
var failures: Array[String] = []
var sent: Array[Dictionary] = []
var ui: Control
var app: RefCounted
var port: RefCounted

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var loaded = Content.load_chapter()
	check(loaded.ok, "approved chapter loads")
	port = MemorySave.new()
	app = GameFlow.new(loaded.nodes, port)
	root.size = Vector2i(1280, 720)
	ui = GameUI.new()
	root.add_child(ui)
	ui.bind_flow(app)
	ui.intent_requested.connect(_submit)
	await settle()
	check(ui.rendered_snapshot().dialogue.text == loaded.nodes.g1.text, "initial dialogue is approved content")
	check(ui.theme.default_font.data == FileAccess.get_file_as_bytes("res://assets/fonts/FoglightUI-SC.otf"), "imported font matches current licensed subset bytes")
	var before = app.view().story
	ui._refresh()
	ui._refresh()
	check(app.view().story == before and port.writes == 0, "redraw has no persistent state or save side effects")
	var exposed = ui.rendered_snapshot()
	exposed.story.appearance.coat_color = "cream"
	check(app.view().appearance.coat_color == "blue", "rendered snapshot is isolated")
	var advance: Button = ui.button_for("advance")
	advance.pressed.emit()
	advance.pressed.emit()
	check(app.view().dialogue.node_id == "g2", "repeated old advance callback consumes one line only")
	check(sent.size() == 1, "old local button cannot emit twice after redraw")
	var old_command = ui.command_for("advance")
	press("wardrobe")
	check(app.view().mode == "wardrobe", "wardrobe owns input")
	before = app.view().story
	press("coat_green")
	press("bottom_long_skirt")
	check(ui.preview_appearance().coat_color == "green", "coat draft previews locally")
	check(ui.preview_appearance().bottom_id == "long_skirt", "bottom draft previews locally")
	check(app.view().story == before, "preview never mutates authoritative state")
	var stale_apply: Button = ui.button_for("apply_outfit")
	press("close")
	stale_apply.pressed.emit()
	check(app.view().appearance.coat_color == "blue" and app.view().dialogue.node_id == "g2", "cancel restores committed appearance and dialogue, old apply ignored")
	check(not app.submit(old_command).ok, "application rejects retained pre-overlay callback")
	press("wardrobe")
	check(ui.preview_appearance().bottom_id == "trousers", "reopening discards cancelled draft")
	var combinations: Dictionary = {}
	for coat in ["blue", "indigo", "green", "cream"]:
		for bottom in ["trousers", "culottes", "long_skirt", "short_skirt"]:
			press("coat_" + coat)
			press("bottom_" + bottom)
			var draft = ui.preview_appearance()
			check(draft.coat_hex == {"blue": "708ba9", "indigo": "465673", "green": "658c7c", "cream": "dbceb2"}[coat], "draft hex matches selected coat " + coat)
			var full: TextureRect = ui.find_child("WardrobeFullBody", true, false)
			var portrait: TextureRect = ui.find_child("WardrobePortrait", true, false)
			check(full.get_meta("coat_color") == portrait.get_meta("coat_color") and full.get_meta("coat_color") == coat, "matching preview coat " + coat + "/" + bottom)
			check(full.get_meta("bottom_id") == bottom, "matching preview bottom " + bottom)
			check(full.material.get_shader_parameter("coat_color") == Appearance.COAT_INDEX[coat], "full body explicit color index " + coat)
			check(portrait.material.get_shader_parameter("coat_color") == Appearance.COAT_INDEX[coat], "portrait explicit color index " + coat)
			press("apply_outfit")
			check(app.view().appearance.coat_color == coat and app.view().appearance.bottom_id == bottom, "all 16 combinations available and applied " + coat + "/" + bottom)
			combinations[coat + "/" + bottom] = true
			check(ui.preview_appearance().coat_color == app.view().appearance.coat_color, "redraw adopts committed appearance")
	check(combinations.size() == 16, "16 unique combinations tested")
	press("close")
	var portrait: TextureRect = ui.find_child("SpeakerPortrait", true, false)
	check(portrait.get_meta("coat_color") == app.view().appearance.coat_color, "dialogue portrait reads same committed appearance as world snapshot")
	check(app.submit(app.intent("save")).ok, "in-memory save succeeds")
	var saved = app.view().story
	press("wardrobe")
	press("coat_green")
	press("bottom_trousers")
	stale_apply = ui.button_for("apply_outfit")
	check(app.submit(app.intent("load")).ok, "load can interrupt wardrobe preview")
	stale_apply.pressed.emit()
	check(app.view().story == saved, "load restores exact save and rejects prior draft callback")
	check(ui.preview_appearance().coat_color == saved.appearance.coat_color, "load redraw adopts restored appearance")
	press("journal")
	check(ui.find_child("JournalScroll", true, false) != null, "journal uses scroll container")
	check(ui.rendered_snapshot().journal == app.view().story.journal, "journal renders only committed lines")
	press("close")
	press("pause")
	press("new_game")
	check(ui.button_for("confirm_new_game") != null, "restart requires explicit UI confirmation")
	press("cancel_new_game")
	check(app.view().story == saved and ui.button_for("save") != null, "restart cancel preserves story and pause")
	press("close")
	# Traverse approved content, including three choices, solely via the public facade.
	for step in 180:
		var state = app.view()
		if state.story.stage == "complete": break
		if state.mode == "exploration":
			var action = "begin"
			var payload = {"target": state.story.stage}
			if state.story.stage == "cabin" and state.story.world.scene_id != "PILOT_CABIN":
				action = "travel"; payload = {"scene_id": "PILOT_CABIN"}
			elif state.story.stage == "depart" and state.story.world.scene_id != "FOG_HARBOR":
				action = "travel"; payload = {"scene_id": "FOG_HARBOR"}
			check(app.submit(app.intent(action, payload)).ok, "public story navigation " + state.story.stage)
		else:
			check(ui.rendered_snapshot().dialogue.text == loaded.nodes[state.dialogue.node_id].text, "exact displayed content " + state.dialogue.node_id)
			if state.dialogue.choices.is_empty(): press("advance")
			else:
				check(ui.button_for("advance") == null and ui.button_for("skip") == null, "branch cannot be advanced or skipped without expression")
				for choice in state.dialogue.choices:
					check(ui.button_for("choice_" + str(choice.index)).text.ends_with(choice.text), "approved choice text is intact")
				await check_layout("three_choice")
				var choice_button: Button = ui.button_for("choice_1")
				choice_button.pressed.emit()
				choice_button.pressed.emit()
	check(app.view().story.flags.get("CH01_COMPLETE", false), "full approved chapter reaches completion through UI intents")
	for resolution in [Vector2i(1280,720), Vector2i(960,540)]:
		root.size = resolution
		root.content_scale_size = resolution
		ui.set_deferred("size", Vector2(resolution))
		await settle()
		for target in ["wardrobe", "journal", "pause"]:
			press(target)
			await check_layout(str(resolution) + "/" + target)
			press("close")
	ui.unbind_flow()
	ui.queue_free()
	await process_frame
	app = null
	port = null
	await process_frame
	print("GAME UI: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _submit(command: Dictionary) -> void:
	sent.append(command.duplicate(true))
	var result: Dictionary = app.submit(command)
	check(result.get("ok", false), "visible UI action accepted: " + str(command.action) + " " + str(result.get("error", "")))

func press(key: String) -> void:
	var button = ui.button_for(key)
	check(button != null and not button.disabled, "enabled button exists: " + key)
	if button != null and not button.disabled: button.pressed.emit()

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func check_layout(label: String) -> void:
	await settle()
	var viewport = Rect2(Vector2.ZERO, Vector2(root.size))
	for key in ui.surface_rects():
		var rectangle: Rect2 = ui.surface_rects()[key]
		check(viewport.encloses(rectangle), "surface fits viewport " + label + "/" + key + " " + str(rectangle))
	for button in ui.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree(): continue
		check(viewport.encloses(button.get_global_rect()), "button fits viewport " + label + "/" + button.name)
