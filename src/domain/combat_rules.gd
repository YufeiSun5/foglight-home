extends RefCounted
## Fixed 60 Hz pure encounter with at most three stable enemy identities. Positions/line of sight are sampled by the scene.
## Visual hitstop never pauses logical ticks. No actor movement, nodes, IO, or story state.
## Projectiles use sampled first-wall fractions; swept target contact stays pure and deterministic.
const Chain = preload("res://src/domain/chain_charge_rules.gd")
const SCHEMA = 3
const MAX_ENEMIES = 3
const TICK_RATE = 60
const PROJECTILE_RADIUS_M = 0.10
const ENEMY_HIT_RADIUS_M = 0.30
const MAX_PROJECTILES = 4
const ENEMY_TARGET_ID = "enemy"
const CONTACT_EPSILON = 0.00000001
# The scene's Vector2 collision adapter uses float32 coordinates (bounded to100m).
# 50 micrometres covers a few coordinate ULPs at that bound. Only wall-vs-target
# ordering uses this spatial tolerance; range/lifetime/state validation stays exact.
const WALL_TIE_SLOP_M = 0.00005

const MAX_TICKS = 36000
const ENEMY_ENGAGE_DISTANCE_M = 1.20 # Approach before winding up; base melee/counter can answer.
const GUARD_REARM_TICKS = 15 # Prototype 0.25s quiet interval between precise guard presses.
const SUPPORTED_CHARGE_MODES = ["melee_charge", "ranged_charge", "chain_charge"]
const PLAYER_PHASES = ["idle", "windup", "charge", "release", "guard", "counter", "chain", "dodge", "hurt", "dead"]
const ENEMY_PHASES = ["idle", "telegraph", "active", "recovery", "dead"]
const INPUT_KEYS = ["run_id", "tick", "player_position", "player_facing", "enemy_position", "line_of_sight",
	"attack_pressed", "attack_released", "defend_pressed", "defend_released", "dodge_pressed", "focused", "paused", "exit"]

static func fresh(run_id: String, stats: Dictionary, additional_enemies: Array = []) -> Dictionary:
	if run_id.is_empty() or run_id.length() > 120 or not _valid_stats(stats): return _error("invalid_config")
	if not stats.charge.mode in SUPPORTED_CHARGE_MODES: return _error("unsupported_charge_mode")
	if not _valid_enemy_config(additional_enemies): return _error("invalid_enemies")
	var result = {"ok": true, "state": {
		"schema": SCHEMA, "run_id": run_id, "tick": 0, "sim_tick": 0, "status": "active", "end_reason": "",
		"stats": stats.duplicate(true), "projectiles": [], "additional_enemies": [], "chain": {}, "hitstop_ticks": 0, "hitstop_log": [], "last_frame_hash": "",
		"player": {"hp": 100, "position": [0.0, 0.0], "facing": [0.0, -1.0], "phase": "idle", "phase_tick": 0,
			"phase_duration": 1, "attack_held": false, "defend_held": false, "charge_ticks": 0, "guard_age_ticks": 0,
			"guard_window_spent": false, "guard_rearm_ticks": 0, "dodge_cooldown": 0, "invulnerable_ticks": 0, "attack_id": 0,
			"attack_kind": "normal", "attack_direction": [0.0, -1.0], "hit_done": false, "haste_ticks": 0},
		"enemy": {"id": ENEMY_TARGET_ID, "present": true, "hp": 60, "position": [0.0, -2.0], "phase": "idle", "phase_tick": 0, "phase_duration": 30,
			"attack_id": 0, "hit_done": false, "aim_direction": [0.0, 1.0], "reach_m": 1.65, "arc_degrees": 80.0,
			"damage": 12, "telegraph_ticks": 36, "active_ticks": 6, "recovery_ticks": 42},
	}}
	for config in additional_enemies:
		var enemy = result.state.enemy.duplicate(true)
		enemy.id = config.id
		enemy.position = config.position.duplicate()
		result.state.additional_enemies.append(enemy)
	result.state.additional_enemies.sort_custom(func(a, b): return a.id < b.id)
	return result

static func step(s: Dictionary, frame: Dictionary) -> Dictionary:
	if not valid(s): return _error("invalid_state")
	if not _valid_frame(frame): return _error("invalid_frame")
	if frame.run_id != s.run_id: return _error("stale_run")
	var fingerprint = JSON.stringify(frame, "", true).sha256_text()
	if frame.tick == s.tick:
		if fingerprint == s.last_frame_hash: return {"ok": true, "state": s.duplicate(true), "events": [], "replay": true}
		return _error("tick_conflict")
	if frame.tick != s.tick + 1: return _error("stale_tick")
	if s.status == "ended": return _error("encounter_ended")
	if not _valid_projectile_samples(s, frame): return _error("invalid_projectile_samples")
	if not _valid_enemy_samples(s, frame): return _error("invalid_enemy_samples")
	if not _valid_chain_sample(s, frame): return _error("invalid_chain_sample")
	if s.tick > 0 and not frame.exit and frame.focused and not frame.paused:
		if _distance(s.player.position, frame.player_position) > 0.65: return _error("position_step_out_of_bounds")
		for enemy in _enemies(s):
			var sample = _enemy_sample(s, frame, enemy.id)
			if sample.present and _distance(enemy.position, sample.position) > 0.35: return _error("position_step_out_of_bounds")
	var n = s.duplicate(true)
	n.tick = int(frame.tick)
	n.last_frame_hash = fingerprint
	n.player.position = frame.player_position.duplicate()
	n.player.facing = _normalized(frame.player_facing)
	for enemy in _enemies(n):
		var sample = _enemy_sample(s, frame, enemy.id)
		enemy.position = sample.position.duplicate()
		enemy.present = sample.present
	var events: Array = []
	if frame.exit:
		_finish(n, "exited", events)
		return _result(n, events)
	if frame.paused or not frame.focused:
		_cancel_inputs(n)
		_clear_projectiles(n, events)
		for enemy in _enemies(n):
			if enemy.hp > 0: _set_phase(enemy, "idle", 30)
		n.status = "paused"
		n.hitstop_ticks = 0
		if n.tick >= MAX_TICKS: _finish(n, "time_limit", events)
		return _result(n, events)
	if n.status == "paused": n.status = "active"
	n.sim_tick += 1
	n.hitstop_ticks = maxi(0, int(n.hitstop_ticks) - 1)
	while not n.hitstop_log.is_empty() and int(n.hitstop_log[0].tick) <= n.sim_tick - TICK_RATE:
		n.hitstop_log.pop_front()
	for timer in ["dodge_cooldown", "invulnerable_ticks", "haste_ticks", "guard_rearm_ticks"]:
		n.player[timer] = maxi(0, int(n.player[timer]) - 1)
	# Coalesced press+release means a complete tap, with release as the final latch state.
	# Releases also invalidate pending windows when an earlier action was interrupted.
	if frame.defend_released:
		n.player.defend_held = false
		n.player.guard_age_ticks = 0
		n.player.guard_window_spent = true
		if n.player.phase == "guard": _set_phase(n.player, "idle", 1)
	# Resolve defensive interruption against the pre-release phase. Releasing attack in
	# this frame must not turn interruptible preparation into protected recovery first.
	var interruptible = n.player.phase in ["idle", "windup", "charge", "guard", "chain"] or (n.player.phase == "release" and n.player.attack_kind == "charge" and n.stats.charge.mode == "chain_charge" and not n.player.hit_done)
	if frame.dodge_pressed and interruptible and n.player.dodge_cooldown == 0:
		_end_chain(n, "dodge", events)
		_cancel_inputs(n)
		_set_phase(n.player, "dodge", 12)
		n.player.invulnerable_ticks = 8
		n.player.dodge_cooldown = 48
		events.append({"kind": "dodge_started", "direction": n.player.facing.duplicate(), "duration_ticks": 12, "invulnerable_ticks": 8})
	elif frame.defend_pressed and not frame.defend_released and not n.player.defend_held and (interruptible or n.player.phase in ["release", "counter"]):
		_end_chain(n, "defense", events)
		n.player.attack_held = false
		n.player.charge_ticks = 0
		n.player.defend_held = true
		n.player.guard_age_ticks = 0
		# A rapid release/press may still block, but cannot reopen precision on every edge.
		n.player.guard_window_spent = n.player.guard_rearm_ticks > 0
		n.player.guard_rearm_ticks = GUARD_REARM_TICKS
		# A released attack keeps its full recovery, but remembers held defense.
		# Its precision clock starts now and keeps aging while recovery completes;
		# _update_player raises guard without granting a fresh window at that point.
		# Dodge and hurt still discard new presses, and all cancellations clear held intent.
		if interruptible: _set_phase(n.player, "guard", _ticks(n.stats.defense.counter_window_seconds))
	else:
		# Only an attack not canceled by an available dodge/guard may release or begin.
		if frame.attack_released:
			if n.player.attack_held and n.player.phase in ["windup", "charge"]:
				var charged = n.player.charge_ticks >= _ticks(n.stats.charge.hold_seconds)
				_start_attack(n, "charge" if charged else "normal", events)
			n.player.attack_held = false
			n.player.charge_ticks = 0
		if frame.attack_pressed and not n.player.attack_held and n.player.phase == "idle" and not n.player.defend_held:
			if frame.attack_released:
				# A complete tap produces one normal attack, never a held charge.
				_start_attack(n, "normal", events)
			else:
				n.player.attack_held = true
				n.player.charge_ticks = 0
				_set_phase(n.player, "windup", _ticks(n.stats.charge.hold_seconds))
	# Only pre-existing bolts fly here. A bolt born in _update_player waits until the
	# next frame, when the scene has had the chance to sweep its first segment.
	_update_projectiles(n, s, frame.get("projectile_collisions", []), events)
	_update_player(n, frame, events)
	for enemy in _enemies(n):
		if enemy.hp <= 0: _set_phase(enemy, "dead", 1)
		elif enemy.present and n.player.hp > 0: _update_enemy(n, enemy, _enemy_sample(n, frame, enemy.id).line_of_sight, events)
	if n.player.hp <= 0:
		_finish(n, "failed", events)
	elif _all_enemies_defeated(n):
		_finish(n, "victory", events)
	elif n.tick >= MAX_TICKS:
		_finish(n, "time_limit", events)
	return _result(n, events)

static func _update_player(s: Dictionary, frame: Dictionary, events: Array) -> void:
	var p: Dictionary = s.player
	p.phase_tick += 1
	if p.defend_held: p.guard_age_ticks = mini(MAX_TICKS, int(p.guard_age_ticks) + 1)
	match p.phase:
		"windup", "charge":
			p.charge_ticks = mini(_ticks(s.stats.charge.hold_seconds), int(p.charge_ticks) + 1)
			if p.phase == "windup" and p.charge_ticks >= _ticks(s.stats.charge.hold_seconds):
				_set_phase(p, "charge", 1)
		"release", "counter":
			var hit_tick = 2 if p.attack_kind == "counter" else (4 if p.attack_kind == "charge" else 3)
			if not p.hit_done and p.phase_tick >= hit_tick:
				p.hit_done = true
				_player_hit(s, frame, events)
			if p.phase != "chain" and p.phase_tick >= p.phase_duration:
				_set_phase(p, "guard" if p.defend_held else "idle", _ticks(s.stats.defense.counter_window_seconds) if p.defend_held else 1)
		"chain": _update_chain(s, frame, events)
		"dodge", "hurt":
			if p.phase_tick >= p.phase_duration: _set_phase(p, "idle", 1)
		"idle": p.phase_tick = 0

static func _update_enemy(s: Dictionary, e: Dictionary, line_of_sight: bool, events: Array) -> void:
	e.phase_tick += 1
	match e.phase:
		"idle":
			if e.phase_tick >= e.phase_duration:
				e.phase_tick = e.phase_duration
				if _distance(e.position, s.player.position) <= minf(float(e.reach_m), ENEMY_ENGAGE_DISTANCE_M) and line_of_sight:
					e.aim_direction = _toward(e.position, s.player.position)
					_set_phase(e, "telegraph", e.telegraph_ticks)
					events.append({"kind": "enemy_telegraph", "source": e.id, "origin": e.position.duplicate(), "direction": e.aim_direction.duplicate(),
						"reach_m": e.reach_m, "arc_degrees": e.arc_degrees, "duration_ticks": e.telegraph_ticks})
		"telegraph":
			if e.phase_tick >= e.phase_duration:
				e.attack_id += 1
				e.hit_done = false
				_set_phase(e, "active", e.active_ticks)
		"active":
			if not e.hit_done:
				e.hit_done = true
				_enemy_hit(s, e, line_of_sight, events)
			if e.phase_tick >= e.phase_duration: _set_phase(e, "recovery", e.recovery_ticks)
		"recovery":
			if e.phase_tick >= e.phase_duration: _set_phase(e, "idle", 30)

static func _start_attack(s: Dictionary, kind: String, events: Array) -> void:
	var p: Dictionary = s.player
	p.attack_id += 1
	p.attack_kind = kind
	p.attack_direction = p.facing.duplicate()
	p.hit_done = false
	var haste = float(s.stats.defense.counter_haste_multiplier) if p.haste_ticks > 0 else 1.0
	var duration = _ticks(1.0 / clampf(float(s.stats.normal.attack_rate_hz) * haste, 1.5, 2.7)) if kind == "normal" else _ticks(s.stats.charge.recovery_seconds)
	if kind == "counter": duration = 24
	_set_phase(p, "counter" if kind == "counter" else "release", maxi(6, duration))
	events.append({"kind": "attack_started", "source": "player", "attack_id": p.attack_id, "attack_kind": kind, "duration_ticks": p.phase_duration})

static func _player_hit(s: Dictionary, frame: Dictionary, events: Array) -> void:
	var kind: String = s.player.attack_kind
	if kind == "charge" and s.stats.charge.mode == "ranged_charge":
		_spawn_projectile(s, events)
		return
	if kind == "charge" and s.stats.charge.mode == "chain_charge":
		s.chain = Chain.begin(s.player.attack_id, s.player.position, _target_views(s, frame))
		if not s.chain.is_empty():
			_set_phase(s.player, "chain", Chain.TOTAL_TICKS)
			events.append({"kind": "chain_started", "source": "player_chain", "attack_id": s.player.attack_id, "duration_ticks": Chain.TOTAL_TICKS})
			_chain_locked(s, events)
		return
	var reach = float(s.stats.normal.reach_m)
	var damage = 10
	if kind == "charge":
		reach = float(s.stats.charge.melee_reach_m)
		damage = 24
	elif kind == "counter":
		reach = float(s.stats.defense.counter_reach_m)
		damage = roundi(16.0 * float(s.stats.defense.counter_damage_multiplier))
	var hitstop_used = 0
	for enemy in _enemies(s):
		if enemy.hp <= 0 or not enemy.present: continue
		if not _enemy_sample(s, frame, enemy.id).line_of_sight or not _in_arc(s.player.position, s.player.facing, enemy.position, reach, 110.0): continue
		enemy.hp = maxi(0, int(enemy.hp) - damage)
		hitstop_used += _hitstop(s, float(s.stats.effects.charge_hitstop_seconds) if kind != "normal" else float(s.stats.effects.normal_hitstop_seconds), 4 - hitstop_used)
		events.append({"kind": "hit", "source": "player", "target": enemy.id, "attack_id": s.player.attack_id, "attack_kind": kind, "damage": damage, "hp": enemy.hp})

static func _enemy_hit(s: Dictionary, e: Dictionary, line_of_sight: bool, events: Array) -> void:
	var p: Dictionary = s.player
	if not line_of_sight or not _in_arc(e.position, e.aim_direction, p.position, e.reach_m, e.arc_degrees): return
	if p.invulnerable_ticks > 0:
		events.append({"kind": "dodged", "source": e.id, "attack_id": e.attack_id})
		return
	var guarded = p.phase == "guard" and p.defend_held and _in_arc(p.position, p.facing, e.position, 100.0, s.stats.defense.arc_degrees)
	if guarded and s.stats.defense.counter_enabled and not p.guard_window_spent and p.guard_age_ticks <= _ticks(s.stats.defense.counter_window_seconds):
		p.guard_window_spent = true
		p.guard_rearm_ticks = GUARD_REARM_TICKS
		p.haste_ticks = _ticks(s.stats.defense.counter_haste_seconds) if s.stats.defense.counter_haste_seconds > 0 else 0
		events.append({"kind": "counter", "source": e.id, "attack_id": e.attack_id})
		_start_attack(s, "counter", events)
		return
	var damage = ceili(float(e.damage) * (1.0 - float(s.stats.defense.damage_reduction))) if guarded else int(e.damage)
	p.hp = maxi(0, int(p.hp) - damage)
	if guarded:
		events.append({"kind": "blocked", "source": e.id, "attack_id": e.attack_id, "damage": damage, "hp": p.hp})
	else:
		_end_chain(s, "hurt", events)
		_cancel_inputs(s)
		_set_phase(p, "hurt", 9)
		events.append({"kind": "hit", "source": e.id, "target": "player", "attack_id": e.attack_id, "attack_kind": "normal", "damage": damage, "hp": p.hp})
	_hitstop(s, 0.035)

static func _hitstop(s: Dictionary, seconds: float, remaining_attack_budget: int = 4) -> int:
	var used = 0
	for entry in s.hitstop_log: used += int(entry.amount)
	var amount = mini(maxi(0, roundi(seconds * TICK_RATE)), mini(floori(float(s.stats.effects.max_hitstop_per_attack_seconds) * TICK_RATE), floori(float(s.stats.effects.max_hitstop_per_second_seconds) * TICK_RATE) - used))
	amount = mini(amount, remaining_attack_budget)
	if amount <= 0: return 0
	s.hitstop_ticks = maxi(int(s.hitstop_ticks), amount)
	s.hitstop_log.append({"tick": s.sim_tick, "amount": amount})
	return amount

static func _cancel_inputs(s: Dictionary) -> void:
	s.chain = {}
	s.player.attack_held = false
	s.player.defend_held = false
	s.player.charge_ticks = 0
	s.player.guard_age_ticks = 0
	s.player.guard_window_spent = true
	s.player.invulnerable_ticks = 0
	s.player.hit_done = true
	_set_phase(s.player, "idle", 1)

static func _finish(s: Dictionary, reason: String, events: Array) -> void:
	_cancel_inputs(s)
	_clear_projectiles(s, events)
	s.player.haste_ticks = 0
	s.hitstop_ticks = 0
	s.status = "ended"
	s.end_reason = reason
	if s.player.hp <= 0: _set_phase(s.player, "dead", 1)
	for enemy in _enemies(s):
		if enemy.hp <= 0: _set_phase(enemy, "dead", 1)
	events.append({"kind": "ended", "reason": reason})

static func _set_phase(actor: Dictionary, phase: String, duration: int) -> void:
	actor.phase = phase
	actor.phase_tick = 0
	actor.phase_duration = maxi(1, duration)

static func _result(s: Dictionary, events: Array) -> Dictionary:
	for index in events.size(): events[index]["event_id"] = "%s:%d:%d" % [s.run_id, s.tick, index]
	if not valid(s): return _error("invalid_candidate")
	return {"ok": true, "state": s, "events": events, "replay": false}

static func valid(s: Dictionary) -> bool:
	if s.size() != 15: return false
	for key in ["schema", "run_id", "tick", "sim_tick", "status", "end_reason", "stats", "hitstop_ticks", "hitstop_log", "last_frame_hash", "player", "enemy", "projectiles", "additional_enemies", "chain"]:
		if not s.has(key): return false
	if not _integer(s.schema, SCHEMA, SCHEMA) or not s.run_id is String or s.run_id.is_empty() or s.run_id.length() > 120: return false
	if not _integer(s.tick, 0, MAX_TICKS) or not _integer(s.sim_tick, 0, int(s.tick)): return false
	if not s.status in ["active", "paused", "ended"] or not s.end_reason in ["", "exited", "failed", "victory", "time_limit"]: return false
	if (s.status == "ended") != (s.end_reason != ""): return false
	if not s.stats is Dictionary or not _valid_stats(s.stats) or not s.stats.charge.mode in SUPPORTED_CHARGE_MODES: return false
	if not _integer(s.hitstop_ticks, 0, 4) or not s.last_frame_hash is String or not s.last_frame_hash.length() in [0, 64]: return false
	if not s.hitstop_log is Array or s.hitstop_log.size() > 7: return false
	var hitstop_sum = 0
	for entry in s.hitstop_log:
		if not entry is Dictionary or entry.size() != 2 or not _integer(entry.get("tick"), 0, int(s.sim_tick)) or not _integer(entry.get("amount"), 1, 4): return false
		hitstop_sum += int(entry.amount)
	if hitstop_sum > 7: return false
	if not s.player is Dictionary or not s.enemy is Dictionary: return false
	var p: Dictionary = s.player
	var e: Dictionary = s.enemy
	if p.size() != 19 or e.size() != 16: return false
	if not _actor(p, PLAYER_PHASES, 100) or not _actor(e, ENEMY_PHASES, 60): return false
	if not _unit_vector(p.get("attack_direction")) or not _vector(p.get("facing"), true) or not _vector(e.get("aim_direction"), true): return false
	for key in ["attack_held", "defend_held", "guard_window_spent", "hit_done"]:
		if not p.get(key) is bool: return false
	for key in ["charge_ticks", "guard_age_ticks", "dodge_cooldown", "invulnerable_ticks", "haste_ticks", "guard_rearm_ticks"]:
		if not _integer(p.get(key), 0, MAX_TICKS): return false
	if p.invulnerable_ticks > 8 or p.dodge_cooldown > 48 or p.guard_rearm_ticks > GUARD_REARM_TICKS or not p.get("attack_kind") in ["normal", "charge", "counter"]: return false
	if not e.get("hit_done") is bool or e.get("reach_m") != 1.65 or e.get("arc_degrees") != 80.0 or e.get("damage") != 12: return false
	if not s.additional_enemies is Array or s.additional_enemies.size() >= MAX_ENEMIES: return false
	var target_ids: Array = []
	for enemy in _enemies(s):
		if not _valid_enemy(enemy) or enemy.id in target_ids: return false
		target_ids.append(enemy.id)
	if e.id != ENEMY_TARGET_ID: return false
	if not s.chain is Dictionary: return false
	if s.chain.is_empty():
		if p.phase == "chain": return false
	else:
		if s.status != "active" or s.stats.charge.mode != "chain_charge" or p.phase != "chain" or p.attack_kind != "charge": return false
		if not Chain.valid(s.chain, p.attack_id, target_ids): return false
		var progress = float(s.chain.leg_tick) / Chain.LEG_TICKS
		if _distance(p.position, _lerp_point(s.chain.origin, s.chain.destination, progress)) > Chain.POSITION_SLOP_M: return false
	if not _valid_projectiles(s): return false
	return true

static func _actor(a: Dictionary, phases: Array, max_hp: int) -> bool:
	return _integer(a.get("hp"), 0, max_hp) and _vector(a.get("position")) and a.get("phase") in phases and _integer(a.get("phase_tick"), 0, MAX_TICKS) and _integer(a.get("phase_duration"), 1, MAX_TICKS) and _integer(a.get("attack_id"), 0, MAX_TICKS)

static func _valid_stats(stats: Dictionary) -> bool:
	if stats.size() != 4: return false
	for section in ["normal", "charge", "defense", "effects"]:
		if not stats.get(section) is Dictionary or stats[section].size() > 24: return false
		for value in stats[section].values():
			if not (value is int or value is float or value is bool or value is String): return false
			if value is String and value.length() > 40: return false
			if (value is int or value is float) and (not is_finite(float(value)) or absf(float(value)) > 1000.0): return false
	var n: Dictionary = stats.normal
	var c: Dictionary = stats.charge
	var d: Dictionary = stats.defense
	var e: Dictionary = stats.effects
	if n.get("enabled") != true or c.get("enabled") != true or d.get("enabled") != true or c.get("requires_charge") != true: return false
	if not c.get("mode") in ["melee_charge", "ranged_charge", "chain_charge"]: return false
	for pair in [[n.get("attack_rate_hz"), 1.5, 2.7], [n.get("reach_m"), 1.25, 1.7],
		[c.get("hold_seconds"), 0.06, 0.9], [c.get("recovery_seconds"), 0.55, 0.55], [c.get("melee_reach_m"), 1.5, 2.0],
		[d.get("damage_reduction"), 0.0, 0.8], [d.get("arc_degrees"), 60.0, 140.0], [d.get("counter_window_seconds"), 0.05, 0.16],
		[d.get("counter_damage_multiplier"), 1.0, 2.0], [d.get("counter_reach_m"), 1.0, 1.7],
		[d.get("counter_haste_multiplier"), 1.0, 1.3], [d.get("counter_haste_seconds"), 0.0, 1.0],
		[e.get("normal_hitstop_seconds"), 0.0, 0.05], [e.get("charge_hitstop_seconds"), 0.0, 0.06]]:
		if not _number(pair[0], pair[1], pair[2]): return false
	if not _valid_charge_shape(c): return false
	return d.get("counter_enabled") is bool and e.get("max_hitstop_per_attack_seconds") == 0.07 and e.get("max_hitstop_per_second_seconds") == 0.12 and e.get("invulnerability_seconds") == 0.0

static func _valid_frame(f: Dictionary) -> bool:
	var optional = ["projectile_collisions", "additional_enemies", "enemy_present", "chain_collision"]
	for key in f:
		if not key in INPUT_KEYS and not key in optional: return false
	if f.has("projectile_collisions") and not _projectile_samples_shape(f.projectile_collisions): return false
	if f.has("enemy_present") and not f.enemy_present is bool: return false
	if f.has("additional_enemies") and not _enemy_samples_shape(f.additional_enemies): return false
	if f.has("chain_collision"):
		var sample: Variant = f.chain_collision
		if not sample is Dictionary or sample.size() != 2 or not sample.has("wall_fraction"): return false
		if not _integer(sample.get("attack_id"), 1, MAX_TICKS): return false
		if sample.wall_fraction != null and not _number(sample.wall_fraction, 0.0, 1.0): return false
	for key in INPUT_KEYS:
		if not f.has(key): return false
	if not f.run_id is String or not _integer(f.tick, 1, MAX_TICKS): return false
	if not _vector(f.player_position) or not _vector(f.enemy_position) or not _vector(f.player_facing, true): return false
	for key in ["line_of_sight", "attack_pressed", "attack_released", "defend_pressed", "defend_released", "dodge_pressed", "focused", "paused", "exit"]:
		if not f[key] is bool: return false
	return true

static func _in_arc(origin: Array, direction: Array, target: Array, reach: float, arc_degrees: float) -> bool:
	var distance = _distance(origin, target)
	if distance > reach: return false
	if distance < 0.001: return true
	var toward = _toward(origin, target)
	return float(direction[0]) * float(toward[0]) + float(direction[1]) * float(toward[1]) >= cos(deg_to_rad(arc_degrees * 0.5))
static func _distance(a: Array, b: Array) -> float: return Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))
static func _toward(a: Array, b: Array) -> Array: return _normalized([float(b[0]) - float(a[0]), float(b[1]) - float(a[1])])
static func _normalized(value: Array) -> Array:
	var v = Vector2(float(value[0]), float(value[1])).normalized()
	return [0.0, 1.0] if v.is_zero_approx() else [v.x, v.y]
static func _ticks(seconds: float) -> int: return maxi(1, ceili(seconds * TICK_RATE))
static func _vector(value: Variant, direction: bool = false) -> bool:
	if not value is Array or value.size() != 2: return false
	for number in value:
		if not _number(number, -100.0, 100.0): return false
	return not direction or (Vector2(float(value[0]), float(value[1])).length() >= 0.5 and Vector2(float(value[0]), float(value[1])).length() <= 1.5)
static func _number(value: Variant, low: float, high: float) -> bool: return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high
static func _integer(value: Variant, low: int, high: int) -> bool: return value is int and value >= low and value <= high
static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}

## Read-only physics boundary for the next active tick. Every existing bolt requires
## one first-wall sample, even if the player is in recovery or the enemy is far away.
## A new bolt never moves or damages on its birth tick. No physics callback enters rules.
static func projectile_sweeps(s: Dictionary) -> Array:
	if not valid(s) or s.status != "active": return []
	var sweeps: Array = []
	for projectile in s.projectiles:
		sweeps.append({"attack_id": projectile.attack_id, "from": projectile.position.duplicate(),
			"to": _projectile_endpoint(projectile, s.stats.charge), "radius_m": PROJECTILE_RADIUS_M})
	return sweeps

static func _projectile_endpoint(projectile: Dictionary, charge: Dictionary) -> Array:
	var distance = minf(float(charge.projectile_reach_m), minf(float(charge.projectile_lifetime_seconds), float(projectile.age_ticks + 1) / TICK_RATE) * float(charge.projectile_speed_mps))
	return [float(projectile.origin[0]) + float(projectile.direction[0]) * distance,
		float(projectile.origin[1]) + float(projectile.direction[1]) * distance]

static func _spawn_projectile(s: Dictionary, events: Array) -> void:
	# With current release/charge/recovery timing at most two can coexist after a
	# hurt interruption. Keep an independent hard cap for future timing changes.
	if s.projectiles.size() >= MAX_PROJECTILES: return
	var projectile = {"attack_id": s.player.attack_id, "source": "player_projectile",
		"origin": s.player.position.duplicate(), "position": s.player.position.duplicate(),
		"direction": s.player.attack_direction.duplicate(), "age_ticks": 0, "travelled_m": 0.0,
		"hit_targets": [], "hitstop_used_ticks": 0}
	s.projectiles.append(projectile)
	events.append({"kind": "projectile_spawned", "source": projectile.source, "attack_id": projectile.attack_id,
		"origin": projectile.origin.duplicate(), "direction": projectile.direction.duplicate(),
		"radius_m": PROJECTILE_RADIUS_M, "speed_mps": s.stats.charge.projectile_speed_mps,
		"reach_m": s.stats.charge.projectile_reach_m, "lifetime_seconds": s.stats.charge.projectile_lifetime_seconds})

static func _update_projectiles(s: Dictionary, previous: Dictionary, samples: Array, events: Array) -> void:
	var survivors: Array = []
	for projectile in s.projectiles:
		var end: Array = _projectile_endpoint(projectile, s.stats.charge)
		var wall: Variant = null
		for sample in samples:
			if sample.attack_id == projectile.attack_id:
				wall = sample.wall_fraction
				break
		var contacts: Array = []
		for enemy in _enemies(s):
			if enemy.hp <= 0 or not enemy.present or enemy.id in projectile.hit_targets: continue
			# Both actor and projectile interpolation use this segment's clipped time.
			var remaining_seconds = float(s.stats.charge.projectile_lifetime_seconds) - float(projectile.age_ticks) / TICK_RATE
			var remaining_range = float(s.stats.charge.projectile_reach_m) - float(projectile.travelled_m)
			var flight_fraction = clampf(minf(remaining_seconds, remaining_range / float(s.stats.charge.projectile_speed_mps)) * TICK_RATE, 0.0, 1.0)
			var previous_position: Array = _enemy_by_id(previous, enemy.id).position
			var target_end = _lerp_point(previous_position, enemy.position, flight_fraction)
			var contact = _swept_target_fraction(projectile.position, end, previous_position, target_end)
			# First wall wins ties, including Vector2 float32 rounding at physical walls.
			if contact >= 0.0 and (wall == null or contact * _distance(projectile.position, end) + WALL_TIE_SLOP_M < float(wall) * _distance(projectile.position, end)):
				contacts.append({"fraction": contact, "id": enemy.id})
		contacts.sort_custom(func(a, b): return a.id < b.id if a.fraction == b.fraction else a.fraction < b.fraction)
		var exhausted = false
		for contact in contacts:
			var enemy = _enemy_by_id(s, contact.id)
			projectile.hit_targets.append(enemy.id)
			enemy.hp = maxi(0, int(enemy.hp) - 24)
			projectile.hitstop_used_ticks += _hitstop(s, s.stats.effects.charge_hitstop_seconds, 4 - int(projectile.hitstop_used_ticks))
			events.append({"kind": "hit", "source": "player_projectile", "target": enemy.id,
				"attack_id": projectile.attack_id, "attack_kind": "charge", "damage": 24, "hp": enemy.hp,
				"position": _lerp_point(projectile.position, end, contact.fraction)})
			if projectile.hit_targets.size() >= int(s.stats.charge.projectile_max_targets):
				projectile.position = _lerp_point(projectile.position, end, contact.fraction)
				_projectile_ended(projectile, "targets", events)
				exhausted = true
				break
		if exhausted: continue
		if wall != null:
			projectile.position = _lerp_point(projectile.position, end, float(wall))
			_projectile_ended(projectile, "wall", events)
			continue
		projectile.age_ticks += 1
		projectile.position = end
		projectile.travelled_m = minf(float(s.stats.charge.projectile_reach_m), minf(float(s.stats.charge.projectile_lifetime_seconds), float(projectile.age_ticks) / TICK_RATE) * float(s.stats.charge.projectile_speed_mps))
		if float(projectile.travelled_m) + CONTACT_EPSILON >= float(s.stats.charge.projectile_reach_m):
			_projectile_ended(projectile, "range", events)
		elif float(projectile.age_ticks) / TICK_RATE + CONTACT_EPSILON >= float(s.stats.charge.projectile_lifetime_seconds):
			_projectile_ended(projectile, "lifetime", events)
		else:
			survivors.append(projectile)
	s.projectiles = survivors

static func _projectile_ended(projectile: Dictionary, reason: String, events: Array) -> void:
	events.append({"kind": "projectile_ended", "source": projectile.source, "attack_id": projectile.attack_id,
		"reason": reason, "position": projectile.position.duplicate()})

static func _clear_projectiles(s: Dictionary, events: Array) -> void:
	for projectile in s.projectiles: _projectile_ended(projectile, "canceled", events)
	s.projectiles = []

static func _swept_target_fraction(start: Array, end: Array, target_start: Array, target_end: Array) -> float:
	# Relative motion solves first circle contact, including a target crossing the
	# bolt between samples. Endpoint-only distance would tunnel through moving targets.
	var rx = float(start[0]) - float(target_start[0])
	var ry = float(start[1]) - float(target_start[1])
	var vx = float(end[0]) - float(start[0]) - float(target_end[0]) + float(target_start[0])
	var vy = float(end[1]) - float(start[1]) - float(target_end[1]) + float(target_start[1])
	var radius = PROJECTILE_RADIUS_M + ENEMY_HIT_RADIUS_M
	var c = rx * rx + ry * ry - radius * radius
	if c <= 0.0: return 0.0
	var a = vx * vx + vy * vy
	if a <= 0.000000000001: return -1.0
	var b = 2.0 * (rx * vx + ry * vy)
	var discriminant = b * b - 4.0 * a * c
	if discriminant < 0.0: return -1.0
	var fraction = (-b - sqrt(discriminant)) / (2.0 * a)
	return clampf(fraction, 0.0, 1.0) if fraction >= -CONTACT_EPSILON and fraction <= 1.0 + CONTACT_EPSILON else -1.0

static func _lerp_point(start: Array, end: Array, fraction: float) -> Array:
	return [lerpf(float(start[0]), float(end[0]), fraction), lerpf(float(start[1]), float(end[1]), fraction)]

static func _projectile_samples_shape(samples: Variant) -> bool:
	if not samples is Array or samples.size() > MAX_PROJECTILES: return false
	var seen: Dictionary = {}
	for sample in samples:
		if not sample is Dictionary or sample.size() != 2 or not sample.has("wall_fraction"): return false
		if not _integer(sample.get("attack_id"), 1, MAX_TICKS) or seen.has(sample.attack_id): return false
		if sample.wall_fraction != null and not _number(sample.wall_fraction, 0.0, 1.0): return false
		seen[sample.attack_id] = true
	return true

static func _valid_projectile_samples(s: Dictionary, frame: Dictionary) -> bool:
	var samples: Array = frame.get("projectile_collisions", [])
	# Cancellation does no flight; omitting its samples must never prevent cleanup.
	# Any supplied IDs must still belong to the current state, even on cancellation.
	var ids: Array = []
	for projectile in s.projectiles: ids.append(projectile.attack_id)
	for sample in samples:
		if not sample.attack_id in ids: return false
	if frame.exit or frame.paused or not frame.focused: return true
	return samples.size() == s.projectiles.size()

static func _valid_projectiles(s: Dictionary) -> bool:
	if not s.projectiles is Array or s.projectiles.size() > MAX_PROJECTILES: return false
	if (s.status != "active" or s.stats.charge.mode != "ranged_charge") and not s.projectiles.is_empty(): return false
	var ids: Dictionary = {}
	for projectile in s.projectiles:
		if not projectile is Dictionary or projectile.size() != 9: return false
		for key in ["attack_id", "source", "origin", "position", "direction", "age_ticks", "travelled_m", "hit_targets", "hitstop_used_ticks"]:
			if not projectile.has(key): return false
		if not _integer(projectile.attack_id, 1, int(s.player.attack_id)) or ids.has(projectile.attack_id) or projectile.source != "player_projectile": return false
		ids[projectile.attack_id] = true
		if not _vector(projectile.origin) or not _projectile_vector(projectile.position) or not _unit_vector(projectile.direction): return false
		if not _integer(projectile.age_ticks, 0, _ticks(s.stats.charge.projectile_lifetime_seconds) - 1): return false
		if not _number(projectile.travelled_m, 0.0, s.stats.charge.projectile_reach_m): return false
		var expected_distance = float(projectile.age_ticks) * float(s.stats.charge.projectile_speed_mps) / TICK_RATE
		if absf(float(projectile.travelled_m) - expected_distance) > CONTACT_EPSILON: return false
		if float(projectile.travelled_m) + CONTACT_EPSILON >= float(s.stats.charge.projectile_reach_m): return false
		var expected_position = [float(projectile.origin[0]) + float(projectile.direction[0]) * expected_distance,
			float(projectile.origin[1]) + float(projectile.direction[1]) * expected_distance]
		if _distance(projectile.position, expected_position) > 0.00001: return false
		if not _integer(projectile.hitstop_used_ticks, 0, 4): return false
		if not projectile.hit_targets is Array or projectile.hit_targets.size() >= int(s.stats.charge.projectile_max_targets): return false
		var seen_targets: Dictionary = {}
		for id in projectile.hit_targets:
			if not id is String or _enemy_by_id(s, id).is_empty() or seen_targets.has(id): return false
			seen_targets[id] = true
	return true

static func _valid_charge_shape(charge: Dictionary) -> bool:
	var keys = ["enabled", "mode", "requires_charge", "hold_seconds", "recovery_seconds", "melee_reach_m", "trail_layers",
		"projectile_reach_m", "projectile_speed_mps", "projectile_count", "projectile_pierce", "projectile_max_targets", "projectile_lifetime_seconds",
		"chain_max_targets", "chain_search_radius_m", "chain_max_step_m", "chain_duration_seconds"]
	if charge.size() != keys.size(): return false
	for key in keys:
		if not charge.has(key): return false
	var ranged = charge.mode == "ranged_charge"
	for pair in [["projectile_count", 1 if ranged else 0], ["projectile_pierce", 1 if ranged else 0], ["projectile_max_targets", 2 if ranged else 0]]:
		if not _integer(charge[pair[0]], pair[1], pair[1]): return false
	if ranged:
		if not _number(charge.projectile_reach_m, 5.5, 6.0) or not _number(charge.projectile_speed_mps, 10.0, 10.0): return false
		if not _number(charge.projectile_lifetime_seconds, 0.55, 0.60): return false
		if absf(float(charge.projectile_lifetime_seconds) - float(charge.projectile_reach_m) / float(charge.projectile_speed_mps)) > CONTACT_EPSILON: return false
	else:
		for key in ["projectile_reach_m", "projectile_speed_mps", "projectile_lifetime_seconds"]:
			if not _number(charge[key], 0.0, 0.0): return false
	var chain = charge.mode == "chain_charge"
	if not _integer(charge.chain_max_targets, 3 if chain else 0, 3 if chain else 0): return false
	for pair in [["chain_search_radius_m", 3.0 if chain else 0.0], ["chain_max_step_m", 2.0 if chain else 0.0], ["chain_duration_seconds", 0.60 if chain else 0.0]]:
		if not _number(charge[pair[0]], pair[1], pair[1]): return false
	return true

static func _unit_vector(value: Variant) -> bool:
	return _vector(value, true) and absf(float(value[0]) * float(value[0]) + float(value[1]) * float(value[1]) - 1.0) <= 0.000001

static func _projectile_vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0], -106.0, 106.0) and _number(value[1], -106.0, 106.0)

## Primary actor is never mirrored in additional_enemies; these are transient references.
static func _enemies(s: Dictionary) -> Array:
	var result: Array = [s.enemy]
	result.append_array(s.additional_enemies)
	return result

static func _enemy_by_id(s: Dictionary, id: String) -> Dictionary:
	for enemy in _enemies(s):
		if enemy.id == id: return enemy
	return {}

static func _valid_enemy_config(config: Array) -> bool:
	if config.size() >= MAX_ENEMIES: return false
	var ids: Dictionary = {ENEMY_TARGET_ID: true}
	for entry in config:
		if not entry is Dictionary or entry.size() != 2 or not _target_id(entry.get("id")) or not _vector(entry.get("position")): return false
		if ids.has(entry.id): return false
		ids[entry.id] = true
	return true

static func _target_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 60: return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func _valid_enemy(e: Variant) -> bool:
	if not e is Dictionary or e.size() != 16 or not _target_id(e.get("id")) or not e.get("present") is bool: return false
	if not _actor(e, ENEMY_PHASES, 60) or not _vector(e.get("aim_direction"), true): return false
	if not e.get("hit_done") is bool or e.get("reach_m") != 1.65 or e.get("arc_degrees") != 80.0 or e.get("damage") != 12: return false
	return e.get("telegraph_ticks") == 36 and e.get("active_ticks") == 6 and e.get("recovery_ticks") == 42

static func _enemy_samples_shape(samples: Variant) -> bool:
	if not samples is Array or samples.size() >= MAX_ENEMIES: return false
	var ids: Dictionary = {}
	for sample in samples:
		if not sample is Dictionary or sample.size() != 4 or not _target_id(sample.get("id")) or not _vector(sample.get("position")): return false
		if not sample.get("present") is bool or not sample.get("line_of_sight") is bool or ids.has(sample.id): return false
		ids[sample.id] = true
	return true

static func _valid_enemy_samples(s: Dictionary, frame: Dictionary) -> bool:
	if not s.enemy.present and frame.get("enemy_present", false): return false
	var samples: Array = frame.get("additional_enemies", [])
	for sample in samples:
		var enemy = _enemy_by_id(s, sample.id)
		if enemy.is_empty() or sample.id == ENEMY_TARGET_ID or (not enemy.present and sample.present): return false
	if frame.exit or frame.paused or not frame.focused: return true
	return samples.size() == s.additional_enemies.size()

static func _enemy_sample(s: Dictionary, frame: Dictionary, id: String) -> Dictionary:
	if id == ENEMY_TARGET_ID:
		return {"id": id, "position": frame.enemy_position, "line_of_sight": frame.line_of_sight, "present": frame.get("enemy_present", s.enemy.present)}
	for sample in frame.get("additional_enemies", []):
		if sample.id == id: return sample
	var enemy = _enemy_by_id(s, id)
	return {"id": id, "position": enemy.position, "line_of_sight": false, "present": enemy.present}

static func _target_views(s: Dictionary, frame: Dictionary) -> Array:
	var targets: Array = []
	for enemy in _enemies(s):
		targets.append({"id": enemy.id, "hp": enemy.hp, "present": enemy.present, "position": enemy.position,
			"line_of_sight": _enemy_sample(s, frame, enemy.id).line_of_sight})
	return targets

static func _all_enemies_defeated(s: Dictionary) -> bool:
	for enemy in _enemies(s):
		if enemy.hp > 0: return false
	return true

## The scene supplies current edges/presence before moving. Shared arbitration keeps
## defense, dodge, focus, pause, exit and disappeared-target frames motion-free.
static func chain_sweep(s: Dictionary, intent: Dictionary = {}) -> Dictionary:
	if not valid(s) or s.status != "active" or s.chain.is_empty() or _chain_canceled(s, intent): return {}
	return Chain.sweep(s.chain, s.player.position)

static func _chain_canceled(s: Dictionary, intent: Dictionary) -> bool:
	if intent.get("exit", false) or intent.get("paused", false) or not intent.get("focused", true) or s.player.hp <= 0: return true
	if intent.get("dodge_pressed", false) and s.player.dodge_cooldown <= 1: return true
	if intent.get("defend_pressed", false) and not intent.get("defend_released", false) and not s.player.defend_held: return true
	var target = _enemy_by_id(s, s.chain.target_id)
	if target.is_empty() or target.hp <= 0 or not target.present: return true
	if target.id == ENEMY_TARGET_ID: return not intent.get("enemy_present", true)
	for sample in intent.get("additional_enemies", []):
		if sample is Dictionary and sample.get("id") == target.id: return not sample.get("present", true)
	return false

static func _valid_chain_sample(s: Dictionary, frame: Dictionary) -> bool:
	if s.chain.is_empty(): return not frame.has("chain_collision")
	if frame.has("chain_collision") and frame.chain_collision.attack_id != s.chain.attack_id: return false
	if _chain_canceled(s, frame): return true
	if not frame.has("chain_collision"): return false
	return Chain.sampled_position_matches(Chain.sweep(s.chain, s.player.position), frame.player_position, frame.chain_collision.wall_fraction)

static func _chain_locked(s: Dictionary, events: Array) -> void:
	s.player.facing = s.chain.direction.duplicate()
	events.append({"kind": "chain_target_locked", "source": "player_chain", "attack_id": s.chain.attack_id,
		"target": s.chain.target_id, "origin": s.chain.origin.duplicate(), "destination": s.chain.destination.duplicate(),
		"direction": s.chain.direction.duplicate(), "duration_ticks": Chain.LEG_TICKS})

static func _update_chain(s: Dictionary, frame: Dictionary, events: Array) -> void:
	if s.chain.is_empty(): return
	var chain: Dictionary = s.chain
	var target = _enemy_by_id(s, chain.target_id)
	if target.is_empty() or not target.present or target.hp <= 0 or s.player.hp <= 0:
		_end_chain(s, "target_lost", events)
		return
	if frame.get("chain_collision", {}).get("wall_fraction") != null:
		_end_chain(s, "wall", events)
		return
	chain.elapsed_ticks += 1
	chain.leg_tick += 1
	s.player.facing = chain.direction.duplicate()
	if chain.leg_tick >= Chain.LEG_TICKS:
		if not _enemy_sample(s, frame, target.id).line_of_sight or not _in_arc(s.player.position, chain.direction, target.position, s.stats.charge.melee_reach_m, 110.0):
			_end_chain(s, "miss", events)
			return
		target.hp = maxi(0, int(target.hp) - 24)
		chain.hitstop_used_ticks += _hitstop(s, s.stats.effects.charge_hitstop_seconds, 4 - int(chain.hitstop_used_ticks))
		events.append({"kind": "hit", "source": "player_chain", "target": target.id, "attack_id": chain.attack_id,
			"attack_kind": "charge", "damage": 24, "hp": target.hp, "position": target.position.duplicate()})
		if chain.elapsed_ticks >= Chain.TOTAL_TICKS or chain.visited.size() >= Chain.MAX_TARGETS:
			_end_chain(s, "targets" if chain.visited.size() >= Chain.MAX_TARGETS else "duration", events)
		elif Chain.next_leg(chain, s.player.position, _target_views(s, frame)):
			_chain_locked(s, events)
		else:
			_end_chain(s, "no_target", events)

static func _end_chain(s: Dictionary, reason: String, events: Array) -> void:
	if s.chain.is_empty(): return
	events.append({"kind": "chain_ended", "source": "player_chain", "attack_id": s.chain.attack_id, "reason": reason})
	s.chain = {}
	s.player.hit_done = true
	_set_phase(s.player, "release", _ticks(s.stats.charge.recovery_seconds))
