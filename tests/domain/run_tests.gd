extends SceneTree
const Rules = preload("res://src/domain/story_rules.gd")
const Store = preload("res://src/app/state_store.gd")
const Port = preload("res://src/app/ports/save_port.gd")
const Content = preload("res://src/adapters/content_loader.gd")
var checks = 0
var failures: Array = []
var nodes: Dictionary

func _initialize() -> void:
	var loaded = Content.load_chapter()
	check(loaded.get("ok", false), "content loads")
	if not loaded.get("ok", false):
		printerr(loaded)
		quit(1)
		return
	nodes = loaded.nodes
	_test_transactions()
	_test_interruptions()
	_test_skip_and_signals()
	_test_outfits()
	_test_all_branches()
	_test_invalid_snapshots()
	_test_travel()
	_test_command_inspection()
	print("DOMAIN: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _new() -> RefCounted: return Store.new(nodes, Port.new())

func _test_transactions() -> void:
	var store = _new()
	var initial = store.view()
	check(Rules.valid(initial, nodes), "fresh valid")
	var view = store.view()
	view.appearance.coat_color = "green"
	view.ledger["injected"] = {}
	check(store.view() == initial, "snapshot deeply isolated")
	var content = store.content()
	content.g1.text = "modified"
	check(store.line().text != "modified", "content deeply isolated")
	var request = store.make_command("choose", {"node": "g1"})
	var result = store.submit(request)
	check(result.ok and store.view().revision == 1, "first commit")
	var after = store.view()
	check(store.submit(request) == result and store.view() == after, "same ID retry is exact and side effect free")
	result.events.append({"injected": true})
	check(store.view() == after, "result deep copy")
	var conflict = request.duplicate(true)
	conflict.payload.node = "g2"
	check(not store.submit(conflict).ok and store.view() == after, "same ID different payload rejected")
	var double_click = request.duplicate(true)
	double_click.id = "new-id-same-old-click"
	check(not store.submit(double_click).ok and store.view() == after, "new ID stale click rejected")
	check(not store.command("choose", {"node": "g1"}).ok and store.view() == after, "new command cannot replay previous node")
	check(not store.command("outfit", {"coat_color": "green", "bottom_id": "illegal"}).ok and store.view() == after, "whole invalid outfit transaction rolls back")
	var old_callback = store.make_command("choose", {"node": "g2"})
	store.new_game()
	check(not store.submit(old_callback).ok and store.view().revision == 0, "new game rejects previous session callback")
	check(not store.submit({}).ok, "malformed command rejected")
	var replay = _new()
	var replay2 = _new()
	for _step in range(6):
		var state = replay.view()
		var input = {"node": state.node}
		replay.command("choose", input)
		replay2.command("choose", input)
	var a = replay.view()
	var b = replay2.view()
	a.ledger = {}
	b.ledger = {}
	check(a == b, "deterministic replay apart from command identities")

func _test_interruptions() -> void:
	var store = _new()
	store.command("choose", {"node": "g1"})
	var pending = store.make_command("choose", {"node": "g2"})
	check(store.command("suspend").ok, "suspend allowed mid scene")
	check(store.view().node == "" and store.view().resume_node == "g2", "suspend preserves unread node")
	check(not store.submit(pending).ok, "suspend invalidates previous interaction")
	for target in ["shen", "xu", "qi", "board", "bag", "mirror"]:
		check(store.command("begin", {"target": target}).ok, "free conversation " + target)
		_finish_scene(store, 0)
		check(store.view().resume_node == "g2" and store.view().stage == "gate", "optional leaves main intact " + target)
	check(store.command("begin", {"target": "continue"}).ok and store.view().node == "g2", "resume exact unread node")
	check(store.view().flags == Rules.fresh().flags, "optional does not unlock story facts")

func _test_outfits() -> void:
	var store = _new()
	for color in Rules.COLORS:
		for bottom in Rules.BOTTOMS:
			check(store.command("outfit", {"coat_color": color, "bottom_id": bottom}).ok, "all outfit combinations available from start")
	check(store.view().stage == "gate" and store.view().choices.is_empty(), "clothes never advance or gate story")
	check(store.command("anchor", {"position": [2.0, -3.0]}).ok, "stable anchor")
	var before = store.view()
	check(not store.command("anchor", {"position": [INF, 0]}).ok and store.view() == before, "nonfinite anchor rejected")
	check(not store.command("anchor", {"position": "bad"}).ok, "malformed anchor rejected")

func _finish_scene(store: RefCounted, selection: int) -> void:
	var safety = 0
	while store.view().node != "" and safety < 150:
		var state = store.view()
		var options: Array = nodes[state.node].get("choices", [])
		check(store.command("choose", {"node": state.node, "index": selection if not options.is_empty() else -1}).ok, "advance " + state.node)
		safety += 1
	check(safety < 150, "scene terminates")

func _test_all_branches() -> void:
	# All 3 x 3 x 3 expression routes must finish with no clothes/route gate.
	for intro in 3:
		for clothes in 3:
			for terms in 3:
				var store = _new()
				_finish_scene(store, 0)
				check(store.command("begin", {"target": "meet"}).ok, "meet begins")
				_finish_scene(store, intro)
				check(store.command("begin", {"target": "repair"}).ok, "repair starts with no puzzle or inventory")
				_finish_scene(store, 0)
				check(store.command("begin", {"target": "cabin"}).ok, "cabin begins")
				while store.view().node != "":
					var state = store.view()
					var index = clothes if state.node == "c5" else (terms if state.node == "c13" else -1)
					check(store.command("choose", {"node": state.node, "index": index}).ok, "cabin branch")
				check(store.command("begin", {"target": "depart"}).ok, "depart begins")
				_finish_scene(store, 0)
				check(store.view().stage == "complete" and store.view().flags.get("CH01_COMPLETE", false), "route completes")
				check(store.view().appearance == Rules.fresh().appearance, "rejecting clothes leaves all default clothing")
				check(store.view().story_time == Rules.fresh().story_time, "chapter does not rush months")
				check(store.command("begin", {"target": "shen"}).ok, "free chat after chapter completion")
				_finish_scene(store, 0)

func _test_invalid_snapshots() -> void:
	for replacement in [-1, 0.5, INF, "one"]:
		var bad = Rules.fresh()
		bad.revision = replacement
		check(not Rules.valid(bad, nodes), "invalid revision rejected")
	for key in ["node", "resume_node", "journal", "appearance", "ledger", "story_time"]:
		var bad = Rules.fresh()
		bad[key] = null
		check(not Rules.valid(bad, nodes), "invalid type rejected " + key)
	var bad = Rules.fresh()
	bad.choices["m5"] = "no-such-option"
	check(not Rules.valid(bad, nodes), "dangling choice rejected")
	bad = Rules.fresh()
	bad.stage = "complete"
	check(not Rules.valid(bad, nodes), "inconsistent completion rejected")

func _test_skip_and_signals() -> void:
	var store = _new()
	check(store.command("skip").ok and store.view().stage == "meet", "skip gate reaches exploration")
	check(store.view().revision == 1 and store.view().journal.size() == 6, "skip is one atomic transaction with full history")
	store.command("begin", {"target": "meet"})
	check(store.command("skip").ok and store.view().node == "m5", "skip stops before expression choice")
	var before = store.view()
	check(not store.command("skip").ok and store.view() == before, "skip never chooses player expression")
	store.command("choose", {"node": "m5", "index": 2})
	store.command("skip")
	store.command("begin", {"target": "repair"})
	check(store.command("skip").ok and store.view().stage == "cabin" and store.view().flags.relit, "repair performance may be skipped without gating")
	var observed = {"count": 0, "reentrant_rejected": false}
	var callback = func():
		observed.count += 1
		observed.reentrant_rejected = not store.command("anchor", {"position": [1, 1]}).ok and not store.new_game().ok
	store.changed.connect(callback)
	var request = store.make_command("outfit", {"coat_color": "green"})
	check(store.submit(request).ok and observed.reentrant_rejected, "signal callback cannot reenter transaction or reset state")
	store.submit(request)
	check(observed.count == 1, "idempotent retry does not re-emit changed")
	store.changed.disconnect(callback)
	check(store.command("anchor", {"position": [1, 1]}).ok, "input lock released after commit")

func _test_travel()->void:
	var store=_new()
	check(not store.command("travel",{"scene_id":"PILOT_CABIN"}).ok,"dialogue must be suspended before free travel")
	store.command("suspend")
	var old=store.make_command("begin",{"target":"shen"})
	var trip=store.make_command("travel",{"scene_id":"PILOT_CABIN"})
	check(store.submit(trip).ok,"cabin opens at chapter start without a task gate")
	check(store.view().world.scene_id=="PILOT_CABIN" and store.view().anchor==[0.0,1.65],"cabin has a local stable anchor")
	check(not store.submit(old).ok,"old outdoor callback rejected after travel")
	check(store.submit(trip).ok,"duplicate travel is idempotent")
	check(store.command("outfit",{"coat_color":"green","bottom_id":"culottes"}).ok,"all outfits also available indoors")
	var before=store.view()
	check(not store.command("anchor",{"position":[99,99]}).ok and store.view()==before,"invalid cabin coordinates roll back")
	check(store.command("travel",{"scene_id":"FOG_HARBOR"}).ok,"leave cabin without story gate")
	check(store.view().resume_node=="g1" and store.view().appearance.bottom_id=="culottes","free travel preserves story and clothes")
	check(not store.command("travel",{"scene_id":"unknown"}).ok,"unknown scene rejected")
	check(store.command("begin",{"target":"continue"}).ok,"story resumes after indoor excursion")

func _test_command_inspection()->void:
	var store=_new()
	var request=store.make_command("choose",{"node":"g1"})
	var before=store.view();var context=store.context()
	var inspection=store.inspect_command(request)
	check(inspection.ok and not inspection.replay,"fresh intent can be checked without committing")
	check(store.view()==before and store.context()==context,"inspection does not change state or generation")
	var invalid=store.make_command("travel",{"scene_id":"UNKNOWN"})
	check(not store.inspect_command(invalid).ok and store.view()==before,"invalid intent rejected before side effects")
	check(store.submit(request).ok,"inspected command remains committable")
	before=store.view();context=store.context()
	check(store.inspect_command(request).replay,"exact committed replay is identified before IO")
	check(store.view()==before and store.context()==context,"replay inspection is read-only")
	var stale=store.make_command("suspend")
	store.command("outfit",{"coat_color":"cream"})
	before=store.view()
	check(not store.inspect_command(stale).ok and store.view()==before,"old revision inspection cannot commit")
	store.new_game();before=store.view()
	check(not store.inspect_command(request).ok and store.view()==before,"old epoch checked before ledger replay")
