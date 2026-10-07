extends SceneTree
const Combat = preload("res://src/domain/combat_rules.gd")
const Tower = preload("res://src/domain/tower_run_rules.gd")
var checks = 0
var failures: Array = []
var base_stats: Dictionary
var cards: Dictionary

func _initialize() -> void:
	var parsed = Tower.validate_catalog(JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json")))
	check(parsed.ok, "tower catalog loads")
	if not parsed.ok:
		quit(1)
		return
	cards = parsed.cards
	base_stats = Tower.stats(Tower.fresh("stats", 1, 1, cards).state, cards).stats
	_test_basic_attacks()
	_test_coalesced_edges()
	_test_input_priority_matrix()
	_test_enemy_and_counter()
	_test_guard_rearm()
	_test_dodge()
	_test_cleanup()
	_test_replay_and_validation()
	_test_limits_and_styles()
	print("COMBAT RULES: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _new() -> Dictionary:
	var created = Combat.fresh("combat-test", base_stats)
	check(created.ok and Combat.valid(created.state), "fresh combat valid")
	return created.state

func _frame(s: Dictionary, changes: Dictionary = {}) -> Dictionary:
	var f = {"run_id": s.run_id, "tick": s.tick + 1, "player_position": [0.0, 0.0], "player_facing": [0.0, -1.0],
		"enemy_position": [0.0, -1.0], "line_of_sight": true, "attack_pressed": false, "attack_released": false,
		"defend_pressed": false, "defend_released": false, "dodge_pressed": false, "focused": true, "paused": false, "exit": false}
	for key in changes: f[key] = changes[key]
	return f

func _step(s: Dictionary, changes: Dictionary = {}) -> Dictionary:
	var result = Combat.step(s, _frame(s, changes))
	check(result.ok, "step accepted tick " + str(s.tick + 1) + (" " + str(result.get("error", ""))))
	return result

func _advance(s: Dictionary, ticks: int, changes: Dictionary = {}) -> Dictionary:
	for _index in ticks:
		var result = _step(s, changes)
		if not result.ok: return s
		s = result.state
	return s

func _has(events: Array, kind: String) -> bool:
	for event in events:
		if event.kind == kind: return true
	return false

func _incoming(s: Dictionary) -> Dictionary:
	var n = s.duplicate(true)
	n.enemy.phase = "active"
	n.enemy.phase_tick = 0
	n.enemy.phase_duration = n.enemy.active_ticks
	n.enemy.attack_id += 1
	n.enemy.hit_done = false
	n.enemy.aim_direction = [0.0, 1.0]
	return n

func _test_basic_attacks() -> void:
	var initial = _new()
	var pressed = _step(initial, {"attack_pressed": true})
	check(pressed.state.player.phase == "windup" and pressed.state.player.charge_ticks == 1 and pressed.state.enemy.hp == 60, "press alone does not attack")
	var released = _step(pressed.state, {"attack_released": true})
	check(released.state.player.phase == "release" and released.state.player.attack_kind == "normal" and _has(released.events, "attack_started"), "tap release chooses normal only")
	var s = _advance(released.state, 2)
	check(s.enemy.hp == 50 and s.player.hit_done, "normal hits once at active tick")
	var hitstop_before: int = s.hitstop_ticks
	var next = _step(s)
	check(next.state.sim_tick == s.sim_tick + 1 and next.state.player.phase_tick == s.player.phase_tick + 1 and next.state.hitstop_ticks < hitstop_before, "visual hitstop does not freeze logical timers")
	s = _advance(next.state, 7)
	check(s.enemy.hp == 50, "same attack overlap cannot multi-hit")
	s = _step(_new(), {"attack_pressed": true, "line_of_sight": false}).state
	s = _advance(s, 53, {"line_of_sight": false})
	check(s.player.phase == "charge" and s.player.charge_ticks == 54 and s.enemy.hp == 60, "held input charges without auto normal attacks")
	s = _step(s, {"attack_released": true}).state
	s = _advance(s, 3)
	check(s.enemy.hp == 36 and s.player.attack_kind == "charge", "charged release has separate damage")
	for obstruction in ["range", "wall", "facing"]:
		var changes: Dictionary = {}
		if obstruction == "range": changes.enemy_position = [0.0, -2.5]
		if obstruction == "wall": changes.line_of_sight = false
		if obstruction == "facing": changes.player_facing = [0.0, 1.0]
		changes.attack_pressed = true
		changes.attack_released = true
		var first = _step(_new(), changes)
		changes.attack_pressed = false
		changes.attack_released = false
		s = _advance(first.state, 3, changes)
		check(s.enemy.hp == 60, "no hit through " + obstruction)
	var fast_click = _step(_new(), {"attack_pressed": true, "attack_released": true})
	check(fast_click.state.player.phase == "release" and not fast_click.state.player.attack_held, "same-tick tap never sticks held")

func _test_coalesced_edges() -> void:
	var tap = {"attack_pressed": true, "attack_released": true, "line_of_sight": false}
	var defend_tap = {"defend_pressed": true, "defend_released": true, "line_of_sight": false}
	# New same-tick tap and repeated coalesced events throughout recovery cannot stick or restart.
	var first = _step(_new(), tap)
	check(first.state.player.attack_kind == "normal" and first.state.player.attack_id == 1 and not first.state.player.attack_held, "new coalesced tap is exactly one unlatched normal attack")
	var s = first.state
	for _index in 8:
		var retry = _step(s, tap)
		check(retry.state.player.attack_id == 1 and not retry.state.player.attack_held and not _has(retry.events, "attack_started"), "coalesced repeats during recovery never start a second attack")
		s = retry.state
	# Both edges during an already-held short/charged input release that one attack only.
	for held_ticks in [3, 54]:
		s = _step(_new(), {"attack_pressed": true, "line_of_sight": false}).state
		s = _advance(s, held_ticks - 1, {"line_of_sight": false})
		var release = _step(s, tap)
		check(release.state.player.attack_kind == ("charge" if held_ticks == 54 else "normal"), "existing held coalesced release preserves charge classification " + str(held_ticks))
		check(release.state.player.attack_id == 1 and not release.state.player.attack_held and release.state.player.charge_ticks == 0, "existing held coalesced release does not re-latch " + str(held_ticks))
		s = _step(release.state, {"line_of_sight": false}).state
		check(s.player.phase == "release" and not s.player.attack_held and s.player.attack_id == 1, "released attack remains one finite action " + str(held_ticks))
	# Repeated pressed edges cannot restart a currently held charge or its clock.
	s = _step(_new(), {"attack_pressed": true, "line_of_sight": false}).state
	s = _advance(s, 9, {"attack_pressed": true, "line_of_sight": false})
	check(s.player.charge_ticks == 10 and s.player.attack_id == 0 and s.player.attack_held, "repeated press preserves the accumulated held charge")
	var defense = _step(_new(), defend_tap)
	check(not defense.state.player.defend_held and defense.state.player.phase == "idle" and defense.state.player.guard_window_spent, "new coalesced defense tap leaves no active guard window")
	s = _step(_new(), {"defend_pressed": true, "line_of_sight": false}).state
	s = _advance(s, 9, {"defend_pressed": true, "line_of_sight": false})
	check(s.player.guard_age_ticks == 10, "repeated defense press does not refresh held window")
	defense = _step(s, defend_tap)
	check(not defense.state.player.defend_held and defense.state.player.phase == "idle" and defense.state.player.guard_age_ticks == 0 and defense.state.player.guard_window_spent, "existing held coalesced defense release clears guard and window")
	var unguarded = _step(_incoming(defense.state))
	check(unguarded.state.player.hp == 88 and not _has(unguarded.events, "counter") and not _has(unguarded.events, "blocked"), "released defense cannot counter or block the next incoming attack")
	# Paused/focus-lost frames discard all coalesced edges. Release after resuming cannot revive them.
	for interruption in ["paused", "focused"]:
		s = _step(_new(), {"attack_pressed": true, "line_of_sight": false}).state
		var cancel = tap.duplicate(true)
		cancel[interruption] = false if interruption == "focused" else true
		cancel.defend_pressed = true
		cancel.defend_released = true
		var stopped = _step(s, cancel)
		check(stopped.state.status == "paused" and not stopped.state.player.attack_held and not stopped.state.player.defend_held and stopped.events.is_empty(), "interruption consumes coalesced attack/defense edges " + interruption)
		var resumed = _step(stopped.state, {"attack_released": true, "defend_released": true, "line_of_sight": false})
		check(resumed.state.player.phase == "idle" and resumed.state.player.attack_id == 0 and not resumed.state.player.attack_held and not resumed.state.player.defend_held, "resume does not replay interrupted edges " + interruption)
		var new_tap = _step(resumed.state, tap)
		check(new_tap.state.player.attack_id == 1 and new_tap.state.player.attack_kind == "normal" and not new_tap.state.player.attack_held, "fresh complete tap works after resume " + interruption)

func _test_input_priority_matrix() -> void:
	# Each row starts from the same real preparation state; release cannot hide it from interruption.
	var preparing_cases = [
		{"name": "release and guard", "edges": {"attack_released": true, "defend_pressed": true}, "phase": "guard", "cooldown": 0},
		{"name": "release and dodge", "edges": {"attack_released": true, "dodge_pressed": true}, "phase": "dodge", "cooldown": 0},
		{"name": "release guard dodge", "edges": {"attack_released": true, "defend_pressed": true, "dodge_pressed": true}, "phase": "dodge", "cooldown": 0},
		{"name": "unavailable dodge falls to guard", "edges": {"attack_released": true, "defend_pressed": true, "dodge_pressed": true}, "phase": "guard", "cooldown": 2},
		{"name": "unavailable dodge preserves release", "edges": {"attack_released": true, "dodge_pressed": true}, "phase": "release", "cooldown": 2},
		{"name": "cooldown expires before intent arbitration", "edges": {"attack_released": true, "dodge_pressed": true}, "phase": "dodge", "cooldown": 1},
		{"name": "coalesced guard tap does not suppress release", "edges": {"attack_released": true, "defend_pressed": true, "defend_released": true}, "phase": "release", "cooldown": 0},
		{"name": "coalesced attack yields to guard", "edges": {"attack_pressed": true, "attack_released": true, "defend_pressed": true}, "phase": "guard", "cooldown": 0},
		{"name": "coalesced attack yields to dodge", "edges": {"attack_pressed": true, "attack_released": true, "dodge_pressed": true}, "phase": "dodge", "cooldown": 0},
		{"name": "held preparation interrupted by guard", "edges": {"defend_pressed": true}, "phase": "guard", "cooldown": 0},
		{"name": "held preparation interrupted by dodge", "edges": {"dodge_pressed": true}, "phase": "dodge", "cooldown": 0},
	]
	for held_ticks in [3, 54]:
		var preparing = _step(_new(), {"attack_pressed": true, "line_of_sight": false}).state
		preparing = _advance(preparing, held_ticks - 1, {"line_of_sight": false})
		check(preparing.player.phase == ("windup" if held_ticks == 3 else "charge"), "priority fixture has expected preparation phase")
		for row in preparing_cases:
			var input_state = preparing.duplicate(true)
			input_state.player.dodge_cooldown = row.cooldown
			var before = input_state.duplicate(true)
			var edges = row.edges.duplicate(true)
			edges.line_of_sight = false
			var outcome = _step(input_state, edges)
			var label = row.name + " held=" + str(held_ticks)
			check(outcome.state.player.phase == row.phase and input_state == before, "priority and input isolation " + label)
			check(not outcome.state.player.attack_held and outcome.state.player.charge_ticks == 0, "no latent attack after competing intent " + label)
			if row.phase == "release":
				check(outcome.state.player.attack_id == 1 and _has(outcome.events, "attack_started") and outcome.state.player.attack_kind == ("normal" if held_ticks == 3 else "charge"), "only uncanceled release starts attack " + label)
			else:
				check(outcome.state.player.attack_id == 0 and not _has(outcome.events, "attack_started") and not _has(outcome.events, "hit"), "interrupted release produces no attack or hit " + label)
				check(outcome.state.player.defend_held == (row.phase == "guard"), "only winning guard intent retains defense " + label)
				var after = _advance(outcome.state, 5, {"line_of_sight": false})
				check(after.player.attack_id == 0 and after.enemy.hp == 60, "canceled attack never emerges later " + label)
	# Releasing held guard can immediately start a new attack; a dodge still has higher priority.
	var guarded = _step(_new(), {"defend_pressed": true, "line_of_sight": false}).state
	var guard_exit_cases = [
		{"name": "release guard and press attack", "edges": {"defend_released": true, "attack_pressed": true}, "phase": "windup", "held": true, "attack_id": 0},
		{"name": "release guard and complete tap", "edges": {"defend_released": true, "attack_pressed": true, "attack_released": true}, "phase": "release", "held": false, "attack_id": 1},
		{"name": "release guard attack and dodge", "edges": {"defend_released": true, "attack_pressed": true, "dodge_pressed": true}, "phase": "dodge", "held": false, "attack_id": 0},
	]
	for row in guard_exit_cases:
		var edges = row.edges.duplicate(true)
		edges.line_of_sight = false
		var outcome = _step(guarded, edges)
		check(outcome.state.player.phase == row.phase and outcome.state.player.attack_held == row.held and not outcome.state.player.defend_held and outcome.state.player.attack_id == row.attack_id, row.name)
	# An attack already released on an earlier tick keeps its recovery, including counter recovery.
	var normal = _step(_new(), {"attack_pressed": true, "attack_released": true, "line_of_sight": false}).state
	var charging = _step(_new(), {"attack_pressed": true, "line_of_sight": false}).state
	charging = _advance(charging, 53, {"line_of_sight": false})
	var charged = _step(charging, {"attack_released": true, "line_of_sight": false}).state
	var counter = _step(_incoming(_new()), {"defend_pressed": true}).state
	for recovery in [normal, charged, counter]:
		for edges in [{"defend_pressed": true}, {"dodge_pressed": true}, {"attack_released": true, "defend_pressed": true, "dodge_pressed": true}, {"defend_released": true, "attack_pressed": true}]:
			var command_edges = edges.duplicate(true)
			command_edges.line_of_sight = false
			var result = _step(recovery, command_edges)
			check(result.state.player.phase == recovery.player.phase and result.state.player.phase_duration == recovery.player.phase_duration and result.state.player.phase_tick == recovery.player.phase_tick + 1, "already released recovery is not canceled " + recovery.player.attack_kind + str(edges))
			check(result.state.player.attack_id == recovery.player.attack_id and not _has(result.events, "attack_started") and not _has(result.events, "dodge_started"), "recovery inputs cannot spawn extra attacks or dodges")

func _test_enemy_and_counter() -> void:
	var distant = _advance(_new(), 40, {"enemy_position": [0.0, -2.2]})
	check(distant.enemy.phase == "idle", "enemy follows at two metres instead of telegraphing out of range")
	distant = _step(distant, {"enemy_position": [0.0, -1.9]}).state
	var nearby = _step(distant, {"enemy_position": [0.0, -1.7]})
	check(nearby.state.enemy.phase == "telegraph" and _has(nearby.events, "enemy_telegraph"), "enemy starts windup only inside reach plus small approach margin")
	var s = _advance(_new(), 30)
	check(s.enemy.phase == "telegraph" and s.enemy.phase_duration == 36 and s.enemy.reach_m == 1.65, "enemy windup exposes exact timing/range")
	s = _advance(s, 36)
	check(s.enemy.phase == "active" and s.player.hp == 100, "enemy telegraphs before active")
	var hit = _step(s)
	check(hit.state.player.hp == 88 and _has(hit.events, "hit"), "enemy attack deals damage once")
	s = _advance(hit.state, 5)
	check(s.player.hp == 88 and s.enemy.phase == "recovery", "same enemy attack deduplicates overlapping ticks")
	var counter = _step(_incoming(_new()), {"defend_pressed": true})
	check(counter.state.player.hp == 100 and _has(counter.events, "counter") and counter.state.player.phase == "counter", "fresh guard within precise window counters")
	s = _advance(counter.state, 2)
	check(s.enemy.hp == 40 and s.player.attack_kind == "counter", "counter emits a single original-weapon strike")
	s = _advance(s, 5)
	check(s.enemy.hp == 40, "counter cannot recursively proc itself")
	s = _step(_new(), {"defend_pressed": true, "line_of_sight": false}).state
	s = _advance(s, 10, {"defend_pressed": true, "line_of_sight": false})
	check(s.player.guard_age_ticks == 11, "repeated press/hold does not reset precision window")
	var blocked = _step(_incoming(s), {"defend_pressed": true})
	check(blocked.state.player.hp == 95 and _has(blocked.events, "blocked") and not _has(blocked.events, "counter"), "late held guard still reduces damage")
	var backstab = _step(_incoming(_new()), {"defend_pressed": true, "player_facing": [0.0, 1.0]})
	check(backstab.state.player.hp == 88 and not _has(backstab.events, "blocked"), "guard only covers configured front arc")
	var canceled = _step(_new(), {"defend_pressed": true, "defend_released": true})
	check(not canceled.state.player.defend_held and canceled.state.player.phase == "idle", "same-tick defense release wins")

func _test_guard_rearm() -> void:
	var s = _step(_new(), {"defend_pressed": true, "line_of_sight": false}).state
	check(s.player.guard_rearm_ticks == Combat.GUARD_REARM_TICKS and not s.player.guard_window_spent, "initial guard gets one precise window and bounded rearm interval")
	for index in 12:
		var changes = {"line_of_sight": false}
		changes["defend_released" if index % 2 == 0 else "defend_pressed"] = true
		s = _step(s, changes).state
		if index % 2 == 1:
			check(s.player.phase == "guard" and s.player.defend_held and s.player.guard_window_spent and s.player.guard_rearm_ticks == Combat.GUARD_REARM_TICKS, "rapid alternating edges keep ordinary guard without rearming precision")
	var blocked = _step(_incoming(s))
	check(blocked.state.player.hp == 95 and _has(blocked.events, "blocked") and not _has(blocked.events, "counter"), "rapid re-press cannot convert every incoming hit to counter")
	s = _step(blocked.state, {"defend_released": true, "line_of_sight": false}).state
	s = _advance(s, Combat.GUARD_REARM_TICKS, {"line_of_sight": false})
	check(s.player.guard_rearm_ticks == 0 and not s.player.defend_held, "quiet released interval rearms without automatically raising guard")
	var counter = _step(_incoming(s), {"defend_pressed": true})
	check(counter.state.player.hp == 95 and _has(counter.events, "counter") and counter.state.player.guard_rearm_ticks == Combat.GUARD_REARM_TICKS, "release wait and fresh press permit a new precise counter")
	s = _advance(counter.state, 25, {"line_of_sight": false})
	check(s.player.phase == "guard" and s.player.guard_window_spent and s.player.guard_rearm_ticks == 0, "successful counter returns to held ordinary guard without a new window")
	var held = _step(_incoming(s), {"defend_pressed": true})
	check(_has(held.events, "blocked") and not _has(held.events, "counter"), "long-held repeated press cannot rearm after counter recovery")
	s = _step(_new(), {"defend_pressed": true, "line_of_sight": false}).state
	var paused = _step(s, {"paused": true})
	check(paused.state.player.guard_rearm_ticks == s.player.guard_rearm_ticks, "pause does not erase or advance rearm cooldown")
	var resumed = _step(_incoming(paused.state), {"defend_pressed": true})
	check(_has(resumed.events, "blocked") and not _has(resumed.events, "counter") and resumed.state.player.guard_window_spent, "pause resume and rapid guard cannot bypass precision cooldown")
	var invalid = resumed.state.duplicate(true)
	invalid.player.guard_rearm_ticks = Combat.GUARD_REARM_TICKS + 1
	check(not Combat.valid(invalid), "rearm cooldown remains bounded")

func _test_dodge() -> void:
	var dodged = _step(_incoming(_new()), {"dodge_pressed": true})
	check(dodged.state.player.hp == 100 and _has(dodged.events, "dodged") and _has(dodged.events, "dodge_started"), "dodge avoids one active hit")
	check(dodged.state.player.invulnerable_ticks == 8 and dodged.state.player.dodge_cooldown == 48, "finite dodge protection and cooldown")
	var next = _step(dodged.state, {"dodge_pressed": true})
	check(next.state.player.invulnerable_ticks == 7 and next.state.player.dodge_cooldown == 47 and not _has(next.events, "dodge_started"), "spam cannot extend dodge")
	var s = _advance(next.state, 10)
	check(s.player.phase == "idle" and s.player.invulnerable_ticks == 0, "dodge ends independently of visual hitstop")
	var cooling = _step(s, {"dodge_pressed": true})
	check(not _has(cooling.events, "dodge_started"), "dodge cooldown enforced")

func _test_cleanup() -> void:
	for field in ["paused", "focused", "exit"]:
		var s = _step(_new(), {"attack_pressed": true}).state
		var frame_change = {field: false if field == "focused" else true}
		var result = _step(s, frame_change)
		check(not result.state.player.attack_held and not result.state.player.defend_held and result.state.player.charge_ticks == 0 and result.state.player.invulnerable_ticks == 0, "interruption clears held actions " + field)
		check(result.state.sim_tick == s.sim_tick, "interrupted frame never advances gameplay " + field)
		if field == "exit":
			check(result.state.status == "ended" and result.state.end_reason == "exited", "exit is terminal")
		else:
			check(result.state.status == "paused" and result.state.enemy.phase == "idle", "pause cancels enemy active windup")
			var resumed = _step(result.state, {"attack_released": true})
			check(resumed.state.status == "active" and resumed.state.player.phase == "idle" and resumed.state.enemy.hp == 60, "resume/release cannot finish stale attack " + field)
	var guard = _step(_new(), {"defend_pressed": true}).state
	var paused = _step(guard, {"paused": true})
	check(not paused.state.player.defend_held and paused.state.player.guard_window_spent, "pause clears defense window")

func _test_replay_and_validation() -> void:
	var s = _new()
	var before = s.duplicate(true)
	var frame = _frame(s, {"attack_pressed": true})
	var frame_before = frame.duplicate(true)
	var result = Combat.step(s, frame)
	check(s == before and frame == frame_before, "step input isolation")
	var committed = result.state.duplicate(true)
	var replay = Combat.step(committed, frame)
	check(replay.ok and replay.replay and replay.events.is_empty() and replay.state == committed, "same frame retry is side-effect free")
	replay.state.player.hp = 1
	replay.state.stats.normal.reach_m = 99
	check(result.state == committed and base_stats.normal.reach_m == 1.25, "nested output and stats isolated")
	var changed = frame.duplicate(true)
	changed.attack_pressed = false
	check(Combat.step(committed, changed).error == "tick_conflict", "same tick changed payload rejected")
	changed = _frame(committed)
	changed.run_id = "old-run"
	check(Combat.step(committed, changed).error == "stale_run", "old run rejected")
	changed = _frame(committed)
	changed.tick += 1
	check(Combat.step(committed, changed).error == "stale_tick", "skipped tick rejected")
	for mutation in ["nan", "teleport", "missing", "zero_facing", "script"]:
		changed = _frame(committed)
		match mutation:
			"nan": changed.player_position = [NAN, 0.0]
			"teleport": changed.player_position = [10.0, 0.0]
			"missing": changed.erase("line_of_sight")
			"zero_facing": changed.player_facing = [0.0, 0.0]
			"script": changed["script"] = "anything"
		check(not Combat.step(committed, changed).ok, "invalid sample rejected " + mutation)
	var invalid = committed.duplicate(true)
	invalid.player.invulnerable_ticks = 999
	check(not Combat.valid(invalid), "unbounded immunity rejected")

func _test_limits_and_styles() -> void:
	var capped = _new()
	capped.stats.normal.attack_rate_hz = 2.7
	capped.stats.defense.counter_haste_multiplier = 1.3
	capped.player.haste_ticks = 60
	var capped_attack = _step(capped, {"attack_pressed": true, "attack_released": true})
	check(capped_attack.state.player.phase_duration >= ceili(60.0 / 2.7), "temporary counter haste also obeys final attack rate cap")
	var invalid_stats = base_stats.duplicate(true)
	invalid_stats.effects.max_live_particles = NAN
	check(not Combat.fresh("invalid", invalid_stats).ok, "all numeric stats reject nonfinite values")
	for id in ["snap_focus", "counter_edge", "far_charge", "chain_flow"]:
		var pool = {id: cards[id]}
		var run = Tower.fresh("style", 1, 7, pool, 3).state
		run = Tower.reduce(run, Tower.make_command(run, "clear", "clear_stage", {"stage": 1}, "application"), pool).state
		run = Tower.reduce(run, Tower.make_command(run, "pick", "choose", {"stage": 2, "card_id": id}), pool).state
		var configured = Tower.stats(run, pool).stats
		var created = Combat.fresh("style", configured)
		if id in ["far_charge", "chain_flow"]:
			check(not created.ok and created.error == "unsupported_charge_mode", "unimplemented attack shape never silently falls back " + id)
		else:
			check(created.ok, "supported style initializes " + id)
			if id == "snap_focus":
				var s = _step(created.state, {"attack_pressed": true}).state
				s = _advance(s, 6)
				check(s.player.phase == "charge", "near-instant charge still waits seven fixed ticks")
			if id == "counter_edge":
				var s = _step(_incoming(created.state), {"defend_pressed": true}).state
				check(s.player.haste_ticks == 60, "counter card enables bounded temporary haste")
	var s = _new()
	s.tick = Combat.MAX_TICKS - 1
	s.sim_tick = Combat.MAX_TICKS - 1
	s.enemy.position = [0.0, -1.0]
	var last = _step(s, {"line_of_sight": false})
	check(last.state.status == "ended" and last.state.end_reason == "time_limit", "bounded encounter lifetime")
	# Inject several logically distinct hits inside one second; visual pause budget never grows unbounded.
	s = _new()
	for _i in 3:
		s = _incoming(s)
		s.player.phase = "guard"
		s.player.defend_held = true
		s.player.guard_age_ticks = 20
		s = _step(s).state
		var used = 0
		for entry in s.hitstop_log: used += entry.amount
		check(used <= 7 and s.hitstop_ticks <= 4, "sliding one-second hitstop budget")
