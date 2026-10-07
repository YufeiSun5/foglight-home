extends SceneTree
const Combat = preload("res://src/domain/combat_rules.gd")
const Tower = preload("res://src/domain/tower_run_rules.gd")
var checks = 0
var failures: Array = []
var base_stats: Dictionary
var cards: Dictionary
var ranged_stats: Dictionary

func _initialize() -> void:
	var parsed = Tower.validate_catalog(JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json")))
	check(parsed.ok, "tower catalog loads")
	if not parsed.ok:
		quit(1)
		return
	cards = parsed.cards
	base_stats = Tower.stats(Tower.fresh("stats", 1, 1, cards).state, cards).stats
	var far_pool = {"far_charge": cards.far_charge}
	var far_run = Tower.fresh("ranged-stats", 1, 7, far_pool, 3).state
	far_run = Tower.reduce(far_run, Tower.make_command(far_run, "clear", "clear_stage", {"stage": 1}, "application"), far_pool).state
	far_run = Tower.reduce(far_run, Tower.make_command(far_run, "pick", "choose", {"stage": 2, "card_id": "far_charge"}), far_pool).state
	ranged_stats = Tower.stats(far_run, far_pool).stats
	_test_basic_attacks()
	_test_coalesced_edges()
	_test_input_priority_matrix()
	_test_enemy_and_counter()
	_test_guard_rearm()
	_test_recovery_defense_hold()
	_test_recovery_defense_window()
	_test_recovery_defense_cancellation()
	_test_dodge()
	_test_cleanup()
	_test_replay_and_validation()
	_test_limits_and_styles()
	_test_ranged_activation()
	_test_ranged_recovery_defense()
	_test_ranged_flight_and_walls()
	_test_ranged_target_motion_and_ledger()
	_test_ranged_expiry_and_cleanup()
	_test_ranged_replay_and_validation()
	_test_ranged_repeatability_and_budgets()
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
	if not s.projectiles.is_empty():
		f["projectile_collisions"] = []
		for projectile in s.projectiles:
			f.projectile_collisions.append({"attack_id": projectile.attack_id, "wall_fraction": null})
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
	var outside = _step(distant, {"enemy_position": [0.0, -1.7]})
	check(outside.state.enemy.phase=="idle" and not _has(outside.events,"enemy_telegraph"),"enemy continues approach instead of repeatedly swinging outside hit reach")
	var approach = _step(outside.state, {"enemy_position": [0.0, -1.4]})
	check(approach.state.enemy.phase=="idle","enemy closes within base answering distance before windup")
	var nearby = _step(approach.state, {"enemy_position": [0.0, -1.19]})
	check(nearby.state.enemy.phase == "telegraph" and _has(nearby.events, "enemy_telegraph"), "enemy starts windup at an actual close engagement distance")
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

func _recovery_fixture(kind: String) -> Dictionary:
	if kind == "normal":
		return _step(_new(), {"attack_pressed": true, "attack_released": true, "line_of_sight": false}).state
	if kind == "counter":
		var counter = _step(_incoming(_new()), {"defend_pressed": true}).state
		# Test a new held intent, independently of the original successful guard.
		return _step(counter, {"defend_released": true, "line_of_sight": false}).state
	var charged = _step(_new(), {"attack_pressed": true, "line_of_sight": false}).state
	charged = _advance(charged, 53, {"line_of_sight": false})
	return _step(charged, {"attack_released": true, "line_of_sight": false}).state

func _test_recovery_defense_hold() -> void:
	for kind in ["normal", "charge", "counter"]:
		var recovery = _recovery_fixture(kind)
		var before = recovery.duplicate(true)
		var pressed = _step(recovery, {"defend_pressed": true, "line_of_sight": false})
		check(recovery == before and pressed.state.player.defend_held and pressed.state.player.guard_age_ticks == 1, "defense held during recovery is retained from its original press " + kind)
		check(pressed.state.player.phase == recovery.player.phase and pressed.state.player.phase_tick == recovery.player.phase_tick + 1 and pressed.state.player.phase_duration == recovery.player.phase_duration, "held defense never starts guard early or shortens recovery " + kind)
		var near_end = pressed.state
		# Repeated input edges and simultaneous unavailable dodge do not refresh the
		# held defense clock or skip the already released attack's protected recovery.
		while near_end.player.phase_tick < near_end.player.phase_duration - 1:
			var next = _step(near_end, {"defend_pressed": true, "dodge_pressed": true, "attack_pressed": true, "attack_released": true, "line_of_sight": false})
			check(next.state.player.phase == recovery.player.phase and next.state.player.phase_tick == near_end.player.phase_tick + 1 and next.state.player.guard_age_ticks == near_end.player.guard_age_ticks + 1, "every recovery tick stays protected while original defense clock ages " + kind)
			check(next.state.player.attack_id == recovery.player.attack_id and not _has(next.events, "attack_started") and not _has(next.events, "dodge_started"), "held defense and repeated competing input do not spawn another action " + kind)
			near_end = next.state
		var ended = _step(near_end, {"defend_pressed": true, "line_of_sight": false})
		check(ended.state.player.phase == "guard" and ended.state.player.defend_held and ended.state.player.guard_age_ticks == near_end.player.guard_age_ticks + 1, "recovery ends in held guard without resetting the original clock " + kind)
		var blocked = _step(_incoming(ended.state), {"defend_pressed": true})
		check(blocked.state.player.hp == 95 and _has(blocked.events, "blocked") and not _has(blocked.events, "counter"), "expired buffered window grants ordinary block without another precise window " + kind)
		# An actual incoming hit before the end is never blocked by pending intent.
		var hurt = _step(_incoming(pressed.state))
		check(hurt.state.player.hp == 88 and hurt.state.player.phase == "hurt" and not _has(hurt.events, "blocked") and not _has(hurt.events, "counter"), "pending guard cannot block an attack during recovery " + kind)
		check(not hurt.state.player.defend_held and hurt.state.player.guard_age_ticks == 0 and hurt.state.player.guard_window_spent, "being hit clears the pending held defense " + kind)
		var after_hurt = _advance(hurt.state, 9, {"line_of_sight": false})
		check(after_hurt.player.phase == "idle" and not after_hurt.player.defend_held, "hurt does not revive a canceled defense " + kind)

func _test_recovery_defense_window() -> void:
	var window = ceili(base_stats.defense.counter_window_seconds * Combat.TICK_RATE)
	for kind in ["normal", "charge", "counter"]:
		var recovery = _recovery_fixture(kind)
		var last_tick = _advance(recovery, recovery.player.phase_duration - recovery.player.phase_tick - 1, {"line_of_sight": false})
		var pressed_last = _step(last_tick, {"defend_pressed": true, "line_of_sight": false})
		check(pressed_last.state.player.phase == "guard" and pressed_last.state.player.guard_age_ticks == 1 and pressed_last.state.player.defend_held, "press on the final recovery tick carries through immediately " + kind)
		var counter = _step(_incoming(pressed_last.state))
		check(_has(counter.events, "counter") and counter.state.player.guard_age_ticks == 2, "late recovery press keeps only the remaining original precise window " + kind)
		for elapsed_at_end in [window, window + 1]:
			var before_press = _advance(recovery, recovery.player.phase_duration - recovery.player.phase_tick - elapsed_at_end, {"line_of_sight": false})
			var held = _step(before_press, {"defend_pressed": true, "line_of_sight": false}).state
			held = _advance(held, elapsed_at_end - 2, {"defend_pressed": true, "line_of_sight": false})
			check(held.player.phase == recovery.player.phase and held.player.phase_tick == held.player.phase_duration - 1, "precision boundary fixture is still in protected recovery " + kind)
			var contact = _step(_incoming(held), {"defend_pressed": true})
			check(contact.state.player.guard_age_ticks == elapsed_at_end, "precision age includes all waiting recovery ticks " + kind)
			check(_has(contact.events, "counter") == (elapsed_at_end == window) and _has(contact.events, "blocked") == (elapsed_at_end > window), "recovery completion obeys exact original-window boundary " + kind + " age=" + str(elapsed_at_end))
		# Release and rapid re-press during recovery never grant a free second window.
		var almost_done = _advance(recovery, recovery.player.phase_duration - recovery.player.phase_tick - 4, {"line_of_sight": false})
		almost_done = _step(almost_done, {"defend_pressed": true, "line_of_sight": false}).state
		almost_done = _step(almost_done, {"defend_released": true, "line_of_sight": false}).state
		almost_done = _step(almost_done, {"defend_pressed": true, "line_of_sight": false}).state
		var rapid = _step(_incoming(almost_done))
		check(rapid.state.player.guard_window_spent and _has(rapid.events, "blocked") and not _has(rapid.events, "counter"), "recovery release and rapid re-press preserve precision rearm protection " + kind)

func _test_recovery_defense_cancellation() -> void:
	for kind in ["normal", "charge", "counter"]:
		var recovery = _recovery_fixture(kind)
		var held = _step(recovery, {"defend_pressed": true, "line_of_sight": false}).state
		for coalesced in [false, true]:
			var released = _step(held, {"defend_pressed": coalesced, "defend_released": true, "line_of_sight": false}).state
			check(not released.player.defend_held and released.player.guard_age_ticks == 0 and released.player.guard_window_spent, "release wins over pending recovery defense including coalesced edges " + kind)
			released = _advance(released, released.player.phase_duration - released.player.phase_tick, {"line_of_sight": false})
			check(released.player.phase == "idle" and not released.player.defend_held, "released recovery defense does not reappear at completion " + kind)
			var last_tick = _advance(held, held.player.phase_duration - held.player.phase_tick - 1, {"line_of_sight": false})
			var last_release = _step(last_tick, {"defend_pressed": coalesced, "defend_released": true, "line_of_sight": false})
			check(last_release.state.player.phase == "idle" and not last_release.state.player.defend_held and last_release.state.player.guard_age_ticks == 0, "release wins on the exact final recovery tick " + kind)
		var tapped = _step(recovery, {"defend_pressed": true, "defend_released": true, "line_of_sight": false}).state
		tapped = _advance(tapped, tapped.player.phase_duration - tapped.player.phase_tick, {"line_of_sight": false})
		check(tapped.player.phase == "idle" and not tapped.player.defend_held, "fresh coalesced defense tap during recovery is never buffered " + kind)
		for field in ["paused", "focused", "exit"]:
			var edges = {"defend_pressed": true, "line_of_sight": false}
			edges[field] = false if field == "focused" else true
			var canceled = _step(held, edges)
			check(not canceled.state.player.defend_held and canceled.state.player.guard_age_ticks == 0 and canceled.state.player.guard_window_spent and canceled.state.sim_tick == held.sim_tick, "interruption discards buffered recovery defense before any gameplay tick " + kind + " " + field)
			if field == "exit":
				check(canceled.state.status == "ended" and Combat.step(canceled.state, _frame(canceled.state)).error == "encounter_ended", "exited recovery cannot consume held defense later " + kind)
			else:
				var resumed = _step(canceled.state, {"line_of_sight": false})
				check(resumed.state.player.phase == "idle" and not resumed.state.player.defend_held and resumed.state.player.attack_id == recovery.player.attack_id, "resume never resurrects buffered defense or old attack " + kind + " " + field)
	# Keep this change bounded to released attacks: dodge cancels prior held inputs,
	# and damage clears them. A new press during either lockout is still discarded.
	var dodge = _step(_new(), {"dodge_pressed": true, "line_of_sight": false}).state
	var hurt = _step(_incoming(_new())).state
	for locked in [dodge, hurt]:
		var attempted = _step(locked, {"defend_pressed": true, "line_of_sight": false}).state
		check(not attempted.player.defend_held and attempted.player.phase == locked.player.phase, "dodge and hurt do not gain new buffering semantics " + locked.player.phase)
		attempted = _advance(attempted, attempted.player.phase_duration - attempted.player.phase_tick, {"line_of_sight": false})
		check(attempted.player.phase == "idle" and not attempted.player.defend_held, "dodge and hurt end without reviving ignored guard " + locked.player.phase)

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
		if id == "chain_flow":
			check(created.ok and created.state.stats.charge.mode == "chain_charge", "implemented chain shape accepted " + id)
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

func _ranged_new() -> Dictionary:
	var created = Combat.fresh("ranged-test", ranged_stats)
	check(created.ok and Combat.valid(created.state) and created.state.projectiles.is_empty(), "ranged card creates a valid empty encounter")
	return created.state

func _ranged_prepared(enemy: Array = [0.0, -3.0]) -> Dictionary:
	var s = _step(_ranged_new(), {"attack_pressed": true, "enemy_position": enemy, "line_of_sight": false}).state
	return _advance(s, ceili(ranged_stats.charge.hold_seconds * 60.0) - 1, {"enemy_position": enemy, "line_of_sight": false})

func _ranged_born(enemy: Array = [0.0, -3.0]) -> Dictionary:
	var s = _step(_ranged_prepared(enemy), {"attack_released": true, "enemy_position": enemy, "line_of_sight": false}).state
	s = _advance(s, 3, {"enemy_position": enemy, "line_of_sight": false})
	check(s.projectiles.size() == 1 and s.projectiles[0].age_ticks == 0 and s.enemy.hp == 60, "one newborn bolt has no unqueried birth movement or hit")
	return s

func _ranged_changes(s: Dictionary, wall: Variant = null) -> Dictionary:
	var samples: Array = []
	for projectile in s.projectiles: samples.append({"attack_id": projectile.attack_id, "wall_fraction": wall})
	return {"enemy_position": s.enemy.position.duplicate(), "line_of_sight": false, "projectile_collisions": samples}

func _test_ranged_activation() -> void:
	var fresh = _ranged_new()
	check(Combat.projectile_sweeps(fresh).is_empty(), "no sweep without a launched bolt")
	var tap = _step(fresh, {"attack_pressed": true, "attack_released": true})
	var s = _advance(tap.state, 2)
	check(s.player.attack_kind == "normal" and s.enemy.hp == 50 and s.projectiles.is_empty(), "ranged card preserves ordinary tap as one melee hit")
	s = _step(_ranged_new(), {"attack_pressed": true}).state
	s = _advance(s, 5)
	s = _step(s, {"attack_released": true}).state
	s = _advance(s, 2)
	check(s.player.attack_kind == "normal" and s.enemy.hp == 50 and s.projectiles.is_empty(), "short hold still cannot fire a bolt")
	var prepared = _ranged_prepared()
	check(prepared.player.phase == "charge" and prepared.projectiles.is_empty() and prepared.enemy.hp == 60, "full preparation never auto-fires")
	var release = _step(prepared, {"attack_released": true, "enemy_position": [0.0, -3.0], "line_of_sight": false})
	check(release.state.player.phase_duration == 33 and release.state.projectiles.is_empty() and not _has(release.events, "hit"), "release keeps bounded recovery and waits for active tick")
	s = _step(release.state, {"player_position": [0.1, 0.0], "player_facing": [1.0, 0.0], "enemy_position": [0.0, -3.0], "line_of_sight": false}).state
	s = _step(s, {"player_position": [0.2, 0.0], "player_facing": [1.0, 0.0], "enemy_position": [0.0, -3.0], "line_of_sight": false}).state
	check(s.projectiles.is_empty(), "no early bolt before active tick four")
	var born = _step(s, {"player_position": [0.3, 0.0], "player_facing": [1.0, 0.0], "enemy_position": [0.0, -3.0], "line_of_sight": false})
	check(_has(born.events, "projectile_spawned") and not _has(born.events, "hit") and born.state.projectiles.size() == 1, "birth publishes projectile rather than a distant melee hit")
	var bolt: Dictionary = born.state.projectiles[0]
	check(bolt.origin == [0.3, 0.0] and bolt.position == bolt.origin and bolt.direction == [0.0, -1.0], "active origin follows release motion but aim stays locked to release")
	var next = _step(born.state, {"player_position": [0.5, 0.0], "player_facing": [0.0, 1.0], "enemy_position": [0.0, -3.0], "line_of_sight": false})
	check(is_equal_approx(next.state.projectiles[0].position[0], 0.3) and is_equal_approx(next.state.projectiles[0].position[1], -10.0 / 60.0), "turning and moving cannot steer an existing bolt")
	for defensive in ["defend_pressed", "dodge_pressed"]:
		var changes = {"attack_released": true, "enemy_position": [0.0, -3.0], "line_of_sight": false, defensive: true}
		var stopped = _step(prepared, changes)
		s = _advance(stopped.state, 12, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
		check(s.projectiles.is_empty() and s.player.attack_id == 0 and s.enemy.hp == 60, "same-frame release yields to defense with no delayed bolt " + defensive)
	var counter = _step(_incoming(_ranged_new()), {"defend_pressed": true})
	s = _advance(counter.state, 2)
	check(s.enemy.hp == 40 and s.projectiles.is_empty() and s.player.attack_kind == "counter", "ranged conversion leaves precise counter as original melee strike")
	s = _ranged_born([0.0, -1.0])
	check(s.enemy.hp == 60, "nearby target cannot receive a fallback melee charge")
	s = _advance(s, 3, {"enemy_position": [0.0, -1.0], "line_of_sight": false})
	check(s.enemy.hp == 60, "charge waits for actual projectile travel even within melee range")
	var hit = _step(s, {"enemy_position": [0.0, -1.0], "line_of_sight": false})
	check(hit.state.enemy.hp == 36 and _has(hit.events, "hit"), "near target takes only projectile damage when swept contact arrives")

func _test_ranged_recovery_defense() -> void:
	var release = _step(_ranged_prepared(), {"attack_released": true, "enemy_position": [0.0, -3.0], "line_of_sight": false}).state
	var baseline = release.duplicate(true)
	var held = release.duplicate(true)
	var spawned = 0
	for index in release.player.phase_duration - release.player.phase_tick:
		var next = _step(baseline, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
		var guarded = _step(held, {"defend_pressed": true, "enemy_position": [0.0, -3.0], "line_of_sight": false})
		check(guarded.events == next.events and guarded.state.projectiles == next.state.projectiles and guarded.state.enemy == next.state.enemy, "pending defense does not delay duplicate or clear the original ranged release and flight")
		if _has(guarded.events, "projectile_spawned"): spawned += 1
		baseline = next.state
		held = guarded.state
		if baseline.player.phase == "release":
			check(held.player.phase == "release" and held.player.phase_tick == baseline.player.phase_tick and held.player.phase_duration == baseline.player.phase_duration, "ranged guard intent keeps every protected recovery tick")
	check(spawned == 1 and held.enemy.hp == 36 and held.player.attack_id == release.player.attack_id, "ranged recovery buffering retains one finite projectile and one target hit")
	check(held.player.phase == "guard" and held.player.defend_held and held.player.guard_age_ticks == release.player.phase_duration - release.player.phase_tick and baseline.player.phase == "idle", "ranged recovery ends in held guard with the original elapsed defense age")

func _test_ranged_flight_and_walls() -> void:
	var born = _ranged_born()
	var queries = Combat.projectile_sweeps(born)
	check(queries.size() == 1 and queries[0].attack_id == born.projectiles[0].attack_id and queries[0].from == [0.0, 0.0] and is_equal_approx(queries[0].to[1], -1.0 / 6.0) and queries[0].radius_m == 0.10, "physics boundary exposes exact next finite-speed segment and radius")
	queries[0].from[0] = 99.0
	queries[0].to[0] = 99.0
	check(born.projectiles[0].position == [0.0, 0.0], "read-only sweep query never leaks mutable state")
	for wall_fraction in [0.0, 0.06, 0.5, 1.0]:
		var wall_hit = _step(born, _ranged_changes(born, wall_fraction))
		check(wall_hit.state.projectiles.is_empty() and wall_hit.state.enemy.hp == 60 and _has(wall_hit.events, "projectile_ended") and not _has(wall_hit.events, "hit"), "first segment cannot skip thin obstruction fraction " + str(wall_fraction))
		var removed = wall_hit.events.filter(func(event): return event.kind == "projectile_ended")
		check(removed[0].reason == "wall" and is_equal_approx(removed[0].position[1], -wall_fraction / 6.0), "wall contact position is on first swept segment")
	var s = _advance(born, 15, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
	check(is_equal_approx(s.projectiles[0].position[1], -2.5) and s.enemy.hp == 60, "distant target is not instantly damaged")
	# Target contact is 0.6 of this segment. Earlier wall and tie beat enemy contact.
	for wall_fraction in [0.1, 0.6]:
		var blocked = _step(s, _ranged_changes(s, wall_fraction))
		check(blocked.state.enemy.hp == 60 and blocked.state.projectiles.is_empty() and not _has(blocked.events, "hit"), "wall precedes enemy or wins exact tie " + str(wall_fraction))
	var after_target = _step(s, _ranged_changes(s, 0.9))
	check(after_target.state.enemy.hp == 36 and after_target.state.projectiles.is_empty() and _has(after_target.events, "hit"), "enemy before a later wall takes one hit then bolt stops")
	var clear = _step(s, _ranged_changes(s))
	check(clear.state.enemy.hp == 36 and clear.state.projectiles.size() == 1 and clear.state.projectiles[0].hit_targets == ["enemy"], "clear path hits once and records stable target identity")
	check(clear.state.hitstop_ticks <= 4 and clear.state.projectiles[0].hitstop_used_ticks <= 4, "projectile hitstop has finite per-attack allowance")
	var hit_replay = Combat.step(clear.state, _frame(s, _ranged_changes(s)))
	check(hit_replay.ok and hit_replay.replay and hit_replay.state.enemy.hp == 36 and hit_replay.events.is_empty(), "replaying actual projectile contact never applies damage twice")
	var source_events = clear.events.filter(func(event): return event.kind == "hit")
	check(source_events.size() == 1 and source_events[0].source == "player_projectile" and source_events[0].attack_kind == "charge", "projectile source is distinct and does not recursively trigger effects")

func _test_ranged_target_motion_and_ledger() -> void:
	var s = _ranged_born([0.405, -2.0])
	s = _advance(s, 11, {"enemy_position": [0.405, -2.0], "line_of_sight": false})
	var moving_hit = _step(s, {"enemy_position": [0.385, -1.67], "line_of_sight": false})
	# Both endpoint distances exceed 0.40; relative paths graze the target in between.
	check(moving_hit.state.enemy.hp == 36 and _has(moving_hit.events, "hit"), "relative-motion sweep catches target between samples without endpoint contact")
	var repeated = _step(moving_hit.state, {"enemy_position": [0.1, -1.7], "line_of_sight": false})
	check(repeated.state.enemy.hp == 36 and not _has(repeated.events, "hit") and repeated.state.projectiles[0].hit_targets == ["enemy"], "same projectile cannot hit already recorded target on another flight frame")
	var chased = _ranged_born([0.0, -3.0])
	chased = _advance(chased, 10, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
	for x in [0.3, 0.6, 0.9]:
		chased = _step(chased, {"enemy_position": [x, -3.0], "line_of_sight": false}).state
	chased = _advance(chased, 9, {"enemy_position": [0.9, -3.0], "line_of_sight": false})
	check(chased.enemy.hp == 60 and is_equal_approx(chased.projectiles[0].position[0], 0.0), "target moving aside is missed and never homed toward")
	var near_death = _ranged_born()
	near_death.enemy.hp = 24
	near_death = _advance(near_death, 15, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
	var killed = _step(near_death, _ranged_changes(near_death))
	check(killed.state.status == "ended" and killed.state.end_reason == "victory" and killed.state.enemy.hp == 0 and killed.state.projectiles.is_empty(), "lethal bolt ends encounter and clears all remaining flight")
	check(Combat.step(killed.state, _frame(killed.state, {"enemy_position": [0.0, -3.0]})).error == "encounter_ended", "dead target cannot receive later projectile damage")
	var lost = _ranged_born()
	lost.enemy.hp = 0
	lost.enemy.phase = "dead"
	var no_target = _step(lost, _ranged_changes(lost))
	check(no_target.state.projectiles.is_empty() and no_target.state.status == "ended" and not _has(no_target.events, "hit"), "target removed before next flight ends safely without ghost hit")

func _test_ranged_expiry_and_cleanup() -> void:
	var s = _ranged_born([0.0, -6.0])
	s = _advance(s, 32, {"enemy_position": [0.0, -6.0], "line_of_sight": false})
	check(s.projectiles.size() == 1 and s.projectiles[0].age_ticks == 32, "bolt exists for bounded configured flight lifetime")
	var expired = _step(s, _ranged_changes(s))
	check(expired.state.projectiles.is_empty() and expired.state.enemy.hp == 60 and _has(expired.events, "projectile_ended"), "bolt expires at 5.5m and 33 ticks without hitting beyond range")
	var removals = expired.events.filter(func(event): return event.kind == "projectile_ended")
	check(removals[0].reason == "range" and is_equal_approx(removals[0].position[1], -5.5), "range endpoint is exact with no full-step overshoot")
	# A partial last tick must clip both the bolt and the target's movement duration.
	var fractional_stats = ranged_stats.duplicate(true)
	fractional_stats.charge.projectile_reach_m = 5.55
	fractional_stats.charge.projectile_lifetime_seconds = 0.555
	var fractional = Combat.fresh("fractional", fractional_stats).state
	fractional.player.attack_id = 1
	fractional.tick = 34
	fractional.sim_tick = 34
	fractional.enemy.position = [0.5, -5.55]
	fractional.projectiles = [{"attack_id": 1, "source": "player_projectile", "origin": [0.0, 0.0], "position": [0.0, -5.5], "direction": [0.0, -1.0], "age_ticks": 33, "travelled_m": 5.5, "hit_targets": [], "hitstop_used_ticks": 0}]
	check(Combat.valid(fractional), "fractional lifetime fixture is valid")
	var query = Combat.projectile_sweeps(fractional)
	check(is_equal_approx(query[0].to[1], -5.55), "fractional lifetime clips physical wall query")
	var final_tick = _step(fractional, {"enemy_position": [0.2, -5.55], "line_of_sight": false})
	check(final_tick.state.enemy.hp == 60 and final_tick.state.projectiles.is_empty(), "enemy entering path after fractional lifetime cannot be hit")
	for interrupt in ["paused", "focused", "exit"]:
		var born = _ranged_born()
		var changes = _ranged_changes(born)
		changes.erase("projectile_collisions")
		changes[interrupt] = false if interrupt == "focused" else true
		var frame = _frame(born, changes)
		frame.erase("projectile_collisions")
		var canceled = Combat.step(born, frame)
		check(canceled.ok and canceled.state.projectiles.is_empty() and canceled.state.sim_tick == born.sim_tick and not _has(canceled.events, "hit"), "immediate interruption clears projectile without requiring stale physics sample " + interrupt)
		check(Combat.projectile_sweeps(canceled.state).is_empty(), "interrupted state has no future sweeps " + interrupt)
		if interrupt != "exit":
			var resumed = _step(canceled.state, {"enemy_position": [0.0, -3.0], "attack_released": true, "line_of_sight": false})
			s = _advance(resumed.state, 35, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
			check(s.projectiles.is_empty() and s.enemy.hp == 60 and s.player.phase == "idle", "resume cannot revive a canceled bolt " + interrupt)
	var last = _ranged_born()
	last.tick = Combat.MAX_TICKS - 1
	last.sim_tick = Combat.MAX_TICKS - 1
	var limit = _step(last, _ranged_changes(last))
	check(limit.state.status == "ended" and limit.state.end_reason == "time_limit" and limit.state.projectiles.is_empty(), "encounter limit clears projectiles")
	var fresh = _ranged_new()
	check(fresh.player.attack_id == 0 and fresh.projectiles.is_empty(), "new encounter never inherits previous bolt or target ledger")

func _test_ranged_replay_and_validation() -> void:
	var born = _ranged_born()
	var original = born.duplicate(true)
	var frame = _frame(born, _ranged_changes(born))
	var frame_before = frame.duplicate(true)
	var flight = Combat.step(born, frame)
	check(flight.ok and born == original and frame == frame_before, "projectile flight preserves state and physics sample inputs")
	var replay = Combat.step(flight.state, frame)
	check(replay.ok and replay.replay and replay.events.is_empty() and replay.state == flight.state, "same flight frame replays without moving or hitting again")
	replay.state.projectiles[0].position[0] = 90.0
	replay.state.projectiles[0].hit_targets.append("enemy")
	check(flight.state.projectiles[0].position[0] == 0.0 and flight.state.projectiles[0].hit_targets.is_empty(), "replay projectile and nested ledger are deep copies")
	var conflict = frame.duplicate(true)
	conflict.projectile_collisions[0].wall_fraction = 0.5
	check(Combat.step(flight.state, conflict).error == "tick_conflict", "changed collision sample on same frame conflicts")
	var malformed_samples = [null, {}, 1, [null], [{}], [{"attack_id": 1}],
		[{"attack_id": 1, "wall_fraction": NAN}], [{"attack_id": 1, "wall_fraction": INF}],
		[{"attack_id": 1, "wall_fraction": -0.01}], [{"attack_id": 1, "wall_fraction": 1.01}],
		[{"attack_id": 1, "wall_fraction": true}], [{"attack_id": 1, "wall_fraction": "0"}],
		[{"attack_id": true, "wall_fraction": null}], [{"attack_id": 1.0, "wall_fraction": null}],
		[{"attack_id": 1, "wall_fraction": null, "unknown": 0}],
		[{"attack_id": 1, "wall_fraction": null}, {"attack_id": 1, "wall_fraction": null}],
		[{"attack_id": 2, "wall_fraction": null}], []]
	for samples in malformed_samples:
		var invalid = _frame(born, _ranged_changes(born))
		invalid.projectile_collisions = samples
		check(not Combat.step(born, invalid).ok and born == original, "malformed unknown duplicate or missing projectile sample rejected " + str(samples))
	var missing = _frame(born, _ranged_changes(born))
	missing.erase("projectile_collisions")
	check(Combat.step(born, missing).error == "invalid_projectile_samples", "an existing bolt cannot travel on implicit clear-wall data")
	var no_bolt = _frame(_ranged_new())
	no_bolt.projectile_collisions = [{"attack_id": 1, "wall_fraction": null}]
	check(not Combat.step(_ranged_new(), no_bolt).ok, "unknown projectile sample rejected without live bolt")
	var paused_unknown = _frame(born, {"paused": true})
	paused_unknown.projectile_collisions[0].attack_id = 99
	check(not Combat.step(born, paused_unknown).ok, "pause also rejects unknown supplied sample identity")
	for field in ["attack_id", "source", "origin", "position", "direction", "age_ticks", "travelled_m", "hit_targets", "hitstop_used_ticks"]:
		var invalid = born.duplicate(true)
		invalid.projectiles[0].erase(field)
		check(not Combat.valid(invalid), "missing projectile state field rejected " + field)
	for change in [{"attack_id": 0}, {"source": "counter"}, {"position": [NAN, 0.0]}, {"direction": [0.0, 1.1]},
		{"age_ticks": 99}, {"travelled_m": 0.5}, {"hit_targets": ["enemy", "enemy"]}, {"hit_targets": ["unknown"]}, {"hitstop_used_ticks": 5}]:
		var invalid = born.duplicate(true)
		invalid.projectiles[0].merge(change, true)
		check(not Combat.valid(invalid), "bounded projectile state mutation rejected " + str(change))
	for malformed in [null, {}, "bolt", [null], [1]]:
		var invalid = born.duplicate(true)
		invalid.projectiles = malformed
		check(not Combat.valid(invalid), "malformed projectile collection rejected " + str(malformed))
	var extra = born.duplicate(true)
	extra.projectiles[0]["unknown"] = true
	check(not Combat.valid(extra), "unknown projectile state field rejected")
	var duplicate = born.duplicate(true)
	duplicate.projectiles.append(duplicate.projectiles[0].duplicate(true))
	check(not Combat.valid(duplicate), "duplicate projectile attack identity rejected")
	for change in [{"projectile_reach_m": 600.0}, {"projectile_speed_mps": 0.0}, {"projectile_speed_mps": INF},
		{"projectile_count": 2}, {"projectile_pierce": 99}, {"projectile_max_targets": 99}, {"projectile_lifetime_seconds": 10.0},
		{"projectile_lifetime_seconds": 0.56}, {"unknown_projectile_option": 1}, {"chain_max_targets": 3}]:
		var stats = ranged_stats.duplicate(true)
		stats.charge.merge(change, true)
		check(not Combat.fresh("bad-projectile-stats", stats).ok, "nonfinite unbounded or inconsistent projectile config rejected " + str(change))
	# Same sampled frame sequence produces byte-identical pure state/events.
	var a = born.duplicate(true)
	var b = born.duplicate(true)
	for _index in 22:
		var next_frame = _frame(a, _ranged_changes(a))
		var one = Combat.step(a, next_frame)
		var two = Combat.step(b, next_frame.duplicate(true))
		check(one.ok and two.ok and one == two, "ranged replay is deterministic across complete flight trace")
		a = one.state
		b = two.state

func _test_ranged_repeatability_and_budgets() -> void:
	var s = _ranged_born()
	s = _advance(s, 33, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
	check(s.enemy.hp == 36 and s.projectiles.is_empty() and s.player.phase == "idle", "first reusable ranged attack finishes normally")
	for shot in [2, 3]:
		s = _step(s, {"attack_pressed": true, "enemy_position": [0.0, -3.0], "line_of_sight": false}).state
		s = _advance(s, 53, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
		s = _step(s, {"attack_released": true, "enemy_position": [0.0, -3.0], "line_of_sight": false}).state
		s = _advance(s, 3, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
		check(s.projectiles.size() == 1 and s.projectiles[0].attack_id == shot and s.projectiles[0].hit_targets.is_empty(), "new charge gets a separate instance and clean hit ledger without ammo")
		s = _advance(s, 16, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
		check(s.enemy.hp == (12 if shot == 2 else 0), "different ranged attack may hit the same target again")
		if shot == 2: s = _advance(s, 17, {"enemy_position": [0.0, -3.0], "line_of_sight": false})
	check(s.status == "ended" and s.end_reason == "victory" and s.projectiles.is_empty(), "repeated same-weapon charges can complete encounter")
	# Independent instances can share one tick, but hitstop and corpse hits stay bounded.
	var budget = _ranged_born([0.0, -0.5])
	budget.player.attack_id = 4
	for id in [2, 3, 4]:
		var extra = budget.projectiles[0].duplicate(true)
		extra.attack_id = id
		budget.projectiles.append(extra)
	check(Combat.valid(budget), "bounded multi-instance stress fixture is valid")
	var burst = _step(budget, _ranged_changes(budget))
	var hits = burst.events.filter(func(event): return event.kind == "hit")
	var hitstop_used = 0
	for entry in burst.state.hitstop_log: hitstop_used += int(entry.amount)
	check(hits.size() == 3 and burst.state.enemy.hp == 0 and burst.state.projectiles.is_empty(), "simultaneous distinct bolts stop damaging as soon as target dies")
	check(hitstop_used <= 7 and burst.state.hitstop_ticks <= 4 and burst.state.sim_tick == budget.sim_tick + 1, "simultaneous bolts cannot exceed per-second visual pause budget or freeze logic")
	check(not _has(burst.events, "counter") and not _has(burst.events, "attack_started") and not _has(burst.events, "projectile_spawned"), "projectile hits never recursively spawn counters attacks or new projectiles")
	var overflow = budget.duplicate(true)
	var fifth = overflow.projectiles[0].duplicate(true)
	fifth.attack_id = 5
	overflow.player.attack_id = 5
	overflow.projectiles.append(fifth)
	check(not Combat.valid(overflow), "total projectile count has a hard ceiling")
