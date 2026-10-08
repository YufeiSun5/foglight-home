extends SceneTree
const GameUI = preload("res://src/presentation/ui/game_ui.gd")
const Content = preload("res://src/adapters/content_loader.gd")
const GameFlow = preload("res://src/app/game_flow.gd")
const Port = preload("res://tests/ui/memory_save.gd")
class SnapshotFixture extends RefCounted:
	signal changed
	var snapshot: Dictionary = {}
	func view() -> Dictionary: return snapshot.duplicate(true)
	func intent(action: String, payload: Dictionary = {}) -> Dictionary:
		return {"action": action, "payload": payload.duplicate(true)}
	func display(value: Dictionary) -> void:
		snapshot = value.duplicate(true)
		changed.emit()
var checks: int = 0
var failures: Array[String] = []
var ui: Control
var fixture: RefCounted
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var definitions: Dictionary = Content.load_chapter().nodes
	var real = GameFlow.new(definitions, Port.new())
	var base: Dictionary = real.view()
	fixture = SnapshotFixture.new()
	fixture.snapshot = base.duplicate(true)
	ui = GameUI.new()
	root.add_child(ui)
	ui.bind_flow(fixture)
	for resolution in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = resolution
		root.content_scale_size = resolution
		ui.set_deferred("size", Vector2(resolution))
		for node_id in definitions:
			var node: Dictionary = definitions[node_id]
			var display = base.duplicate(true)
			var choices: Array = []
			for index in node.get("choices", []).size():
				choices.append({"id": node.choices[index].id, "text": node.choices[index].text, "index": index})
			display.dialogue = {"node_id": node_id, "speaker_id": node.speaker, "speaker_name": {"star": "岑星遥", "shen": "沈砚舟", "xu": "许知微", "qi": "祁岚", "narrator": "旁白"}[node.speaker], "text": node.text, "expression": node.expression, "choices": choices, "can_advance": choices.is_empty(), "can_skip": choices.is_empty()}
			fixture.display(display)
			await settle()
			check(ui.find_child("DialogueText", true, false).text == node.text, "approved line " + node_id)
			check(ui.rendered_snapshot().dialogue.choices == choices, "approved choices " + node_id)
			check_layout(str(resolution) + "/" + node_id)
			if node.speaker in ["shen", "xu", "qi"]:
				check(ui.find_child("SpeakerPortrait", true, false).get_meta("art_kind") == "npc_idle_placeholder", "NPC asset honestly classified " + node_id)
		var long_journal = base.duplicate(true)
		long_journal.mode = "journal"
		long_journal.journal = []
		for index in 20000: long_journal.journal.append("岑星遥：" + definitions.g1.text)
		fixture.display(long_journal)
		await settle()
		check_layout(str(resolution) + "/large_journal")
		check(ui.find_children("*", "Label", true, false).size() < 40, "20000-entry journal renders bounded page")
		check(ui.button_for("journal_previous").disabled, "first page previous disabled")
		ui.button_for("journal_next").pressed.emit()
		check(not ui.button_for("journal_previous").disabled, "next journal page permits back")
		ui.button_for("journal_previous").pressed.emit()
		check(ui.button_for("journal_previous").disabled, "journal back restores first page")
		var transition = base.duplicate(true)
		transition.mode = "transition"
		transition.transition = {"id": "fixture-transition"}
		fixture.display(transition)
		await settle()
		check_layout(str(resolution) + "/transition")
		check(ui.command_for("cancel_transition").payload.transition_id == "fixture-transition", "cancel retains exact transition identity")
		check(ui.button_for("wardrobe").disabled and ui.button_for("pause").disabled, "transition blocks unrelated input")
	var combat = base.duplicate(true)
	combat.mode = "expedition"
	fixture.display(combat)
	var same_button: Button = ui.button_for("wardrobe")
	for tick in 60:
		combat.expedition = {"revision": tick, "combat": {"tick": tick}}
		combat.status = {"ok": true, "revision": tick}
		fixture.display(combat)
		check(ui.button_for("wardrobe") == same_button, "ordinary combat tick preserves toolbar and focus")
	check(ui.rendered_snapshot().expedition.revision == 59, "skipped redraw still updates isolated snapshot")
	ui.unbind_flow()
	ui.queue_free()
	await process_frame
	fixture = null
	real = null
	await process_frame
	print("UI LAYOUT: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
func settle() -> void:
	await process_frame
	await process_frame
	await process_frame
func check_layout(label: String) -> void:
	var bounds = Rect2(Vector2.ZERO, ui.size)
	for name in ui.surface_rects(): check(bounds.encloses(ui.surface_rects()[name]), "surface within viewport " + label + "/" + name)
	for control in ui.find_children("*", "Control", true, false):
		if control is Button:
			check(bounds.encloses(control.get_global_rect()), "button within viewport " + label + "/" + control.name)
		if control is Label and not control.get_parent().get_parent() is ScrollContainer:
			check(control.get_line_count() == control.get_visible_line_count(), "all label lines visible " + label + "/" + control.name)
