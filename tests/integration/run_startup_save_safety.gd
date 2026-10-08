extends SceneTree
## Actual primary/backup bytes, never the player's slot. Startup stays locked
## until the same two-phase load or explicitly confirmed new game succeeds.
const Content = preload("res://src/adapters/content_loader.gd")
const FileSave = preload("res://src/adapters/file_save.gd")
const Store = preload("res://src/app/state_store.gd")
const Flow = preload("res://src/app/game_flow.gd")
const WorldPort = preload("res://src/app/ports/world_port.gd")
## Test-only readiness/mapping boundary. No renderer or production world loaded.
class Layout extends WorldPort:
	func resolve_snapshot(snapshot: Dictionary) -> Dictionary:
		return {"ok": true, "mapping_id": "startup_test_identity_v1", "scene_id": snapshot.world.scene_id,
			"logical_anchor": snapshot.anchor.duplicate(), "visual_anchor": snapshot.anchor.duplicate(), "transformed": false}
class FailingLayout extends Layout:
	var fail = false
	func resolve_snapshot(snapshot: Dictionary) -> Dictionary:
		if fail: return {"ok": false, "error": "injected_missing_scene"}
		return super.resolve_snapshot(snapshot)
var nodes: Dictionary
var checks = 0
var failures: Array[String] = []
var test_root = "/tmp/foglight-startup-safety-" + str(Time.get_ticks_usec())

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func act(flow: RefCounted, action: String, payload: Dictionary = {}) -> Dictionary:
	return flow.submit(flow.intent(action, payload))
func bytes(path: String) -> Dictionary:
	var result = {}
	for file in ["slot.json", "slot.bak"]:
		result[file] = FileAccess.get_file_as_bytes(path + "/" + file) if FileAccess.file_exists(path + "/" + file) else null
	return result
func write_text(path: String, value: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()
func fixture(name: String) -> Dictionary:
	var path = test_root + "/" + name
	var port = FileSave.new(path)
	var seed = Flow.new(nodes, port)
	for step in 150:
		var view: Dictionary = seed.view()
		if view.chapter.complete: break
		if view.story.node == "": act(seed, "begin", {"target": view.story.stage})
		elif view.dialogue.choices.is_empty(): act(seed, "advance")
		else: act(seed, "choose", {"index": 2})
	check(seed.view().chapter.complete, name + ": seeded CH01_COMPLETE")
	check(act(seed, "anchor", {"position": [0.125, 12.375]}).ok, name + ": seeded exact legacy anchor")
	check(act(seed, "save").ok and act(seed, "save").ok, name + ": seeded primary and backup")
	return {"path": path, "state": seed.view().story, "bytes": bytes(path)}
func reopen(path: String, world: RefCounted = null) -> RefCounted:
	return Flow.new(Store.new(nodes, FileSave.new(path)), null, {}, world, true)
func ready(flow: RefCounted) -> Dictionary:
	return act(flow, "scene_ready", {"transition_id": flow.view().transition.id})
func same_bytes(f: Dictionary, label: String) -> void:
	check(bytes(f.path) == f.bytes, label + ": primary and backup unchanged byte-for-byte")
func blocked(flow: RefCounted, label: String) -> void:
	var state: Dictionary = flow.view().story
	for action in ["advance", "skip", "choose", "suspend", "begin", "travel", "save", "anchor", "visual_anchor", "pause", "open_wardrobe", "open_journal", "close", "route_start", "outfit"]:
		check(not act(flow, action).ok, label + ": blocked " + action)
	check(flow.view().mode == "startup" and flow.view().story == state, label + ": all accidental inputs preserve gate/state")

func _initialize() -> void:
	nodes = Content.load_chapter().nodes
	_test_relaunch_and_continue()
	_test_confirmation_and_cancel()
	_test_failed_loads()
	_test_recovery_and_corruption()
	_test_no_save_and_compatibility()
	print("STARTUP SAVE SAFETY: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	print("Isolated evidence: " + test_root)
	quit(0 if failures.is_empty() else 1)

func _test_relaunch_and_continue() -> void:
	var f = fixture("continue")
	var flow = reopen(f.path, Layout.new())
	var initial = flow.view()
	check(initial.mode == "startup" and initial.input_owner == "startup" and initial.startup.can_continue, "existing slot starts before gameplay input")
	same_bytes(f, "relaunch inspection")
	blocked(flow, "relaunch")
	same_bytes(f, "blocked departure/autosave attempts")
	var load_command = flow.intent("load")
	var duplicate = flow.intent("load")
	var loading = flow.submit(load_command)
	check(loading.ok and loading.pending and flow.view().mode == "transition", "Continue enters two-phase scene preparation")
	check(flow.view().story == initial.story and flow.view().context.epoch == initial.context.epoch, "Continue preflight has not committed replacement")
	var transition = flow.view().transition
	check(transition.target == f.state and transition.mapping.logical_anchor == f.state.anchor, "Continue stages exact completed state and legacy anchor")
	check(flow.submit(load_command) == loading and flow.view().transition == transition, "same-ID Continue replay cannot stage twice")
	check(not flow.submit(duplicate).ok, "different-ID duplicate Continue is stale")
	check(not act(flow, "save").ok and not act(flow, "suspend").ok, "transition rejects input/save before readiness")
	same_bytes(f, "Continue before readiness")
	check(ready(flow).ok and flow.view().story == f.state and flow.view().mode == "exploration", "ready Continue installs exact completed save")
	check(flow.view().startup.is_empty() and not flow.view().unsaved, "successful Continue alone clears gate and saved marker")
	check(not flow.submit(load_command).ok, "old-session Continue cannot replace again")
	same_bytes(f, "Continue success")
	check(act(flow, "travel", {"scene_id": "PILOT_CABIN"}).get("pending", false), "continued game can depart and autosave")
	check(ready(flow).ok, "continued game can finish second transition autosave")
	var verify = FileSave.new(f.path)
	for file in ["slot.json", "slot.bak"]:
		check(verify._read(f.path + "/" + file).get("state", {}).get("flags", {}).get("CH01_COMPLETE", false), "post-Continue autosaves retain completion in " + file)

func _test_confirmation_and_cancel() -> void:
	var f = fixture("new_game")
	var flow = reopen(f.path, Layout.new())
	var initial = flow.view().story
	check(not act(flow, "confirm_new_game").ok, "cannot bypass new-game confirmation")
	var request = flow.intent("new_game")
	check(flow.submit(request).get("confirmation_required", false) and flow.view().startup.confirm_new_game, "New Game first asks confirmation in application")
	var old_confirm = flow.intent("confirm_new_game")
	check(act(flow, "cancel_new_game").ok and flow.view().mode == "startup", "Cancel returns to save choice")
	check(not flow.submit(old_confirm).ok and flow.view().story == initial, "canceled confirmation callbacks cannot start fresh")
	same_bytes(f, "cancel confirmation")
	blocked(flow, "after cancellation")
	act(flow, "new_game")
	check(act(flow, "confirm_new_game").get("pending", false), "explicit confirmation stages fresh scene")
	var id: String = flow.view().transition.id
	var late = flow.intent("scene_ready", {"transition_id": id})
	check(act(flow, "cancel_transition", {"transition_id": id}).ok, "fresh-scene preparation can be canceled")
	check(flow.view().mode == "startup" and not flow.submit(late).ok, "cancel new scene retains startup and rejects late readiness")
	same_bytes(f, "cancel new scene")
	act(flow, "new_game")
	act(flow, "confirm_new_game")
	id = flow.view().transition.id
	check(act(flow, "scene_failed", {"transition_id": id, "error": "injected_collision"}).ok and flow.view().mode == "startup", "new-game scene failure stays safely gated")
	same_bytes(f, "failed new scene")
	act(flow, "new_game")
	act(flow, "confirm_new_game")
	check(ready(flow).ok and flow.view().mode == "dialogue" and flow.view().story.node == "g1", "confirmed ready fresh game unlocks authored first line")
	same_bytes(f, "confirmed fresh game before its first save")
	act(flow, "suspend")
	check(act(flow, "travel", {"scene_id": "PILOT_CABIN"}).get("pending", false) and ready(flow).ok, "explicitly chosen fresh game may autosave normally")
	var verify = FileSave.new(f.path)
	for file in ["slot.json", "slot.bak"]:
		check(verify._read(f.path + "/" + file).get("state", {}).get("stage") == "gate", "only explicit confirmed fresh choice permits replacing " + file)

func _test_failed_loads() -> void:
	var f = fixture("failures")
	var mapping = FailingLayout.new()
	var flow = reopen(f.path, mapping)
	mapping.fail = true
	check(not act(flow, "load").ok and flow.view().mode == "startup", "unavailable mapping fails before replacement")
	same_bytes(f, "mapping failure")
	mapping.fail = false
	act(flow, "load")
	var id: String = flow.view().transition.id
	var late = flow.intent("scene_ready", {"transition_id": id})
	check(act(flow, "cancel_transition", {"transition_id": id}).ok, "Continue can cancel scene preparation")
	check(flow.view().mode == "startup" and not flow.submit(late).ok, "canceled Continue remains gated and rejects late readiness")
	same_bytes(f, "cancel Continue")
	act(flow, "load")
	id = flow.view().transition.id
	check(act(flow, "scene_failed", {"transition_id": id, "error": "injected_scene_failure"}).ok and flow.view().mode == "startup", "Continue scene failure keeps menu recoverable")
	same_bytes(f, "Continue scene failure")
	act(flow, "load")
	mapping.fail = true
	check(not ready(flow).ok and flow.view().mode == "startup", "second-phase validation failure never falls back to fresh play")
	same_bytes(f, "second-phase mapping failure")
	mapping.fail = false
	act(flow, "load")
	var external = Flow.new(nodes, FileSave.new(f.path))
	act(external, "advance")
	act(external, "save")
	var changed_bytes = bytes(f.path)
	check(not ready(flow).ok and flow.view().mode == "startup", "save changed during preparation is rejected")
	check(bytes(f.path) == changed_bytes, "rejected changed save is never overwritten")
	check(act(flow, "load").get("pending", false) and ready(flow).ok and flow.view().story.node == "g2", "Continue retries current validated bytes successfully")

func _test_recovery_and_corruption() -> void:
	var f = fixture("recovery")
	write_text(f.path + "/slot.json", "broken primary")
	f.bytes = bytes(f.path)
	var flow = reopen(f.path, Layout.new())
	check(flow.view().mode == "startup" and flow.view().startup.recovered, "recoverable backup still requires startup choice")
	check(act(flow, "load").get("pending", false), "backup Continue prepares target")
	var result = ready(flow)
	check(result.ok and result.recovered and flow.view().story == f.state, "backup Continue restores exact completion")
	same_bytes(f, "recovered Continue leaves original damaged primary/valid backup intact")
	write_text(f.path + "/slot.bak", "broken backup")
	f.bytes = bytes(f.path)
	flow = reopen(f.path, Layout.new())
	check(flow.view().mode == "startup" and not flow.view().startup.can_continue, "both corrupt slots are not mistaken for no save")
	check(not act(flow, "load").ok, "corrupt Continue returns error")
	blocked(flow, "failed corrupt Continue")
	same_bytes(f, "corrupt files preserved")
	f = fixture("future_version")
	write_text(f.path + "/slot.json", JSON.stringify({"format": 99}))
	f.bytes = bytes(f.path)
	flow = reopen(f.path, Layout.new())
	check(flow.view().mode == "startup" and not flow.view().startup.can_continue, "unknown primary version is protected despite valid backup")
	check(not act(flow, "load").ok, "unknown version cannot silently recover older backup")
	same_bytes(f, "unknown version preservation")

func _test_no_save_and_compatibility() -> void:
	var path = test_root + "/empty"
	var flow = reopen(path, Layout.new())
	check(flow.view().mode == "dialogue" and flow.view().story.node == "g1", "genuinely absent save initializes fresh without prompt")
	check(not FileAccess.file_exists(path + "/slot.json"), "fresh initialization never writes implicitly")
	act(flow, "suspend")
	check(act(flow, "travel", {"scene_id": "PILOT_CABIN"}).get("pending", false) and ready(flow).ok, "no-save game can autosave normally")
	var f = fixture("headless")
	var compatible = Flow.new(nodes, FileSave.new(f.path))
	check(compatible.view().mode == "dialogue", "default core/headless constructor remains compatible")
	same_bytes(f, "default constructor remains write-free")
	flow = reopen(f.path)
	check(flow.view().mode == "startup" and act(flow, "load").ok and flow.view().story == f.state, "opt-in unbound/headless Continue works without scene callback")
	same_bytes(f, "unbound Continue preserves bytes")
