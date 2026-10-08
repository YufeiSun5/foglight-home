extends SceneTree
const Flow = preload("res://src/app/game_flow.gd")
const Store = preload("res://src/app/state_store.gd")
const Rules = preload("res://src/domain/story_rules.gd")
const SavePort = preload("res://src/app/ports/save_port.gd")
const WorldPort = preload("res://src/app/ports/world_port.gd")
const Content = preload("res://src/adapters/content_loader.gd")
const FileSave = preload("res://src/adapters/file_save.gd")

class MemorySave extends SavePort:
	var snapshot: Dictionary = {}
	var writes = 0
	var reads = 0
	var barriers = 0
	var epoch = 0
	var fail_write = false
	var fail_read = false
	func barrier(value: int) -> void:
		epoch = value
		barriers += 1
	func write_snapshot(state: Dictionary, request_epoch: int) -> Dictionary:
		writes += 1
		if fail_write or request_epoch != epoch: return {"ok": false, "error": "injected_write_failure"}
		if not _validator.call(state): return {"ok": false, "error": "invalid_snapshot"}
		snapshot = state.duplicate(true)
		return {"ok": true, "revision": state.revision, "sequence": writes}
	func read_snapshot() -> Dictionary:
		reads += 1
		if fail_read or snapshot.is_empty(): return {"ok": false, "error": "injected_read_failure"}
		return {"ok": true, "state": snapshot.duplicate(true), "recovered": false, "migrated": false}

class MappedWorld extends WorldPort:
	var cabin_supported = true
	var routes_supported = true
	var corrupt_mapping = false
	func resolve_snapshot(snapshot: Dictionary) -> Dictionary:
		if not cabin_supported and snapshot.world.scene_id == "PILOT_CABIN": return {"ok": false, "error": "cabin_unavailable"}
		return {"ok": true, "mapping_id": "test_reversible_scale_v1", "scene_id": snapshot.world.scene_id,
			"logical_anchor": [0.0, 0.0] if corrupt_mapping else snapshot.anchor.duplicate(),
			"visual_anchor": [snapshot.anchor[0] * 0.2, snapshot.anchor[1] * 0.1], "transformed": true}
	func logical_position(_scene_id: String, position: Array, mapping_id: String) -> Dictionary:
		if mapping_id != "test_reversible_scale_v1": return {"ok": false, "error": "stale_mapping"}
		return {"ok": true, "position": [position[0] / 0.2, position[1] / 0.1]}
	func resolve_expedition(_expedition: Dictionary) -> Dictionary:
		return {"ok": routes_supported, "error": "route_unavailable" if not routes_supported else ""}

var checks = 0
var failures: Array = []
var nodes: Dictionary
var catalog: Dictionary

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func perform(flow: RefCounted, action: String, payload: Dictionary = {}) -> Dictionary:
	return flow.submit(flow.intent(action, payload))

func fixture(world: RefCounted = null) -> Dictionary:
	var save = MemorySave.new()
	return {"save": save, "flow": Flow.new(nodes, save, catalog, world)}

func finish_dialogue(flow: RefCounted, index: int = 0) -> void:
	var count = 0
	while not flow.view().dialogue.is_empty() and count < 150:
		var dialogue: Dictionary = flow.view().dialogue
		check(perform(flow, "skip" if dialogue.choices.is_empty() else "choose", {} if dialogue.choices.is_empty() else {"index": index}).ok, "dialogue completes " + dialogue.node_id)
		count += 1
	check(count < 150, "dialogue traversal is bounded")

func _initialize() -> void:
	var content: Dictionary = Content.load_chapter()
	check(content.get("ok", false), "actual chapter content validates")
	if not content.get("ok", false): quit(1); return
	nodes = content.nodes
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json"))
	_test_views_and_commands()
	_test_wardrobe_and_interruptions()
	_test_all_story_branches()
	_test_save_load()
	_test_actual_file_save()
	_test_world_transitions()
	_test_load_preflight()
	_test_position_sampling()
	_test_routes()
	_test_route_cards()
	_test_route_world_readiness()
	print("GAME FLOW: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _test_views_and_commands() -> void:
	var f = fixture()
	var flow = f.flow
	var first: Dictionary = flow.view()
	check(first.mode == "dialogue" and first.dialogue.node_id == "g1", "starts with authorized first line")
	check(first.dialogue.text == nodes.g1.text and first.dialogue.speaker_name == Rules.NAMES[nodes.g1.speaker], "speaker and text come from actual approved content")
	check(first.chapter.title == "雾港没有出口" and first.chapter.stage_label == "港口的临时姓名", "chapter labels are approved scene titles")
	check(first.world.presentation_bound == false and first.world.mapping.visual_anchor.is_empty(), "unbound composition never claims physical scene coordinates")
	first.story.flags.clear(); first.appearance.coat_color = "invented"; first.wardrobe.coats.clear()
	check(flow.view().story.flags == Rules.BASE_FLAGS and flow.view().wardrobe.coats.size() == 4, "view deeply isolated")
	var calls = {"commits": 0, "reentrant": false}
	flow.changed.connect(func(): calls.reentrant = not perform(flow, "advance").ok)
	flow.committed.connect(func(events): calls.commits += 1; events.clear())
	var advance = flow.intent("advance")
	var alternate = flow.intent("advance")
	var result = flow.submit(advance)
	var after = flow.view().story
	check(result.ok and after.node == "g2" and calls.reentrant, "advance is atomic and signal reentrancy blocked")
	check(flow.submit(advance) == result and flow.view().story == after and calls.commits == 0, "exact replay cannot advance or republish empty-event transaction")
	check(not flow.submit(alternate).ok and flow.view().story == after, "different-id duplicate click is stale")
	var conflict = advance.duplicate(true); conflict.action = "skip"
	check(not flow.submit(conflict).ok, "same-id changed payload rejected")
	check(not flow.submit({}).ok and flow.view().story == after, "malformed command harmless")
	var injected = Store.new(nodes, MemorySave.new())
	var composed = Flow.new(injected, null, catalog)
	check(perform(composed, "advance").ok and injected.view().node == "g2", "bootstrap-injected StateStore remains sole persistent writer")

func _test_wardrobe_and_interruptions() -> void:
	var f = fixture()
	var flow = f.flow
	perform(flow, "advance")
	var original = flow.view().story
	var stale = flow.intent("advance")
	check(perform(flow, "open_wardrobe").ok and flow.view().input_owner == "wardrobe", "wardrobe takes input ownership")
	check(flow.view().story == original, "opening wardrobe does not commit story")
	check(not flow.submit(stale).ok and not perform(flow, "advance").ok, "underlying dialogue and stale callbacks are blocked")
	check(perform(flow, "close").ok and flow.view().story == original, "cancel preview is mutation free")
	check(not flow.submit(stale).ok, "dismissed overlay never revalidates old callbacks")
	perform(flow, "open_wardrobe")
	for color in Rules.COLORS:
		for bottom in Rules.BOTTOMS:
			check(perform(flow, "outfit", {"coat_color": color, "bottom_id": bottom}).ok, "fixed wardrobe immediately available " + color + "/" + bottom)
			var view: Dictionary = flow.view()
			check(view.appearance.coat_color == view.story.appearance.coat_color and view.appearance.bottom_id == bottom and view.appearance.coat_hex == Rules.COLORS[color], "single world/portrait appearance source")
	var before = flow.view().story
	check(not perform(flow, "outfit", {"coat_color": "green", "bottom_id": "locked"}).ok and flow.view().story == before, "invalid outfit rejects entire batch")
	check(before.stage == "gate" and before.flags == original.flags and before.choices.is_empty(), "wardrobe cannot advance or reward story")
	perform(flow, "close")
	check(perform(flow, "suspend").ok and flow.view().story.resume_node == "g2", "dialogue cancellation preserves unread story line")
	for target in ["shen", "xu", "qi", "board", "bag", "mirror"]:
		check(perform(flow, "begin", {"target": target}).ok, "free optional interaction " + target)
		finish_dialogue(flow)
		check(flow.view().story.resume_node == "g2" and flow.view().story.stage == "gate", "optional dialogue preserves main progress")
	check(perform(flow, "begin", {"target": "continue"}).ok and flow.view().story.node == "g2", "resume exact unread line")
	check(perform(flow, "open_journal").ok and not flow.view().journal.is_empty(), "recorded dialogue remains readable")
	check(perform(flow, "close").ok and flow.view().mode == "dialogue", "journal cancellation restores dialogue owner")

func _test_all_story_branches() -> void:
	for intro in 3:
		for clothes in 3:
			for terms in 3:
				var flow = fixture().flow
				for stage in ["gate", "meet", "repair", "cabin", "depart"]:
					if flow.view().story.node == "": check(perform(flow, "begin", {"target": stage}).ok, "continue approved story stage " + stage)
					var count = 0
					while flow.view().story.node != "" and count < 150:
						var dialogue: Dictionary = flow.view().dialogue
						var selected = intro if dialogue.node_id == "m5" else clothes if dialogue.node_id == "c5" else terms
						check(perform(flow, "skip" if dialogue.choices.is_empty() else "choose", {} if dialogue.choices.is_empty() else {"index": selected}).ok, "all expression routes retain exits")
						count += 1
					check(count < 150, "full chapter traversal bounded")
				var final: Dictionary = flow.view().story
				check(final.stage == "complete" and final.flags.CH01_COMPLETE and final.choices.size() == 3, "chapter completes with three recorded expression choices")
				check(final.choices.m5 == nodes.m5.choices[intro].id and final.choices.c5 == nodes.c5.choices[clothes].id and final.choices.c13 == nodes.c13.choices[terms].id, "all 27 distinct combinations select their exact authored IDs")
				check(final.appearance == Rules.fresh().appearance and final.story_time.time_slot == "night", "narrative neither overwrites outfit nor daylight study changes story clock")

func _test_save_load() -> void:
	var f = fixture()
	var flow = f.flow
	perform(flow, "advance")
	check(perform(flow, "save").ok and not flow.view().unsaved, "save success only from injected receipt")
	var expected = flow.view().story
	perform(flow, "advance")
	var old = flow.intent("advance")
	check(perform(flow, "load").ok and flow.view().story == expected, "load restores committed story including ledger")
	check(not flow.submit(old).ok, "loaded epoch rejects old callback")
	f.save.fail_read = true
	var context = flow.view().context
	check(not perform(flow, "load").ok and flow.view().story == expected and flow.view().context == context, "failed load preserves state and input generation")
	f.save.fail_read = false
	perform(flow, "advance")
	f.save.fail_write = true
	check(not perform(flow, "save").ok and flow.view().unsaved, "write failure cannot claim saved status")
	f.save.fail_write = false
	check(perform(flow, "save").ok and not flow.view().unsaved, "save retry succeeds without replaying story")
	old = flow.intent("advance")
	check(perform(flow, "new_game").ok and flow.view().story.revision == 0 and flow.view().unsaved, "new game uses fresh epoch without overwriting slot")
	check(not flow.submit(old).ok and f.save.snapshot.node == "g3", "new game cancels callbacks and preserves existing slot")

func _test_actual_file_save() -> void:
	var root = "/tmp/foglight-flow-file-save-" + str(Time.get_ticks_usec())
	var port = FileSave.new(root)
	var flow = Flow.new(Store.new(nodes, port), null, catalog)
	perform(flow, "skip")
	perform(flow, "begin", {"target": "meet"})
	perform(flow, "skip")
	perform(flow, "choose", {"index": 2})
	perform(flow, "open_wardrobe")
	perform(flow, "outfit", {"coat_color": "indigo", "bottom_id": "short_skirt"})
	perform(flow, "close")
	check(perform(flow, "save").ok, "facade writes actual checksum-validated FileSave")
	var expected = flow.view().story
	var primary = FileAccess.get_file_as_string(root + "/slot.json")
	perform(flow, "suspend")
	check(perform(flow, "load").ok and flow.view().story == expected, "facade FileSave restores choices, line, wardrobe and ledger")
	check(FileAccess.get_file_as_string(root + "/slot.json") == primary, "facade load never rewrites original slot")
	perform(flow, "suspend")
	port.fault = "disk_full"
	check(not perform(flow, "save").ok and FileAccess.get_file_as_string(root + "/slot.json") == primary, "facade exposes real disk failure without changing previous valid slot")
	port.fault = ""
	check(perform(flow, "save").ok, "facade actual persistence retry succeeds")
	var recovered = Flow.new(Store.new(nodes, FileSave.new(root)), null, catalog)
	check(perform(recovered, "load").ok and recovered.view().story == flow.view().story, "second bootstrap instance restores actual file exactly")

func ready(flow: RefCounted) -> Dictionary:
	return perform(flow, "scene_ready", {"transition_id": flow.view().transition.id})

func _test_world_transitions() -> void:
	var world = MappedWorld.new()
	var f = fixture(world)
	var flow = f.flow
	perform(flow, "suspend")
	var original = flow.view().story
	f.save.fail_write = true
	check(not perform(flow, "travel", {"scene_id": "PILOT_CABIN"}).ok and flow.view().story == original and flow.view().mode == "exploration", "departure save failure leaves original world unlocked")
	f.save.fail_write = false
	check(perform(flow, "travel", {"scene_id": "PILOT_CABIN"}).get("pending", false), "world change waits for explicit readiness")
	var pending: Dictionary = flow.view().transition
	check(flow.view().story == original and f.save.snapshot == original and flow.view().input_owner == "transition", "only departure snapshot saved while preparing target")
	check(pending.target.world.scene_id == "PILOT_CABIN" and pending.target.anchor == [0.0, 1.65], "readiness target contains original logical cabin anchor")
	check(not perform(flow, "advance").ok and not perform(flow, "save").ok, "transition owns input and blocks other writes")
	check(not perform(flow, "scene_ready", {"transition_id": "old"}).ok, "wrong transition token rejected")
	var stale = flow.intent("scene_ready", {"transition_id": pending.id})
	check(perform(flow, "cancel_transition", {"transition_id": pending.id}).ok and flow.view().story == original, "cancel before readiness preserves entire original state")
	check(not flow.submit(stale).ok and flow.view().mode == "exploration", "late readiness after cancel rejected and input released")
	perform(flow, "travel", {"scene_id": "PILOT_CABIN"})
	check(ready(flow).ok and flow.view().story.world.scene_id == "PILOT_CABIN", "ready target commits through StateStore")
	check(f.save.snapshot == flow.view().story and not flow.view().unsaved, "target persisted only after readiness")
	perform(flow, "travel", {"scene_id": "FOG_HARBOR"})
	var before_return: Dictionary = flow.view().story
	f.save.fail_write = true
	var result = ready(flow)
	check(result.ok and not result.saved and flow.view().unsaved and flow.view().mode == "exploration", "second save failure leaves usable committed target with explicit warning")
	check(f.save.snapshot == before_return, "failed target write preserves departing snapshot")
	check(flow.view().story.anchor == [10.0, -8.68], "legacy harbor return anchor preserved exactly")
	check(flow.view().world.mapping.logical_anchor == [10.0, -8.68] and is_equal_approx(flow.view().world.mapping.visual_anchor[0], 2.0), "visual mapping explicitly separate from legacy logical anchor")
	f.save.fail_write = false
	check(perform(flow, "save").ok and f.save.snapshot.anchor == [10.0, -8.68], "retry preserves legacy save coordinates")
	check(perform(flow, "visual_anchor", {"position": [1.0, -0.2], "mapping_id": "test_reversible_scale_v1"}).ok and flow.view().story.anchor == [5.0, -2.0], "actual movement can use explicitly reversible mapping")
	check(not perform(flow, "visual_anchor", {"position": [1.0, 0.0], "mapping_id": "stale"}).ok, "unrecognized coordinate mapping cannot overwrite anchor")
	for malformed in [[], [1.0], [1.0, 2.0, 3.0], ["bad", 0.0], [0.0, null], [INF, 0.0], [0.0, NAN]]:
		var before_invalid: Dictionary = flow.view().story
		check(not perform(flow, "visual_anchor", {"position": malformed, "mapping_id": "test_reversible_scale_v1"}).ok and flow.view().story == before_invalid, "malformed visual coordinates rejected before adapter")
		check(perform(flow, "save").ok, "malformed coordinates never strand submission lock")
	world.corrupt_mapping = true
	original = flow.view().story
	check(not perform(flow, "anchor", {"position": [1.0, 2.0]}).ok and flow.view().story == original, "mapping cannot silently replace candidate logical position")

func _test_load_preflight() -> void:
	var world = MappedWorld.new()
	var f = fixture(world)
	var flow = f.flow
	perform(flow, "suspend")
	perform(flow, "travel", {"scene_id": "PILOT_CABIN"})
	ready(flow)
	var indoor = f.save.snapshot.duplicate(true)
	perform(flow, "new_game")
	check(ready(flow).ok, "new game world readiness completes")
	var initial = flow.view().story
	var barriers: int = f.save.barriers
	world.cabin_supported = false
	check(not perform(flow, "load").ok and flow.view().story == initial and f.save.snapshot == indoor and f.save.barriers == barriers, "unsupported loaded scene fails before state/barrier/file changes")
	world.cabin_supported = true
	check(perform(flow, "load").get("pending", false) and flow.view().story == initial and f.save.barriers == barriers, "supported load stages a snapshot without committing it")
	var pending = flow.view().transition
	check(perform(flow, "scene_failed", {"transition_id": pending.id, "error": "resource_failure"}).ok and flow.view().story == initial, "scene resource failure cancels staged load")
	perform(flow, "load")
	f.save.snapshot = Rules.fresh()
	check(not ready(flow).ok and flow.view().story == initial and flow.view().mode == "dialogue", "changed slot during preparation rejected instead of loading unseen state")
	f.save.snapshot = indoor
	perform(flow, "load")
	var stale = flow.intent("scene_ready", {"transition_id": flow.view().transition.id})
	check(ready(flow).ok and flow.view().story == indoor and not flow.view().unsaved, "load commits validated exact snapshot after readiness")
	check(not flow.submit(stale).ok, "old load readiness callback cannot cross replacement epoch")
	var port = MemorySave.new()
	var store = Store.new(nodes, port)
	store.save()
	store.command("choose", {"node": "g1"})
	var current = store.view()
	var before_context = store.context()
	var guard = {"blocked": false}
	var result: Dictionary = store.load_game(func(candidate):
		candidate.node = "not-authoritative"
		guard.blocked = not store.command("choose", {"node": "g2"}).ok
		return {"ok": false, "error": "unsupported_scene"})
	check(not result.ok and guard.blocked and store.view() == current and store.context() == before_context, "load preflight receives isolated candidate and blocks reentrant mutations")

func combat_frame(pressed: bool = false, released: bool = false) -> Dictionary:
	return {"player_position": [0.0, 0.0], "player_facing": [0.0, -1.0], "enemy_position": [0.0, -1.0],
		"line_of_sight": true, "attack_pressed": pressed, "attack_released": released,
		"defend_pressed": false, "defend_released": false, "dodge_pressed": false,
		"focused": true, "paused": false, "exit": false}

func _test_routes() -> void:
	var f = fixture()
	var flow = f.flow
	check(not perform(flow, "route_start").ok and f.save.writes == 0, "route cannot consume active dialogue")
	perform(flow, "suspend")
	var original = flow.view().story
	f.save.fail_write = true
	check(not perform(flow, "route_start").ok and flow.view().mode == "exploration" and flow.view().story == original, "failed route departure save leaves original flow usable")
	f.save.fail_write = false
	check(perform(flow, "route_start", {"seed": 21, "stages": 1}).ok and flow.view().mode == "expedition", "optional route starts with unmodified story")
	var stored = f.save.snapshot.duplicate(true)
	var writes: int = f.save.writes
	var run_id: String = flow.view().expedition.run.run_id
	check(stored == original and not stored.has("run"), "only persistent state saved at departure")
	var frame = flow.intent("route_frame", combat_frame(true))
	check(flow.submit(frame).ok and not flow.submit(frame).ok, "repeated sampled frame rejected without advancing simulation twice")
	check(perform(flow, "pause").ok and flow.view().expedition.paused and not flow.view().expedition.combat.player.attack_held, "pause immediately cancels held combat input")
	check(not perform(flow, "route_frame", combat_frame()).ok, "paused UI blocks fresh combat sample")
	check(perform(flow, "close").ok, "pause closes safely")
	check(perform(flow, "open_wardrobe").ok and flow.view().expedition.paused, "wardrobe pauses and cancels route input")
	check(perform(flow, "outfit", {"coat_color": "green", "bottom_id": "culottes"}).ok, "fixed clothes remain usable inside optional route")
	check(not perform(flow, "load").ok and not perform(flow, "new_game").ok and not perform(flow, "save").ok, "route isolates main menu callbacks")
	perform(flow, "close")
	var stale = flow.intent("route_frame", combat_frame())
	var exit_command = flow.intent("route_exit")
	var result = flow.submit(exit_command)
	check(result.ok and flow.view().mode == "exploration" and not flow.view().expedition.ready, "exit discards encounter and releases input")
	check(flow.submit(exit_command) == result and flow.view().last_route.run_id == run_id, "duplicate exit has one return receipt")
	check(not flow.submit(stale).ok and f.save.writes == writes and f.save.snapshot == stored, "exit cannot execute late frame or save temporary progress")
	var after = flow.view().story
	check(after.appearance == {"coat_color": "green", "bottom_id": "culottes"} and after.flags == original.flags and after.resume_node == original.resume_node, "exit retains explicit wardrobe choice and story facts")
	perform(flow, "route_start", {"seed": 21, "stages": 1})
	check(flow.view().expedition.run.run_id != run_id and not flow.submit(stale).ok, "new route gets new identity and rejects previous run callback")
	for tick in 400:
		if not flow.view().expedition.ready: break
		check(perform(flow, "route_frame", combat_frame(tick % 42 == 0, tick % 42 == 1)).ok, "actual battle step accepted")
	check(not flow.view().expedition.ready and flow.view().last_route.reason == "completed" and flow.view().story == after, "actual combat victory returns without persistent rewards or loss")
	perform(flow, "route_start", {"seed": 22, "stages": 1})
	flow._route._combat.tick = 35999
	flow._route._combat.sim_tick = 35999
	check(perform(flow, "cancel_input").ok and not flow.view().expedition.ready and flow.view().last_route.reason == "failed", "terminal cancellation cannot strand optional run")
	check(flow.view().story == after, "failed route preserves persistent state")

func _test_route_world_readiness() -> void:
	var world = MappedWorld.new()
	var f = fixture(world)
	var flow = f.flow
	perform(flow, "suspend")
	var original = flow.view().story
	world.routes_supported = false
	check(not perform(flow, "route_start").ok and f.save.writes == 0, "missing route resources fail before saving departure")
	world.routes_supported = true
	check(perform(flow, "route_start").get("pending", false) and not flow.view().expedition.ready, "bound route waits for scene readiness")
	var transition = flow.view().transition
	check(transition.kind == "route_start" and transition.expedition.ready and flow.view().story == original, "route preparation gets isolated temporary view and unchanged logical return anchor")
	var stale = flow.intent("scene_ready", {"transition_id": transition.id})
	check(perform(flow, "cancel_transition", {"transition_id": transition.id}).ok and not flow.submit(stale).ok, "canceled route preparation discards late readiness")
	perform(flow, "route_start")
	check(ready(flow).ok and flow.view().expedition.ready, "route activates only after prepared scene acknowledgement")
	check(perform(flow, "route_exit").ok and flow.view().story == original and flow.view().world.mapping.logical_anchor == original.anchor, "bound route return preserves logical origin")

func _test_route_cards() -> void:
	var f = fixture()
	var flow = f.flow
	perform(flow, "suspend")
	var original = flow.view().story
	perform(flow, "route_start", {"seed": 71, "stages": 2})
	for tick in 400:
		if flow.view().expedition.run.phase == "awaiting_choice": break
		check(perform(flow, "route_frame", combat_frame(tick % 42 == 0, tick % 42 == 1)).ok, "first real encounter advances toward card offer")
	var expedition: Dictionary = flow.view().expedition
	check(expedition.run.phase == "awaiting_choice" and expedition.cards.size() == 3, "actual stage victory exposes three effective card previews")
	var id: String = expedition.cards[0].card.id
	expedition.cards.clear()
	check(flow.view().expedition.cards.size() == 3, "card preview view is isolated")
	var select = flow.intent("route_choose", {"card_id": id})
	var alternate = flow.intent("route_choose", {"card_id": id})
	var result = flow.submit(select)
	var after: Dictionary = flow.view().expedition
	check(result.ok and after.run.stage == 2 and after.run.phase == "stage_active" and after.run.ranks.has(id), "card choice enters next real encounter with its derived stats")
	check(flow.submit(select) == result and flow.view().expedition == after, "exact card retry cannot duplicate rank or restart encounter")
	check(not flow.submit(alternate).ok and flow.view().expedition == after, "different-id stale card callback rejected across encounter generation")
	var returns = {"count": 0}
	flow.committed.connect(func(events):
		for event in events:
			if event.kind == "route_returned": returns.count += 1)
	var exit = flow.intent("route_exit")
	check(flow.submit(exit).ok and flow.submit(exit).ok and returns.count == 1, "repeated exit publishes exactly one return event")
	check(flow.view().story == original and f.save.snapshot == original, "card ranks never enter persistent story or save")
	var invalid_port = MemorySave.new()
	var invalid = Flow.new(nodes, invalid_port, {})
	perform(invalid, "suspend")
	check(not perform(invalid, "route_start").ok and invalid_port.writes == 0 and invalid.view().mode == "exploration", "invalid catalog fails before departure save and never locks exploration")

func _test_position_sampling() -> void:
	var world = MappedWorld.new()
	var f = fixture(world)
	var flow = f.flow
	perform(flow, "suspend")
	var sampled = {"calls": 0, "position": [1.0, -0.2], "mapping_id": "test_reversible_scale_v1", "reentrant_blocked": false}
	flow.set_position_provider(func():
		sampled.calls += 1
		sampled.reentrant_blocked = not perform(flow, "save").ok
		return {"position": sampled.position.duplicate(), "mapping_id": sampled.mapping_id})
	var command = flow.intent("save")
	var published = {"count": 0}
	flow.changed.connect(func(): published.count += 1)
	var result = flow.submit(command)
	check(result.ok and f.save.snapshot.anchor == [5.0, -2.0] and sampled.calls == 1, "save samples exact physical position before writing persistent anchor")
	check(published.count == 1 and sampled.reentrant_blocked, "position plus action emits one refresh and refuses sampler reentrancy")
	var after = flow.view().story
	var writes: int = f.save.writes
	sampled.position = [2.0, -0.3]
	check(flow.submit(command) == result and sampled.calls == 1 and f.save.writes == writes and flow.view().story == after, "exact retry never resamples or repeats anchor/save effects")
	var stale = flow.intent("pause")
	check(perform(flow, "open_wardrobe").ok and is_equal_approx(flow.view().story.anchor[0], 10.0) and is_equal_approx(flow.view().story.anchor[1], -3.0), "menu while moving captures actual position before taking input")
	perform(flow, "close")
	var calls: int = sampled.calls
	check(not flow.submit(stale).ok and sampled.calls == calls, "stale UI command is rejected before position provider runs")
	sampled.position = [0.2, 0.3]
	check(perform(flow, "begin", {"target": "shen"}).ok and is_equal_approx(flow.view().story.anchor[0], 1.0) and is_equal_approx(flow.view().story.anchor[1], 3.0), "interaction while moving captures actual position before dialogue")
	calls = sampled.calls
	check(perform(flow, "save").ok and sampled.calls == calls, "dialogue save does not query exploration position provider")
	perform(flow, "suspend")
	sampled.position = [0.4, 0.1]
	check(perform(flow, "travel", {"scene_id": "PILOT_CABIN"}).get("pending", false) and f.save.snapshot.anchor == [2.0, 1.0], "transition departure persists latest physical position")
	calls = sampled.calls
	check(ready(flow).ok and sampled.calls == calls, "transition readiness never resamples old scene")
	flow.set_position_provider(Callable())
	perform(flow, "travel", {"scene_id": "FOG_HARBOR"})
	ready(flow)
	var original = flow.view().story
	var visual = flow.view().world.mapping.visual_anchor
	var rounded = Vector2(visual[0], visual[1])
	flow.set_position_provider(func(): return {"position": [rounded.x, rounded.y], "mapping_id": "test_reversible_scale_v1"})
	check(perform(flow, "save").ok and flow.view().story == original and f.save.snapshot.anchor == [10.0, -8.68], "unchanged float32 spawn preserves exact legacy anchor without new revision")
	for malformed in [null, [], {"position": []}, {"position": ["bad", 0]}, {"position": [INF, 0]}, {"position": [1.0, 2.0], "mapping_id": "old"}]:
		flow.set_position_provider(func(): return malformed)
		writes = f.save.writes
		check(not perform(flow, "save").ok and flow.view().story == original and f.save.writes == writes, "bad sampler refuses save without changing current position")
		flow.set_position_provider(func(): return {})
		check(perform(flow, "save").ok, "bad sampler never strands input lock")
	var absent = {"calls": 0}
	flow.set_position_provider(func(): absent.calls += 1; return {"position": [1.0, 1.0], "mapping_id": "test_reversible_scale_v1"})
	check(perform(flow, "load").get("pending", false) and absent.calls == 0, "load never resamples or mutates departing anchor")
	perform(flow, "cancel_transition", {"transition_id": flow.view().transition.id})
	check(perform(flow, "new_game").get("pending", false) and absent.calls == 0, "new game never resamples or rewrites old slot")
	perform(flow, "cancel_transition", {"transition_id": flow.view().transition.id})
	check(absent.calls == 0 and flow.view().story == original, "cancellation never invokes position provider")
