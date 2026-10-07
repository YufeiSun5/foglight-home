extends SceneTree
const Rules = preload("res://src/domain/tower_run_rules.gd")
const Store = preload("res://src/app/state_store.gd")
const FileSave = preload("res://src/adapters/file_save.gd")
const Story = preload("res://src/domain/story_rules.gd")
const Content = preload("res://src/adapters/content_loader.gd")
var checks = 0
var failures: Array = []
var cards: Dictionary
var command_counter = 0

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json"))
	var loaded = Rules.validate_catalog(parsed)
	check(loaded.get("ok", false), "catalog loads")
	if not loaded.get("ok", false):
		printerr(loaded)
		quit(1)
		return
	cards = loaded.cards
	_test_catalog(parsed)
	_test_transactions()
	_test_draws_and_replay()
	_test_styles_and_caps()
	_test_small_pools()
	_test_invalid_state()
	_test_story_save_isolation()
	print("TOWER RULES: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _new(seed_value: int = 17, stages: int = 8, custom: Dictionary = {}) -> Dictionary:
	return Rules.fresh("test-run", 1, seed_value, cards if custom.is_empty() else custom, stages).state

func _command(s: Dictionary, action: String, payload: Dictionary = {}, custom: Dictionary = {}) -> Dictionary:
	command_counter += 1
	var command = Rules.make_command(s, "command-" + str(command_counter), action, payload,
		"application" if action in ["clear_stage", "fail"] else "player")
	return Rules.reduce(s, command, cards if custom.is_empty() else custom)

func _choosing(seed_value: int = 17, stages: int = 8, custom: Dictionary = {}) -> Dictionary:
	var s = _new(seed_value, stages, custom)
	var c = Rules.make_command(s, "fixture-first-clear", "clear_stage", {"stage": 1}, "application")
	return Rules.reduce(s, c, cards if custom.is_empty() else custom).state

func _pick(s: Dictionary, custom: Dictionary = {}) -> Dictionary:
	return _command(s, "choose", {"stage": s.stage, "card_id": s.offer[0]}, custom).state

func _test_catalog(parsed: Dictionary) -> void:
	check(cards.size() == 9, "small initial nine-card pool")
	var copy = parsed.duplicate(true)
	var original = parsed.duplicate(true)
	var validated = Rules.validate_catalog(copy)
	validated.cards.quick_rhythm.modifiers.normal_rate = 999
	check(copy == original, "catalog input and returned definitions are isolated")
	for mutation in ["duplicate", "unknown", "nan", "unbounded", "rank", "script", "shape"]:
		var bad = parsed.duplicate(true)
		match mutation:
			"duplicate": bad.cards.append(bad.cards[0].duplicate(true))
			"unknown": bad.cards[0].modifiers["invincibility"] = 1
			"nan": bad.cards[0].modifiers.normal_rate = NAN
			"unbounded": bad.cards[0].modifiers.normal_rate = 1000
			"rank": bad.cards[0].max_rank = 100
			"script": bad.cards[0]["script"] = "anything"
			"shape": bad.cards[0].modifiers = []
		check(not Rules.validate_catalog(bad).ok, "bad catalog rejected " + mutation)
	check(not Rules.fresh("", 1, 1, cards).ok, "empty identity rejected")
	check(not Rules.fresh("run", 1, -1, cards).ok, "negative seed rejected")
	check(not Rules.fresh("run", 1, 1, cards, 25).ok, "technical stage bound")

func _test_transactions() -> void:
	var fresh = _new()
	check(fresh.phase == "stage_active" and fresh.stage == 1 and fresh.offer.is_empty(), "first encounter has no mandatory card gate")
	var s = _choosing()
	check(Rules.valid(s, cards), "fresh valid")
	var stats = Rules.stats(s, cards).stats
	check(stats.normal.enabled and stats.charge.enabled and stats.defense.enabled and stats.defense.counter_enabled, "basic normal/charge/defense/counter available without cards")
	var initial = s.duplicate(true)
	var card_id: String = s.offer[0]
	var preview = Rules.preview(s, card_id, cards)
	check(preview.ok and not preview.changes.is_empty(), "offered card has an explicit before/after effect")
	var c = Rules.make_command(s, "pick", "choose", {"stage": s.stage, "card_id": card_id})
	var c_before = c.duplicate(true)
	var definitions = cards.duplicate(true)
	var picked = Rules.reduce(s, c, cards)
	check(picked.ok and picked.state.revision == 2 and picked.state.phase == "stage_active", "one card committed")
	check(s == initial and c == c_before and cards == definitions, "reduce never mutates state/command/catalog")
	check(Rules.stats(picked.state, cards).stats == preview.after, "preview equals actual choice")
	var committed = picked.state.duplicate(true)
	var repeat = Rules.reduce(picked.state, c, cards)
	check(repeat.ok and repeat.replay and repeat.result == picked.result and repeat.state == committed and repeat.events.is_empty(), "retry receipt idempotent; no republished events")
	repeat.state.ranks[card_id] = 99
	repeat.result.action = "tampered"
	picked.events[0].card_id = "tampered"
	preview.card.name = "tampered"
	check(picked.state == committed and cards == definitions and s == initial, "all returned nested values isolated")
	var conflict = c.duplicate(true)
	conflict.payload.card_id = "other"
	check(Rules.reduce(committed, conflict, cards).error == "command_id_conflict", "same id different payload rejected")
	var stale = c.duplicate(true)
	stale.id = "double-click"
	check(Rules.reduce(committed, stale, cards).error == "stale_revision", "new id old revision rejected")
	check(not _command(committed, "choose", {"stage": committed.stage, "card_id": card_id}).ok, "current-revision second choice rejected")
	var next_run = Rules.fresh("new-run", 2, 17, cards).state
	check(Rules.reduce(next_run, c, cards).error == "stale_run", "old run callback rejected before replay")
	var wrong_epoch = c.duplicate(true)
	wrong_epoch.epoch = 0
	check(Rules.reduce(s, wrong_epoch, cards).error == "stale_run", "old epoch rejected")
	var progressed = _command(committed, "clear_stage", {"stage": committed.stage})
	check(progressed.ok and progressed.state.stage == 3, "clear advances one encounter")
	check(not _command(progressed.state, "clear_stage", {"stage": 1}).ok, "old encounter completion rejected")
	var player_clear = Rules.make_command(committed, "fake-combat", "clear_stage", {"stage": committed.stage})
	check(Rules.reduce(committed, player_clear, cards).error == "invalid_source", "UI cannot issue combat outcome")
	for action in ["exit", "fail"]:
		var ended = _command(committed, action)
		check(ended.ok and ended.state.phase == "ended" and ended.state.ranks.is_empty() and ended.state.offer.is_empty(), action + " drops run-only modifiers")
		check(Rules.stats(ended.state, cards).stats == stats, action + " restores base attack stats")
		check(not _command(ended.state, "exit").ok, action + " rejects later new commands")

func _test_draws_and_replay() -> void:
	var a = _new(1234, 24)
	var b = _new(1234, 24)
	var reordered: Dictionary = {}
	var ids = cards.keys()
	ids.reverse()
	for id in ids: reordered[id] = cards[id].duplicate(true)
	check(a == Rules.fresh("test-run", 1, 1234, reordered, 24).state, "catalog order independent seed replay")
	var global_first: int
	var global_second: int
	seed(44)
	global_first = randi()
	global_second = randi()
	seed(44)
	check(randi() == global_first, "global RNG test fixture")
	for stage in 24:
		check(a == b, "deterministic full state stage " + str(stage + 1))
		check(a.offer.size() <= 3, "bounded distinct offer " + str(stage + 1))
		if a.phase == "awaiting_choice":
			var command = Rules.make_command(a, "pick-" + str(stage), "choose", {"stage": a.stage, "card_id": a.offer[0]})
			a = Rules.reduce(a, command, cards).state
			b = Rules.reduce(b, command, cards).state
		var clear = Rules.make_command(a, "clear-" + str(stage), "clear_stage", {"stage": a.stage}, "application")
		a = Rules.reduce(a, clear, cards).state
		b = Rules.reduce(b, clear, cards).state
	check(randi() == global_second, "rule PRNG does not consume global RNG")
	check(a == b and a.phase == "ended" and a.end_reason == "completed", "deterministic complete run")
	check(a.ledger.size() <= Rules.MAX_COMMANDS and a.selections.size() <= Rules.MAX_STAGES, "state and command history bounded")
	var variants: Dictionary = {}
	for value in 40:
		var s = _choosing(value)
		variants[JSON.stringify(s.offer)] = true
		check(s.offer.size() == 3 and s.offer[0] != s.offer[1] and s.offer[1] != s.offer[2] and s.offer[0] != s.offer[2], "three unique random options " + str(value))
	check(variants.size() > 10, "different seeds produce varied options")

func _test_styles_and_caps() -> void:
	for preferred in ["far_charge", "chain_flow", "snap_focus", "counter_edge", "quick_rhythm", "long_edge", "gathered_breath", "held_horizon", "light_trace"]:
		var small = {preferred: cards[preferred].duplicate(true)}
		var s = _choosing(7, 24, small)
		var original = Rules.stats(s, small).stats
		while s.phase != "ended":
			if s.phase == "awaiting_choice":
				var p = Rules.preview(s, preferred, small)
				check(p.ok and not p.changes.is_empty(), "every offered rank effective " + preferred)
				s = _pick(s, small)
			var current = Rules.stats(s, small).stats
			check(current.normal.attack_rate_hz <= 2.7 and current.normal.reach_m <= 1.70 and current.charge.melee_reach_m <= 2.0, "attack caps " + preferred)
			check(current.charge.hold_seconds >= 0.06 and current.charge.recovery_seconds >= 0.55, "charge remains bounded " + preferred)
			check(current.normal.trail_layers <= 3 and current.charge.trail_layers <= 3 and current.effects.max_live_particles <= 48, "effect caps " + preferred)
			check(current.effects.invulnerability_seconds == 0.0 and current.effects.max_hitstop_per_attack_seconds == 0.07 and current.effects.max_hitstop_per_second_seconds == 0.12, "cards cannot stack invulnerability or hitstop " + preferred)
			if preferred == "far_charge":
				check(current.charge.mode == "ranged_charge" and current.charge.requires_charge and current.normal.mode == "melee", "same weapon charge conversion remains active")
				check(current.charge.projectile_count == 1 and current.charge.projectile_pierce <= 1 and current.charge.projectile_reach_m <= 6.0 and current.charge.projectile_speed_mps <= 12.0, "bounded projectile contract")
			if preferred == "chain_flow": check(current.charge.mode == "chain_charge" and current.charge.chain_max_targets == 3 and current.charge.chain_max_step_m == 2.0, "bounded chain contract")
			if preferred == "snap_focus": check(current.charge.hold_seconds <= 0.11 and current.charge.hold_seconds > 0, "near-instant charge has a positive windup")
			s = _command(s, "clear_stage", {"stage": s.stage}, small).state
		check(Rules.stats(s, small).stats == original, "completion clears style " + preferred)
		check(s.selections.size() == int(cards[preferred].max_rank), "max ranks removed from later offers " + preferred)
	var shapes = {"far_charge": cards.far_charge, "chain_flow": cards.chain_flow}
	for selected in shapes:
		var s = _choosing(17, 4, shapes)
		s = _command(s, "choose", {"stage": s.stage, "card_id": selected}, shapes).state
		s = _command(s, "clear_stage", {"stage": s.stage}, shapes).state
		check(s.offer.is_empty() and s.phase == "stage_active", "opposing charge shape filtered " + selected)

func _test_small_pools() -> void:
	var one = {"light_trace": cards.light_trace.duplicate(true)}
	one.light_trace.max_rank = 3 # Third cosmetic rank would exceed visual cap; never offer it.
	var s = _choosing(1, 5, one)
	check(s.offer.size() == 1, "one eligible card is a legal one-card offer")
	s = _pick(s, one)
	s = _command(s, "clear_stage", {"stage": s.stage}, one).state
	s = _pick(s, one)
	s = _command(s, "clear_stage", {"stage": s.stage}, one).state
	check(s.phase == "stage_active" and s.offer.is_empty() and s.ranks.light_trace == 2, "numeric/visual no-op filtered even below maximum rank")
	check(_command(s, "clear_stage", {"stage": s.stage}, one).ok, "empty pool does not soft-lock encounter progression")
	var two = {"quick_rhythm": cards.quick_rhythm, "long_edge": cards.long_edge}
	check(_choosing(1, 8, two).offer.size() == 2, "two eligible cards are legal")
	check(not Rules.preview(s, "light_trace", one).ok, "no preview for absent offer")

func _test_invalid_state() -> void:
	var s = _choosing()
	for field in Rules.STATE_KEYS:
		var bad = s.duplicate(true)
		bad.erase(field)
		check(not Rules.valid(bad, cards), "missing state key rejected " + field)
	for change in ["extra", "ranks", "offer", "rng", "revision", "selections", "ledger", "nan"]:
		var bad = s.duplicate(true)
		match change:
			"extra": bad["story_flags"] = {}
			"ranks": bad.ranks = {"quick_rhythm": 99}
			"offer": bad.offer = ["nonexistent"]
			"rng": bad.rng_state = 0
			"revision": bad.revision = 999
			"selections": bad.selections = [{"stage": 999, "card_id": "quick_rhythm"}]
			"ledger": bad.ledger = {"fake": {}}
			"nan": bad.seed = NAN
		check(not Rules.valid(bad, cards), "corrupt state rejected " + change)
	var changed = cards.duplicate(true)
	changed.quick_rhythm.modifiers.normal_rate = 0.13
	check(not Rules.valid(s, changed), "mid-run catalog changes rejected")
	for payload in [{}, {"stage": 1, "card_id": "no"}, {"stage": 1, "card_id": s.offer[0], "extra": true}, {"stage": NAN, "card_id": s.offer[0]}]:
		check(not _command(s, "choose", payload).ok, "malformed or unavailable pick rejected")

func _test_story_save_isolation() -> void:
	# Refuse to open the default save location unless the test harness created an isolated HOME/XDG.
	var sandbox_root = OS.get_environment("FOGLIGHT_TOWER_TEST_ROOT")
	if not sandbox_root.begins_with("/tmp/foglight-tower-"):
		check(false, "save isolation test requires fresh /tmp/foglight-tower-* HOME/XDG harness")
		return
	for name in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		if not OS.get_environment(name).begins_with(sandbox_root + "/"):
			check(false, "refusing unisolated environment " + name)
			return
	check(OS.get_user_data_dir().begins_with(sandbox_root + "/"), "Godot user data is inside temporary sandbox")
	var content = Content.load_chapter()
	check(content.ok, "story definitions load for isolation fixture")
	if not content.ok: return
	var port = FileSave.new()
	var store = Store.new(content.nodes, port)
	check(store.command("skip").ok and store.command("begin", {"target": "meet"}).ok, "fixture advances real story nodes")
	check(store.command("skip").ok and store.command("choose", {"node": "m5", "index": 2}).ok, "fixture records a real relationship expression choice")
	check(store.command("skip").ok, "fixture finishes expression branch")
	check(store.command("outfit", {"coat_color": "green", "bottom_id": "long_skirt"}).ok, "fixture has explicit outfit")
	check(store.save().ok, "write real existing story snapshot schema to temporary main slot")
	check(store.command("begin", {"target": "repair"}).ok and store.command("skip").ok and store.save().ok, "fixture retains story facts and real backup slot")
	check(store.view().choices.m5 == "m5.careful" and store.view().flags.hrt_recognition_received and store.view().flags.hrt_supply_received, "fixture explicitly includes expression and HRT narrative facts")
	var snapshot = store.view()
	var primary = FileAccess.get_file_as_bytes("user://saves/slot.json")
	var backup = FileAccess.get_file_as_bytes("user://saves/slot.bak")
	for action in ["exit", "fail"]:
		var s = _pick(_choosing())
		var ended = _command(s, action)
		check(ended.ok, "run terminal isolation " + action)
		check(store.view() == snapshot and Story.valid(store.view(), content.nodes), "live story state untouched " + action)
		check(FileAccess.get_file_as_bytes("user://saves/slot.json") == primary and FileAccess.get_file_as_bytes("user://saves/slot.bak") == backup, "real primary and backup bytes untouched " + action)
		check(store.load_game().ok and store.view() == snapshot, "existing save reload retains full story/appearance/HRT flags " + action)
	check(not Rules.valid(snapshot, cards), "story snapshot cannot enter run reducer")
	check(not store.validate_snapshot(_new()), "run snapshot cannot enter story save")
	print("TOWER SAVE ISOLATION: real FileSave roundtrip in ", OS.get_user_data_dir())
