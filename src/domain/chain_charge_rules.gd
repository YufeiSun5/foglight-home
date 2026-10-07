extends RefCounted
## Pure finite motion plan. Combat owns damage and the single authoritative ledger.
## Scene sweeps each returned segment before supplying the sampled player position.
const LEG_TICKS = 12
const TOTAL_TICKS = 36
const MAX_TARGETS = 3
const SEARCH_RADIUS_M = 3.0
const MAX_STEP_M = 2.0
const STOP_DISTANCE_M = 0.60
const PLAYER_RADIUS_M = 0.23
const POSITION_SLOP_M = 0.00005

static func lock_target(origin: Array, targets: Array, visited: Array) -> Dictionary:
	var eligible: Array = []
	for target in targets:
		if target.hp <= 0 or not target.present or not target.line_of_sight or target.id in visited: continue
		var distance = _distance(origin, target.position)
		if distance <= SEARCH_RADIUS_M: eligible.append({"id": target.id, "position": target.position.duplicate(), "distance": distance})
	eligible.sort_custom(func(a, b): return a.id < b.id if a.distance == b.distance else a.distance < b.distance)
	if eligible.is_empty() or visited.size() >= MAX_TARGETS: return {}
	var chosen: Dictionary = eligible[0]
	var direction = Vector2(float(chosen.position[0]) - float(origin[0]), float(chosen.position[1]) - float(origin[1])).normalized()
	if direction.is_zero_approx(): direction = Vector2(0, -1)
	var travel = minf(MAX_STEP_M, maxf(0.0, float(chosen.distance) - STOP_DISTANCE_M))
	return {"target_id": chosen.id, "origin": origin.duplicate(),
		"destination": [float(origin[0]) + direction.x * travel, float(origin[1]) + direction.y * travel],
		"direction": [direction.x, direction.y]}

static func begin(attack_id: int, origin: Array, targets: Array) -> Dictionary:
	var leg = lock_target(origin, targets, [])
	if leg.is_empty(): return {}
	return {"attack_id": attack_id, "elapsed_ticks": 0, "leg_tick": 0, "target_id": leg.target_id,
		"visited": [leg.target_id], "origin": leg.origin, "destination": leg.destination,
		"direction": leg.direction, "hitstop_used_ticks": 0}

static func next_leg(chain: Dictionary, origin: Array, targets: Array) -> bool:
	var leg = lock_target(origin, targets, chain.visited)
	if leg.is_empty(): return false
	for key in ["target_id", "origin", "destination", "direction"]: chain[key] = leg[key]
	chain.visited.append(leg.target_id)
	chain.leg_tick = 0
	return true

static func sweep(chain: Dictionary, player_position: Array) -> Dictionary:
	if chain.is_empty(): return {}
	var fraction = float(int(chain.leg_tick) + 1) / LEG_TICKS
	return {"attack_id": chain.attack_id, "from": player_position.duplicate(),
		"to": [lerpf(float(chain.origin[0]), float(chain.destination[0]), fraction), lerpf(float(chain.origin[1]), float(chain.destination[1]), fraction)],
		"radius_m": PLAYER_RADIUS_M}

static func sampled_position_matches(sweep_value: Dictionary, position: Array, wall_fraction: Variant) -> bool:
	var fraction = 1.0 if wall_fraction == null else float(wall_fraction)
	var expected = [lerpf(float(sweep_value.from[0]), float(sweep_value.to[0]), fraction), lerpf(float(sweep_value.from[1]), float(sweep_value.to[1]), fraction)]
	return _distance(expected, position) <= POSITION_SLOP_M

static func valid(chain: Dictionary, attack_id: int, target_ids: Array) -> bool:
	if chain.size() != 9: return false
	for key in ["attack_id", "elapsed_ticks", "leg_tick", "target_id", "visited", "origin", "destination", "direction", "hitstop_used_ticks"]:
		if not chain.has(key): return false
	if not chain.attack_id is int or chain.attack_id < 1 or chain.attack_id != attack_id: return false
	if not chain.elapsed_ticks is int or chain.elapsed_ticks < 0 or chain.elapsed_ticks >= TOTAL_TICKS: return false
	if not chain.leg_tick is int or chain.leg_tick < 0 or chain.leg_tick >= LEG_TICKS: return false
	if not chain.hitstop_used_ticks is int or chain.hitstop_used_ticks < 0 or chain.hitstop_used_ticks > 4: return false
	if not chain.target_id is String or not chain.target_id in target_ids: return false
	if not chain.visited is Array or chain.visited.is_empty() or chain.visited.size() > MAX_TARGETS: return false
	var seen: Dictionary = {}
	for id in chain.visited:
		if not id is String or not id in target_ids or seen.has(id): return false
		seen[id] = true
	if chain.visited[-1] != chain.target_id: return false
	if chain.elapsed_ticks != (chain.visited.size() - 1) * LEG_TICKS + chain.leg_tick: return false
	for key in ["origin", "destination", "direction"]:
		if not _point(chain[key]): return false
	var direction = Vector2(chain.direction[0], chain.direction[1])
	if absf(direction.length_squared() - 1.0) > 0.000001: return false
	if _distance(chain.origin, chain.destination) > MAX_STEP_M + POSITION_SLOP_M: return false
	return true

static func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)) or absf(float(component)) > 100.0: return false
	return true

static func _distance(a: Array, b: Array) -> float:
	return Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))
