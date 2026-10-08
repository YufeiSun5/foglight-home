extends SceneTree
## Actual snapshot UI + GameFlow + FileSave, with a test-only world port.
## Readiness is delivered explicitly; this does not test physical world input.
## Uses an isolated FileSave directory and existing published character assets.
const Content = preload("res://src/adapters/content_loader.gd")
const FileSave = preload("res://src/adapters/file_save.gd")
const Flow = preload("res://src/app/game_flow.gd")
const WorldPort = preload("res://src/app/ports/world_port.gd")
## Test-only readiness/mapping boundary. No renderer or production world loaded.
class Layout extends WorldPort:
	func resolve_snapshot(snapshot: Dictionary) -> Dictionary:
		return {"ok": true, "mapping_id": "startup_test_identity_v1", "scene_id": snapshot.world.scene_id,
			"logical_anchor": snapshot.anchor.duplicate(), "visual_anchor": snapshot.anchor.duplicate(), "transformed": false}
const UI = preload("res://src/presentation/ui/game_ui.gd")
var checks = 0
var failures: Array[String] = []
var flow: RefCounted
var ui: Control
var path = "/tmp/foglight-startup-ui-" + str(Time.get_ticks_usec())
var original_bytes: Dictionary
var sent = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func act(action: String, payload: Dictionary = {}) -> Dictionary:
	return flow.submit(flow.intent(action, payload))
func bytes() -> Dictionary:
	return {"primary": FileAccess.get_file_as_bytes(path + "/slot.json"), "backup": FileAccess.get_file_as_bytes(path + "/slot.bak")}
func press(key: String) -> void:
	var button: Button = ui.button_for(key)
	check(button != null and not button.disabled, "visible enabled button " + key)
	if button != null and not button.disabled: button.pressed.emit()
func key(code: Key) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	ui._unhandled_key_input(event)
func settle() -> void:
	for frame in 4: await process_frame
func check_layout(label: String) -> void:
	var bounds = Rect2(Vector2.ZERO, ui.size)
	for name in ui.surface_rects(): check(bounds.encloses(ui.surface_rects()[name]), label + ": surface fits " + name)
	for control in ui.find_children("*", "Control", true, false):
		if control is Button: check(bounds.encloses(control.get_global_rect()), label + ": button fits " + control.name)
		if control is Label: check(control.get_line_count() == control.get_visible_line_count(), label + ": copy fully visible")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var nodes: Dictionary = Content.load_chapter().nodes
	var seed = Flow.new(nodes, FileSave.new(path))
	seed.submit(seed.intent("advance"))
	seed.submit(seed.intent("save"))
	seed.submit(seed.intent("save"))
	var saved: Dictionary = seed.view().story
	original_bytes = bytes()
	flow = Flow.new(nodes, FileSave.new(path), {}, Layout.new(), true)
	ui = UI.new()
	root.add_child(ui)
	ui.bind_flow(flow)
	ui.intent_requested.connect(func(command): sent += 1; flow.submit(command))
	await settle()
	check(flow.view().mode == "startup" and flow.view().input_owner == "startup", "startup owns application input")
	check(ui.button_for("advance") == null and ui.button_for("suspend") == null and ui.button_for("save") == null and ui.button_for("pause") == null, "only startup controls are rendered")
	var initial = flow.view().story
	for code in [KEY_ESCAPE, KEY_I, KEY_J, KEY_SPACE, KEY_1, KEY_F5, KEY_F9]: key(code)
	check(flow.view().story == initial and flow.view().mode == "startup" and sent == 0, "gameplay keyboard shortcuts are ignored on startup")
	check(bytes() == original_bytes, "shortcut attempts preserve both files")
	for resolution in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = resolution
		root.content_scale_size = resolution
		ui.set_deferred("size", Vector2(resolution))
		await settle()
		check_layout(str(resolution) + "/choice")
		check(root.gui_get_focus_owner() == ui.button_for("startup_continue"), "startup safely focuses Continue")
		var old: Button = ui.button_for("startup_new_game")
		press("startup_new_game")
		old.pressed.emit()
		check(flow.view().startup.confirm_new_game and ui.button_for("confirm_new_game") != null, "duplicate New Game opens one confirmation")
		await settle()
		check_layout(str(resolution) + "/confirmation")
		check(root.gui_get_focus_owner() == ui.button_for("cancel_new_game"), "destructive confirmation safely focuses Cancel")
		var stale: Button = ui.button_for("confirm_new_game")
		var stale_command: Dictionary = ui.command_for("confirm_new_game")
		key(KEY_ESCAPE)
		stale.pressed.emit()
		check(not flow.submit(stale_command).ok and flow.view().mode == "startup" and not flow.view().startup.confirm_new_game, "Esc cancel rejects old button and retained confirmation command")
		check(bytes() == original_bytes and flow.view().story == initial, "cancel preserves original files and live state")
	# A slot can fail after the initial probe. Display a recoverable error without
	# falling through to g1, then retry against the restored bytes.
	for file_name in ["slot.json", "slot.bak"]:
		var file = FileAccess.open(path + "/" + file_name, FileAccess.WRITE)
		file.store_string("injected corruption")
		file.close()
	var corrupted = bytes()
	press("startup_continue")
	await settle()
	check(not flow.view().status.ok and flow.view().mode == "startup", "failed Continue presents a retryable error")
	check(bytes() == corrupted and flow.view().input_owner == "startup", "failed Continue preserves files and startup input owner")
	check_layout("failed Continue")
	for file_name in {"slot.json": "primary", "slot.bak": "backup"}:
		var file = FileAccess.open(path + "/" + file_name, FileAccess.WRITE)
		file.store_buffer(original_bytes["primary" if file_name == "slot.json" else "backup"])
		file.close()
	# Explicit readiness receipts exercise UI cancellation and generation safety
	# without importing any unpublished world coordinator or scenery resources.
	press("startup_continue")
	var old_id: String = flow.view().transition.id
	var late_ready = flow.intent("scene_ready", {"transition_id": old_id})
	check(flow.view().mode == "transition" and flow.view().input_owner == "transition", "Continue owns input during scene preparation")
	check(ui.button_for("save") == null and ui.button_for("pause") == null, "preparation exposes no gameplay controls")
	press("cancel_transition")
	check(flow.view().mode == "startup", "preparation cancellation returns to menu")
	press("startup_continue")
	var new_id: String = flow.view().transition.id
	check(new_id != old_id and not flow.submit(late_ready).ok, "canceled readiness cannot complete a newer transition")
	check(flow.view().mode == "transition" and flow.view().transition.id == new_id, "newer Continue remains pending after stale receipt")
	check(flow.submit(flow.intent("scene_ready", {"transition_id": new_id})).ok, "current readiness completes Continue")
	await settle()
	check(flow.view().story == saved and flow.view().mode == "dialogue" and flow.view().transition.is_empty(), "Continue restores exact saved state")
	check(bytes() == original_bytes, "successful Continue has no write side effect")
	press("suspend")
	check(flow.view().mode == "exploration", "gameplay UI becomes available after successful Continue")
	ui.unbind_flow()
	ui.queue_free()
	await settle()
	ui = null
	flow = null
	seed = null
	await settle()
	print("STARTUP UI: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
