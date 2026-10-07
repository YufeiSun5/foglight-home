extends RefCounted
## Fixed 60 Hz pure single-enemy encounter. Positions/line of sight are sampled by the scene.
## Visual hitstop never pauses logical ticks. No movement, projectiles, nodes, IO, or story state.
const TICK_RATE = 60
const MAX_TICKS = 36000
const GUARD_REARM_TICKS = 15 # Prototype 0.25s quiet interval between precise guard presses.
const SUPPORTED_CHARGE_MODES = ["melee_charge"]
const PLAYER_PHASES = ["idle", "windup", "charge", "release", "guard", "counter", "dodge", "hurt", "dead"]
const ENEMY_PHASES = ["idle", "telegraph", "active", "recovery", "dead"]
const INPUT_KEYS = ["run_id", "tick", "player_position", "player_facing", "enemy_position", "line_of_sight",
	"attack_pressed", "attack_released", "defend_pressed", "defend_released", "dodge_pressed", "focused", "paused", "exit"]

static func fresh(run_id: String, stats: Dictionary) -> Dictionary:
	if run_id.is_empty() or run_id.length() > 120 or not _valid_stats(stats): return _error("invalid_config")
	if not stats.charge.mode in SUPPORTED_CHARGE_MODES: return _error("unsupported_charge_mode")
	return {"ok": true, "state": {
		"schema": 1, "run_id": run_id, "tick": 0, "sim_tick": 0, "status": "active", "end_reason": "",
		"stats": stats.duplicate(true), "hitstop_ticks": 0, "hitstop_log": [], "last_frame_hash": "",
		"player": {"hp": 100, "position": [0.0, 0.0], "facing": [0.0, -1.0], "phase": "idle", "phase_tick": 0,
			"phase_duration": 1, "attack_held": false, "defend_held": false, "charge_ticks": 0, "guard_age_ticks": 0,
			"guard_window_spent": false, "guard_rearm_ticks": 0, "dodge_cooldown": 0, "invulnerable_ticks": 0, "attack_id": 0,
			"attack_kind": "normal", "hit_done": false, "haste_ticks": 0},
		"enemy": {"hp": 60, "position": [0.0, -2.0], "phase": "idle", "phase_tick": 0, "phase_duration": 30,
			"attack_id": 0, "hit_done": false, "aim_direction": [0.0, 1.0], "reach_m": 1.65, "arc_degrees": 80.0,
			"damage": 12, "telegraph_ticks": 36, "active_ticks": 6, "recovery_ticks": 42},
	}}

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
	if s.tick > 0 and not frame.exit and frame.focused and not frame.paused:
		if _distance(s.player.position, frame.player_position) > 0.65 or _distance(s.enemy.position, frame.enemy_position) > 0.35:
			return _error("position_step_out_of_bounds")
	var n = s.duplicate(true)
	n.tick = int(frame.tick)
	n.last_frame_hash = fingerprint
	n.player.position = frame.player_position.duplicate()
	n.player.facing = _normalized(frame.player_facing)
	n.enemy.position = frame.enemy_position.duplicate()
	var events: Array = []
	if frame.exit:
		_finish(n, "exited", events)
		return _result(n, events)
	if frame.paused or not frame.focused:
		_cancel_inputs(n)
		_set_phase(n.enemy, "idle", 30)
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
	if frame.attack_released:
		if n.player.attack_held and n.player.phase in ["windup", "charge"]:
			var charged = n.player.charge_ticks >= _ticks(n.stats.charge.hold_seconds)
			_start_attack(n, "charge" if charged else "normal", events)
		n.player.attack_held = false
		n.player.charge_ticks = 0
	var interruptible = n.player.phase in ["idle", "windup", "charge", "guard"]
	if frame.dodge_pressed and interruptible and n.player.dodge_cooldown == 0:
		_cancel_inputs(n)
		_set_phase(n.player, "dodge", 12)
		n.player.invulnerable_ticks = 8
		n.player.dodge_cooldown = 48
		events.append({"kind": "dodge_started", "direction": n.player.facing.duplicate(), "duration_ticks": 12, "invulnerable_ticks": 8})
	elif frame.defend_pressed and not frame.defend_released and not n.player.defend_held and interruptible:
		n.player.attack_held = false
		n.player.charge_ticks = 0
		n.player.defend_held = true
		n.player.guard_age_ticks = 0
		# A rapid release/press may still block, but cannot reopen precision on every edge.
		n.player.guard_window_spent = n.player.guard_rearm_ticks > 0
		n.player.guard_rearm_ticks = GUARD_REARM_TICKS
		_set_phase(n.player, "guard", _ticks(n.stats.defense.counter_window_seconds))
	elif frame.attack_pressed and not n.player.attack_held and n.player.phase == "idle" and not n.player.defend_held:
		if frame.attack_released:
			# A new tap fully contained in this tick produces one normal attack, never a held charge.
			_start_attack(n, "normal", events)
		else:
			n.player.attack_held = true
			n.player.charge_ticks = 0
			_set_phase(n.player, "windup", _ticks(n.stats.charge.hold_seconds))
	_update_player(n, frame.line_of_sight, events)
	if n.enemy.hp > 0 and n.player.hp > 0: _update_enemy(n, frame.line_of_sight, events)
	if n.player.hp <= 0:
		_finish(n, "failed", events)
	elif n.enemy.hp <= 0:
		_finish(n, "victory", events)
	elif n.tick >= MAX_TICKS:
		_finish(n, "time_limit", events)
	return _result(n, events)

static func _update_player(s: Dictionary, line_of_sight: bool, events: Array) -> void:
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
				_player_hit(s, line_of_sight, events)
			if p.phase_tick >= p.phase_duration:
				_set_phase(p, "guard" if p.defend_held else "idle", _ticks(s.stats.defense.counter_window_seconds) if p.defend_held else 1)
		"dodge", "hurt":
			if p.phase_tick >= p.phase_duration: _set_phase(p, "idle", 1)
		"idle": p.phase_tick = 0

static func _update_enemy(s: Dictionary, line_of_sight: bool, events: Array) -> void:
	var e: Dictionary = s.enemy
	e.phase_tick += 1
	match e.phase:
		"idle":
			if e.phase_tick >= e.phase_duration:
				e.phase_tick = e.phase_duration
				if _distance(e.position, s.player.position) <= float(e.reach_m) + 0.10 and line_of_sight:
					e.aim_direction = _toward(e.position, s.player.position)
					_set_phase(e, "telegraph", e.telegraph_ticks)
					events.append({"kind": "enemy_telegraph", "origin": e.position.duplicate(), "direction": e.aim_direction.duplicate(),
						"reach_m": e.reach_m, "arc_degrees": e.arc_degrees, "duration_ticks": e.telegraph_ticks})
		"telegraph":
			if e.phase_tick >= e.phase_duration:
				e.attack_id += 1
				e.hit_done = false
				_set_phase(e, "active", e.active_ticks)
		"active":
			if not e.hit_done:
				e.hit_done = true
				_enemy_hit(s, line_of_sight, events)
			if e.phase_tick >= e.phase_duration: _set_phase(e, "recovery", e.recovery_ticks)
		"recovery":
			if e.phase_tick >= e.phase_duration: _set_phase(e, "idle", 30)

static func _start_attack(s: Dictionary, kind: String, events: Array) -> void:
	var p: Dictionary = s.player
	p.attack_id += 1
	p.attack_kind = kind
	p.hit_done = false
	var haste = float(s.stats.defense.counter_haste_multiplier) if p.haste_ticks > 0 else 1.0
	var duration = _ticks(1.0 / clampf(float(s.stats.normal.attack_rate_hz) * haste, 1.5, 2.7)) if kind == "normal" else _ticks(s.stats.charge.recovery_seconds)
	if kind == "counter": duration = 24
	_set_phase(p, "counter" if kind == "counter" else "release", maxi(6, duration))
	events.append({"kind": "attack_started", "source": "player", "attack_id": p.attack_id, "attack_kind": kind, "duration_ticks": p.phase_duration})

static func _player_hit(s: Dictionary, line_of_sight: bool, events: Array) -> void:
	var kind: String = s.player.attack_kind
	var reach = float(s.stats.normal.reach_m)
	var damage = 10
	if kind == "charge":
		reach = float(s.stats.charge.melee_reach_m)
		damage = 24
	elif kind == "counter":
		reach = float(s.stats.defense.counter_reach_m)
		damage = roundi(16.0 * float(s.stats.defense.counter_damage_multiplier))
	if not line_of_sight or not _in_arc(s.player.position, s.player.facing, s.enemy.position, reach, 110.0): return
	s.enemy.hp = maxi(0, int(s.enemy.hp) - damage)
	_hitstop(s, float(s.stats.effects.charge_hitstop_seconds) if kind != "normal" else float(s.stats.effects.normal_hitstop_seconds))
	events.append({"kind": "hit", "source": "player", "target": "enemy", "attack_id": s.player.attack_id, "attack_kind": kind, "damage": damage, "hp": s.enemy.hp})

static func _enemy_hit(s: Dictionary, line_of_sight: bool, events: Array) -> void:
	var p: Dictionary = s.player
	var e: Dictionary = s.enemy
	if not line_of_sight or not _in_arc(e.position, e.aim_direction, p.position, e.reach_m, e.arc_degrees): return
	if p.invulnerable_ticks > 0:
		events.append({"kind": "dodged", "attack_id": e.attack_id})
		return
	var guarded = p.phase == "guard" and p.defend_held and _in_arc(p.position, p.facing, e.position, 100.0, s.stats.defense.arc_degrees)
	if guarded and s.stats.defense.counter_enabled and not p.guard_window_spent and p.guard_age_ticks <= _ticks(s.stats.defense.counter_window_seconds):
		p.guard_window_spent = true
		p.guard_rearm_ticks = GUARD_REARM_TICKS
		p.haste_ticks = _ticks(s.stats.defense.counter_haste_seconds) if s.stats.defense.counter_haste_seconds > 0 else 0
		events.append({"kind": "counter", "attack_id": e.attack_id})
		_start_attack(s, "counter", events)
		return
	var damage = ceili(float(e.damage) * (1.0 - float(s.stats.defense.damage_reduction))) if guarded else int(e.damage)
	p.hp = maxi(0, int(p.hp) - damage)
	if guarded:
		events.append({"kind": "blocked", "attack_id": e.attack_id, "damage": damage, "hp": p.hp})
	else:
		_cancel_inputs(s)
		_set_phase(p, "hurt", 9)
		events.append({"kind": "hit", "source": "enemy", "target": "player", "attack_id": e.attack_id, "attack_kind": "normal", "damage": damage, "hp": p.hp})
	_hitstop(s, 0.035)

static func _hitstop(s: Dictionary, seconds: float) -> void:
	var used = 0
	for entry in s.hitstop_log: used += int(entry.amount)
	var amount = mini(maxi(0, roundi(seconds * TICK_RATE)), mini(floori(float(s.stats.effects.max_hitstop_per_attack_seconds) * TICK_RATE), floori(float(s.stats.effects.max_hitstop_per_second_seconds) * TICK_RATE) - used))
	if amount <= 0: return
	s.hitstop_ticks = maxi(int(s.hitstop_ticks), amount)
	s.hitstop_log.append({"tick": s.sim_tick, "amount": amount})

static func _cancel_inputs(s: Dictionary) -> void:
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
	s.player.haste_ticks = 0
	s.hitstop_ticks = 0
	s.status = "ended"
	s.end_reason = reason
	if s.player.hp <= 0: _set_phase(s.player, "dead", 1)
	if s.enemy.hp <= 0: _set_phase(s.enemy, "dead", 1)
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
	if s.size() != 12: return false
	for key in ["schema", "run_id", "tick", "sim_tick", "status", "end_reason", "stats", "hitstop_ticks", "hitstop_log", "last_frame_hash", "player", "enemy"]:
		if not s.has(key): return false
	if s.schema != 1 or not s.run_id is String or s.run_id.is_empty() or s.run_id.length() > 120: return false
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
	if p.size() != 18 or e.size() != 14: return false
	if not _actor(p, PLAYER_PHASES, 100) or not _actor(e, ENEMY_PHASES, 60): return false
	if not _vector(p.get("facing"), true) or not _vector(e.get("aim_direction"), true): return false
	for key in ["attack_held", "defend_held", "guard_window_spent", "hit_done"]:
		if not p.get(key) is bool: return false
	for key in ["charge_ticks", "guard_age_ticks", "dodge_cooldown", "invulnerable_ticks", "haste_ticks", "guard_rearm_ticks"]:
		if not _integer(p.get(key), 0, MAX_TICKS): return false
	if p.invulnerable_ticks > 8 or p.dodge_cooldown > 48 or p.guard_rearm_ticks > GUARD_REARM_TICKS or not p.get("attack_kind") in ["normal", "charge", "counter"]: return false
	if not e.get("hit_done") is bool or e.get("reach_m") != 1.65 or e.get("arc_degrees") != 80.0 or e.get("damage") != 12: return false
	return e.get("telegraph_ticks") == 36 and e.get("active_ticks") == 6 and e.get("recovery_ticks") == 42

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
	return d.get("counter_enabled") is bool and e.get("max_hitstop_per_attack_seconds") == 0.07 and e.get("max_hitstop_per_second_seconds") == 0.12 and e.get("invulnerability_seconds") == 0.0

static func _valid_frame(f: Dictionary) -> bool:
	if f.size() != INPUT_KEYS.size(): return false
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
