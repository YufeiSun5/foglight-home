extends SceneTree
const Combat = preload("res://src/domain/combat_rules.gd")
const Tower = preload("res://src/domain/tower_run_rules.gd")
var checks = 0
var failures: Array = []
var stats: Dictionary
var ranged: Dictionary
var fast: Dictionary

func _initialize() -> void:
	var cards = Tower.validate_catalog(JSON.parse_string(FileAccess.get_file_as_string("res://data/tower_cards.json"))).cards
	stats = _stats(cards, ["chain_flow"])
	fast = _stats(cards, ["chain_flow", "snap_focus"])
	ranged = _stats(cards, ["far_charge"])
	_test_three_real_targets()
	_test_activation_and_search()
	_test_cancellation_and_defense()
	_test_motion_contract()
	_test_replay_and_validation()
	_test_real_pierce()
	_test_strike_boundaries()
	_test_multi_actor_authority()
	_test_pierce_order_and_walls()
	_test_repeatable_finishing_chain()
	print("CHAIN CHARGE RULES: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _stats(cards: Dictionary, ids: Array) -> Dictionary:
	var pool: Dictionary = {}
	for id in ids: pool[id] = cards[id]
	var s = Tower.fresh("chain-stats", 1, 12, pool, 5).state
	for id in ids:
		s = Tower.reduce(s, Tower.make_command(s, "clear-" + id, "clear_stage", {"stage": s.stage}, "application"), pool).state
		s = Tower.reduce(s, Tower.make_command(s, "pick-" + id, "choose", {"stage": s.stage, "card_id": id}), pool).state
	return Tower.stats(s, pool).stats

func _fresh(selected: Dictionary = {}, targets: Array = []) -> Dictionary:
	var result = Combat.fresh("chain-test", stats if selected.is_empty() else selected, targets)
	check(result.ok, "fresh accepted")
	var s: Dictionary = result.state
	s.player.position = [0.0, 0.0]
	s.enemy.position = [0.0, -2.5]
	# Keep enemies stationary without making them dead or turning off their LOS.
	s.enemy.phase_duration = 1000
	for enemy in s.additional_enemies: enemy.phase_duration = 1000
	return s

func _frame(s: Dictionary, changes: Dictionary = {}) -> Dictionary:
	var f = {"run_id": s.run_id, "tick": s.tick + 1, "player_position": s.player.position.duplicate(), "player_facing": [0.0, -1.0],
		"enemy_position": s.enemy.position.duplicate(), "line_of_sight": true, "attack_pressed": false, "attack_released": false,
		"defend_pressed": false, "defend_released": false, "dodge_pressed": false, "focused": true, "paused": false, "exit": false,
		"additional_enemies": []}
	for enemy in s.additional_enemies: f.additional_enemies.append({"id": enemy.id, "position": enemy.position.duplicate(), "line_of_sight": true, "present": enemy.present})
	for key in changes: f[key] = changes[key]
	var sweep = Combat.chain_sweep(s, f)
	if not sweep.is_empty():
		if not changes.has("player_position"): f.player_position = sweep.to.duplicate()
		if not changes.has("chain_collision"): f.chain_collision = {"attack_id": sweep.attack_id, "wall_fraction": null}
	if not s.projectiles.is_empty() and not changes.has("projectile_collisions"):
		f.projectile_collisions = []
		for bolt in s.projectiles: f.projectile_collisions.append({"attack_id": bolt.attack_id, "wall_fraction": null})
	return f

func _step(s: Dictionary, changes: Dictionary = {}) -> Dictionary:
	var result = Combat.step(s, _frame(s, changes))
	check(result.ok, "accepted tick%d %s" % [s.tick + 1, result.get("error", "")])
	return result

func _advance(s: Dictionary, ticks: int, changes: Dictionary = {}) -> Dictionary:
	for index in ticks:
		var result = _step(s, changes)
		if not result.ok: return s
		s = result.state
	return s

func _release(s: Dictionary) -> Dictionary:
	s = _step(s, {"attack_pressed": true}).state
	s = _advance(s, ceili(float(s.stats.charge.hold_seconds) * 60.0) - 1)
	return _step(s, {"attack_released": true}).state

func _chain(s: Dictionary) -> Dictionary:
	return _advance(_release(s), 3)

func _hits(events: Array, source: String) -> Array:
	var hits: Array = []
	for event in events:
		if event.kind == "hit" and event.source == source: hits.append(event)
	return hits

func _test_three_real_targets() -> void:
	var initial = _fresh({}, [{"id": "enemy_2", "position": [1.2, -3.2]}, {"id": "enemy_3", "position": [-1.2, -4.0]}])
	var original = initial.duplicate(true)
	var s = _chain(initial)
	check(initial == original, "release isolates all enemy snapshots")
	check(s.player.phase == "chain" and s.chain.visited == ["enemy"], "release explicitly locks nearest target")
	check(s.chain.elapsed_ticks == 0 and s.enemy.hp == 60, "birth tick neither moves nor damages")
	var attack_id: int = s.player.attack_id
	var hits: Array = []
	var moved = 0.0
	var hitstop = 0
	for index in 36:
		var before = Vector2(s.player.position[0], s.player.position[1])
		var outcome = _step(s)
		if not outcome.ok: return
		s = outcome.state
		moved += before.distance_to(Vector2(s.player.position[0], s.player.position[1]))
		for event in _hits(outcome.events, "player_chain"):
			hits.append(event.target)
			check(event.attack_id == attack_id and event.attack_kind == "charge", "all finite strikes belong to original charged action")
		for entry in s.hitstop_log: hitstop = maxi(hitstop, _hitstop_total(s.hitstop_log))
		check(s.player.invulnerable_ticks == 0, "chain never grants invulnerability")
	check(hits.size() == 3 and hits.has("enemy") and hits.has("enemy_2") and hits.has("enemy_3"), "one charge damages three actual distinct actors")
	check(s.enemy.hp == 36 and s.additional_enemies[0].hp == 36 and s.additional_enemies[1].hp == 36, "three HP authorities take24 once each")
	check(s.chain.is_empty() and s.player.phase == "release" and s.player.hit_done, "36 ticks ends in finite recovery")
	check(moved > 2.0 and moved <= 6.0001 and hitstop <= 4, "real movement and per-attack hitstop cap")
	s = _advance(s, 33)
	check(s.player.attack_id == attack_id and s.enemy.hp == 36 and s.player.phase == "idle", "chain and secondary damage never recursively generate attacks")

func _hitstop_total(log: Array) -> int:
	var result = 0
	for entry in log: result += entry.amount
	return result

func _test_activation_and_search() -> void:
	check(stats.charge.hold_seconds > fast.charge.hold_seconds, "snap_focus shortens charge while chain card works alone")
	for selected in [stats, fast]:
		var s = _chain(_fresh(selected))
		check(not s.chain.is_empty(), "single card and combined build both activate")
		s = _advance(s, 12)
		check(s.enemy.hp == 36 and s.chain.is_empty(), "one target is hit once then chain ends")
	var far = _fresh()
	far.enemy.position = [0.0, -3.0001]
	far = _chain(far)
	check(far.chain.is_empty() and far.player.phase == "release" and far.enemy.hp == 60, "no target outside3m safely recovers")
	var edge = _fresh()
	edge.enemy.position = [0.0, -3.0]
	edge = _chain(edge)
	check(not edge.chain.is_empty() and absf(Vector2(edge.chain.destination[0], edge.chain.destination[1]).length() - 2.0) < .00001, "search includes3m and clips dash to2m")
	edge = _advance(edge, 12)
	check(edge.enemy.hp == 36, "clipped2m motion still requires actual melee reach")
	var tie = _fresh({}, [{"id": "a_target", "position": [0.0, -2.5]}, {"id": "z_target", "position": [0.0, -2.5]}])
	tie = _chain(tie)
	check(tie.chain.target_id == "a_target", "equal-distance target search ties use stableID")
	var hidden = _release(_fresh())
	hidden = _advance(hidden, 3, {"line_of_sight": false})
	check(hidden.chain.is_empty() and hidden.enemy.hp == 60, "occluded target is never locked")

func _test_cancellation_and_defense() -> void:
	var active = _chain(_fresh())
	for change in [{"defend_pressed": true}, {"dodge_pressed": true}, {"paused": true}, {"focused": false}, {"exit": true}, {"enemy_present": false}]:
		var f = _frame(active, change)
		check(Combat.chain_sweep(active, f).is_empty(), "cancel intent suppresses physical motion")
		var outcome = Combat.step(active, f)
		check(outcome.ok and outcome.state.chain.is_empty() and outcome.state.enemy.hp == 60 and _hits(outcome.events, "player_chain").is_empty(), "cancel leaves no ghost strike " + str(change))
		if outcome.ok and outcome.state.status != "ended":
			var changes = {"enemy_present": false} if change.has("enemy_present") else {}
			var after = _advance(outcome.state, 20, changes)
			check(after.enemy.hp == 60 and after.chain.is_empty(), "canceled chain stays canceled")
	var incoming = active.duplicate(true)
	incoming.enemy.position = [0.0, -1.0]
	incoming.enemy.phase = "active"; incoming.enemy.phase_tick = 0; incoming.enemy.phase_duration = 6
	incoming.enemy.attack_id = 1; incoming.enemy.hit_done = false; incoming.enemy.aim_direction = [0.0, 1.0]
	var hurt = _step(incoming)
	check(hurt.state.player.hp == 88 and hurt.state.chain.is_empty() and hurt.state.player.phase == "hurt", "enemy damage interrupts chain with authoritative HP")
	incoming.player.hp = 12
	var dead = _step(incoming)
	check(dead.state.player.hp == 0 and dead.state.end_reason == "failed" and dead.state.chain.is_empty(), "death clears chain without invulnerability")
	var target_dead = active.duplicate(true)
	target_dead.enemy.hp = 0
	var stopped = _step(target_dead)
	check(stopped.state.chain.is_empty() and _hits(stopped.events, "player_chain").is_empty(), "dead locked target produces no ghost strike")

func _test_motion_contract() -> void:
	var s = _chain(_fresh())
	var sweep = Combat.chain_sweep(s)
	check(sweep.radius_m == .23 and Vector2(sweep.to[0], sweep.to[1]).length() <= 2.0 / 12.0 + .00001, "scene receives bounded physical sweep at player radius")
	for fraction in [0.0, .4, 1.0]:
		var position = [lerpf(sweep.from[0], sweep.to[0], fraction), lerpf(sweep.from[1], sweep.to[1], fraction)]
		var outcome = _step(s, {"player_position": position, "chain_collision": {"attack_id": s.player.attack_id, "wall_fraction": fraction}})
		check(outcome.state.chain.is_empty() and outcome.state.enemy.hp == 60, "any first-wall contact ends motion with no hit")
	var missing = _frame(s)
	missing.erase("chain_collision")
	check(not Combat.step(s, missing).ok, "unverified motion sample rejected")
	var wrong = _frame(s, {"player_position": [0.0, -.5]})
	check(not Combat.step(s, wrong).ok, "teleport beyond swept segment rejected")
	var removed = _frame(s, {"chain_collision": {"attack_id": s.player.attack_id + 1, "wall_fraction": null}})
	check(not Combat.step(s, removed).ok, "stale sweep attackID rejected")
	# The lock does not chase a moving target; damage rechecks actual final position.
	var escaped = s
	for index in 12:
		var p = escaped.enemy.position.duplicate(); p[0] += .30
		escaped = _step(escaped, {"enemy_position": p}).state
	check(escaped.enemy.hp == 60 and escaped.chain.is_empty(), "target leaving actual strike reach cannot be hit by stale lock")
	var hidden = _advance(s, 11)
	hidden = _step(hidden, {"line_of_sight": false}).state
	check(hidden.enemy.hp == 60 and hidden.chain.is_empty(), "LOS is rechecked at strike time")

func _test_replay_and_validation() -> void:
	var s = _chain(_fresh({}, [{"id": "enemy_2", "position": [1.0, -3.0]}]))
	var f = _frame(s)
	var before = s.duplicate(true)
	var first = Combat.step(s, f)
	check(first.ok and s == before, "input state including chain and extra actors is isolated")
	var replay = Combat.step(first.state, f)
	check(replay.ok and replay.replay and replay.events.is_empty() and replay.state == first.state, "same sampled frame replays without movement or duplicate damage")
	replay.state.additional_enemies[0].hp = 1
	replay.state.chain.visited.append("bad")
	check(first.state.additional_enemies[0].hp == 60 and first.state.chain.visited.size() == 1, "returned snapshots do not alias authority")
	var conflict = f.duplicate(true); conflict.player_position[0] += .01
	check(Combat.step(first.state, conflict).get("error") == "tick_conflict", "conflicting frame replay rejected")
	for malformed in [[{"id": "enemy", "position": [0, 0]}], [{"id": "dup", "position": [0, 0]}, {"id": "dup", "position": [1, 1]}], [{"id": "a", "position": [0, 0]}, {"id": "b", "position": [1, 1]}, {"id": "c", "position": [2, 2]}]]:
		check(not Combat.fresh("invalid", stats, malformed).ok, "invalid actor registrations rejected")
	var missing = _frame(s); missing.additional_enemies = []
	check(not Combat.step(s, missing).ok, "all registered targets require exactly one external sample")
	var mutation = s.duplicate(true); mutation.chain.visited.append("enemy")
	check(not Combat.valid(mutation), "duplicate ledger identity rejected")
	mutation = s.duplicate(true); mutation.chain.elapsed_ticks = 36
	check(not Combat.valid(mutation), "unbounded duration rejected")
	mutation = s.duplicate(true); mutation.stats.charge.projectile_count = 1
	check(not Combat.valid(mutation), "ranged and chain conversions remain mutually exclusive")

func _test_real_pierce() -> void:
	var s = _fresh(ranged, [{"id": "enemy_2", "position": [0.0, -3.0]}, {"id": "enemy_3", "position": [0.0, -4.0]}])
	s.enemy.position = [0.0, -2.0]
	s = _advance(_release(s), 3)
	var hit_ids: Array = []
	for index in 36:
		var outcome = _step(s)
		if not outcome.ok: return
		s = outcome.state
		for event in _hits(outcome.events, "player_projectile"): hit_ids.append(event.target)
	check(hit_ids == ["enemy", "enemy_2"] and s.enemy.hp == 36 and s.additional_enemies[0].hp == 36 and s.additional_enemies[1].hp == 60, "one projectile pierces two real actors and never a third")
	check(s.projectiles.is_empty() and _hitstop_total(s.hitstop_log) <= 4, "piercing keeps finite lifetime and per-attack hitstop budget")

func _test_strike_boundaries() -> void:
	var prepared = _release(_fresh())
	for change in [{"defend_pressed": true}, {"dodge_pressed": true}]:
		var stopped = _step(prepared, change).state
		stopped = _advance(stopped, 6)
		check(stopped.chain.is_empty() and stopped.enemy.hp == 60, "defense cancels pending chain before target lock")
	var s = _advance(_chain(_fresh()), 11)
	for change in [{"defend_pressed": true}, {"dodge_pressed": true}, {"paused": true}, {"focused": false}, {"exit": true}]:
		var stopped = _step(s, change)
		check(stopped.state.chain.is_empty() and stopped.state.enemy.hp == 60 and _hits(stopped.events, "player_chain").is_empty(), "cancellation wins on exact strike tick")
	var sweep = Combat.chain_sweep(s)
	var wall = _step(s, {"player_position": sweep.to, "chain_collision": {"attack_id": s.player.attack_id, "wall_fraction": 1.0}})
	check(wall.state.enemy.hp == 60 and wall.state.chain.is_empty(), "endpoint wall contact wins over scheduled strike")
	var repeated = _advance(_chain(_fresh()), 12, {"attack_pressed": true, "attack_released": true})
	check(repeated.player.attack_id == 1 and repeated.enemy.hp == 36 and repeated.chain.is_empty(), "coalesced spam cannot restart chain or repeat target")
	var tap = _fresh(); tap.enemy.position = [0.0, -1.0]
	tap = _step(tap, {"attack_pressed": true, "attack_released": true}).state
	tap = _advance(tap, 3)
	check(tap.enemy.hp == 50 and tap.chain.is_empty() and tap.player.attack_kind == "normal", "chain conversion retains normal attack for a short tap")
	var multiple = _fresh({}, [{"id": "enemy_2", "position": [1.0, -3.0]}])
	multiple = _advance(_chain(multiple), 12)
	check(multiple.chain.target_id == "enemy_2", "second lock uses actual other enemy")
	var lost_sample = [{"id": "enemy_2", "position": multiple.additional_enemies[0].position, "present": false, "line_of_sight": true}]
	var lost = _step(multiple, {"additional_enemies": lost_sample})
	check(lost.state.chain.is_empty() and lost.state.additional_enemies[0].hp == 60 and not lost.state.additional_enemies[0].present, "second target despawn terminates without fabricating damage")
	var respawn = _frame(lost.state)
	respawn.additional_enemies[0].present = true
	check(not Combat.step(lost.state, respawn).ok, "absent stable identity cannot respawn within encounter")
	var cancel = _frame(multiple, {"paused": true}); cancel.erase("additional_enemies")
	var paused = Combat.step(multiple, cancel)
	check(paused.ok and paused.state.chain.is_empty(), "missing scene actors never block pause cleanup")

func _test_multi_actor_authority() -> void:
	var s = _fresh({}, [{"id": "enemy_2", "position": [.4, -1.0]}, {"id": "enemy_3", "position": [-.4, -1.0]}])
	s.enemy.position = [0.0, -1.0]
	for enemy in [s.enemy] + s.additional_enemies:
		enemy.phase = "active"; enemy.phase_tick = 0; enemy.phase_duration = 6
		enemy.attack_id = 1; enemy.hit_done = false; enemy.aim_direction = [0.0, 1.0]
	var before = s.duplicate(true)
	var attacked = _step(s)
	check(s == before and attacked.state.player.hp == 64, "three real hostile actors damage one authoritative playerHP snapshot")
	check(_hitstop_total(attacked.state.hitstop_log) <= 7, "several enemy hits obey rolling one-second hitstop cap")
	var countered = _step(s, {"defend_pressed": true})
	var starts = 0
	for event in countered.events:
		if event.kind == "attack_started": starts += 1
	check(starts == 1 and countered.state.player.attack_id == 1, "simultaneous attackers cannot recursively generate several counters")
	var survivor = _fresh({}, [{"id": "enemy_2", "position": [5.0, 0.0]}])
	survivor.enemy.hp = 10; survivor.enemy.position = [0.0, -1.0]
	survivor = _step(survivor, {"attack_pressed": true, "attack_released": true}).state
	survivor = _advance(survivor, 3)
	check(survivor.enemy.hp == 0 and survivor.status == "active" and survivor.additional_enemies[0].hp == 60, "defeating primary alone does not clear remaining real actor")
	var absent = _fresh()
	absent = _step(absent, {"enemy_present": false}).state
	check(absent.enemy.hp == 60 and absent.status == "active", "despawn cannot manufacture victory or change HP")

func _test_pierce_order_and_walls() -> void:
	var s = _fresh(ranged, [{"id": "a_target", "position": [0.0, -2.0]}, {"id": "z_target", "position": [0.0, -2.0]}])
	s.enemy.position = [0.0, -2.0]
	s = _advance(_release(s), 3)
	var ids: Array = []
	for index in 15:
		var outcome = _step(s); s = outcome.state
		for event in _hits(outcome.events, "player_projectile"): ids.append(event.target)
	check(ids == ["a_target", "enemy"] and s.additional_enemies[1].hp == 60, "simultaneous projectile contacts use stableID and hard two-target cap")
	# A real first actor is hit, while a wall prevents the later target.
	s = _fresh(ranged, [{"id": "enemy_2", "position": [0.0, -2.1]}])
	s.enemy.position = [0.0, -1.0]
	s = _advance(_release(s), 3)
	ids = []
	for index in 20:
		var changes: Dictionary = {}
		var sweeps = Combat.projectile_sweeps(s)
		if not sweeps.is_empty():
			var from: float = -sweeps[0].from[1]
			var to: float = -sweeps[0].to[1]
			if from <= 1.5 and to >= 1.5: changes.projectile_collisions = [{"attack_id": sweeps[0].attack_id, "wall_fraction": (1.5 - from) / (to - from)}]
		var outcome = _step(s, changes); s = outcome.state
		for event in _hits(outcome.events, "player_projectile"): ids.append(event.target)
	check(ids == ["enemy"] and s.additional_enemies[0].hp == 60 and s.projectiles.is_empty(), "first-wall fraction blocks second real actor after valid piercing hit")

func _test_repeatable_finishing_chain() -> void:
	var s = _fresh(fast, [{"id": "enemy_2", "position": [1.2, -3.2]}, {"id": "enemy_3", "position": [-1.2, -4.0]}])
	for attack in 3:
		if s.player.phase != "idle": s = _advance(s, 33)
		s = _chain(s)
		var hits: Array = []
		for tick in 36:
			var outcome = _step(s)
			s = outcome.state
			for hit in _hits(outcome.events, "player_chain"): hits.append(hit.target)
			check(_hitstop_total(s.hitstop_log) <= 7, "repeat casts never exceed sliding hitstop budget")
			if s.status == "ended": break
		check(hits.size() == 3 and s.player.attack_id == attack + 1, "each fresh cast gets new finite three-identity ledger")
		if attack < 2: check(s.status == "active", "surviving real enemies keep encounter active")
	check(s.status == "ended" and s.end_reason == "victory" and s.chain.is_empty() and s.projectiles.is_empty(), "final three-target lethal cast completes only after all targets defeated")
	check(s.enemy.hp == 0 and s.additional_enemies[0].hp == 0 and s.additional_enemies[1].hp == 0, "final authoritative HP is zero for each actual enemy")
