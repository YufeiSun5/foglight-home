extends RefCounted
## Pure, optional, run-local encounter rules; no literal tower building is required. The application owns commits and run identities.
## No combat simulation, input handling, persistence, or story-state authority.
const SCHEMA = 1
const MAX_STAGES = 24
const MAX_CARDS = 12
const MAX_COMMANDS = MAX_STAGES * 2 + 1
const RNG_MODULUS = 2147483647
const OFFER_SIZE = 3
const MODIFIER_LIMITS = {
	"normal_rate": 0.30, "normal_reach": 0.15, "normal_trails": 1,
	"charge_rate": 0.30, "charge_reach": 0.15, "charge_trails": 1,
	"ranged_charge": 1, "snap_charge": 1, "chain_charge": 1, "counter_style": 1,
}
const STATE_KEYS = ["schema", "run_id", "epoch", "catalog_hash", "seed", "rng_state",
	"revision", "phase", "stage", "max_stages", "ranks", "offer", "selections", "ledger", "end_reason"]

static func validate_catalog(data: Variant) -> Dictionary:
	if not data is Dictionary or not _keys(data, ["schema", "cards"]) or data.schema != SCHEMA:
		return _error("invalid_catalog")
	if not data.cards is Array or data.cards.is_empty() or data.cards.size() > MAX_CARDS:
		return _error("invalid_cards")
	var cards: Dictionary = {}
	for card in data.cards:
		if not _valid_card(card) or cards.has(card.id): return _error("invalid_card")
		cards[card.id] = card.duplicate(true)
		cards[card.id].max_rank = int(card.max_rank)
	return {"ok": true, "cards": cards}

static func fresh(run_id: String, epoch: int, seed_value: int, cards: Dictionary, stages: int = 8) -> Dictionary:
	if not _token(run_id, 120) or epoch < 1 or epoch > 2147483647 or seed_value < 0 or seed_value >= RNG_MODULUS - 1:
		return _error("invalid_run_identity")
	if not _valid_cards(cards) or stages < 1 or stages > MAX_STAGES: return _error("invalid_run_config")
	var state = {"schema": SCHEMA, "run_id": run_id, "epoch": epoch,
		"catalog_hash": _catalog_hash(cards), "seed": seed_value, "rng_state": seed_value + 1,
		"revision": 0, "phase": "stage_active", "stage": 1, "max_stages": stages,
		"ranks": {}, "offer": [], "selections": [], "ledger": {}, "end_reason": ""}
	return {"ok": true, "state": state}

static func make_command(s: Dictionary, id: String, action: String, payload: Dictionary = {}, source: String = "player") -> Dictionary:
	return {"id": id, "source": source, "run_id": s.get("run_id"), "epoch": s.get("epoch"),
		"revision": s.get("revision"), "action": action, "payload": payload.duplicate(true)}

static func reduce(s: Dictionary, command: Dictionary, cards: Dictionary) -> Dictionary:
	if not valid(s, cards): return _error("invalid_state")
	if not _keys(command, ["id", "source", "run_id", "epoch", "revision", "action", "payload"]):
		return _error("invalid_command")
	if command.run_id != s.run_id or command.epoch != s.epoch: return _error("stale_run")
	if not _token(command.id, 160) or not command.source in ["player", "application"] or not command.action is String or not command.payload is Dictionary or not _whole(command.revision, 0, MAX_COMMANDS):
		return _error("invalid_command")
	if not _valid_payload(command.action, command.payload): return _error("invalid_payload")
	var fingerprint = JSON.stringify(command, "", true).sha256_text()
	if s.ledger.has(command.id):
		var record: Dictionary = s.ledger[command.id]
		if record.fingerprint != fingerprint: return _error("command_id_conflict")
		return {"ok": true, "state": s.duplicate(true), "result": record.result.duplicate(true), "events": [], "replay": true}
	if command.revision != s.revision: return _error("stale_revision")
	if s.phase == "ended": return _error("run_ended")
	if s.ledger.size() >= MAX_COMMANDS: return _error("command_limit")
	var n = s.duplicate(true)
	var events: Array = []
	match command.action:
		"choose":
			if command.source != "player": return _error("invalid_source")
			if n.phase != "awaiting_choice" or command.payload.stage != n.stage: return _error("stage_not_choosing")
			var card_id: String = command.payload.card_id
			if not card_id in n.offer or not card_id in _eligible(n.ranks, cards): return _error("card_not_offered")
			n.ranks[card_id] = int(n.ranks.get(card_id, 0)) + 1
			n.selections.append({"stage": n.stage, "card_id": card_id})
			n.offer = []
			n.phase = "stage_active"
			events.append({"kind": "tower_card_selected", "card_id": card_id, "stage": n.stage})
		"clear_stage":
			# Only a future application combat outcome may issue this, never the card UI.
			if command.source != "application": return _error("invalid_source")
			if n.phase != "stage_active" or command.payload.stage != n.stage: return _error("stage_not_active")
			events.append({"kind": "tower_stage_cleared", "stage": n.stage})
			if n.stage == n.max_stages:
				_end(n, "completed", events)
			else:
				n.stage += 1
				_deal(n, cards)
				events.append({"kind": "tower_stage_opened", "stage": n.stage, "offer": n.offer.duplicate()})
		"exit", "fail":
			if command.source != ("player" if command.action == "exit" else "application"): return _error("invalid_source")
			_end(n, "exited" if command.action == "exit" else "failed", events)
		_: return _error("unknown_action")
	n.revision += 1
	for index in events.size():
		events[index]["event_id"] = "%s:%d:%s:%d" % [n.run_id, n.epoch, command.id, index]
		events[index]["revision"] = n.revision
	var result = {"ok": true, "revision": n.revision, "action": command.action, "stage": n.stage, "end_reason": n.end_reason}
	n.ledger[command.id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	if not valid(n, cards): return _error("invalid_candidate")
	return {"ok": true, "state": n, "result": result, "events": events, "replay": false}

static func stats(s: Dictionary, cards: Dictionary) -> Dictionary:
	if not valid(s, cards): return _error("invalid_state")
	return {"ok": true, "stats": _stats(s.ranks, cards)}

static func preview(s: Dictionary, card_id: String, cards: Dictionary) -> Dictionary:
	if not valid(s, cards): return _error("invalid_state")
	if s.phase != "awaiting_choice" or not card_id in s.offer: return _error("card_not_offered")
	var ranks = s.ranks.duplicate(true)
	var before = _stats(ranks, cards)
	ranks[card_id] = int(ranks.get(card_id, 0)) + 1
	var after = _stats(ranks, cards)
	var changes: Array = []
	for section in ["normal", "charge", "defense", "effects"]:
		for field in before[section]:
			if before[section][field] != after[section][field]:
				changes.append({"stat": section + "." + field, "before": before[section][field], "after": after[section][field]})
	return {"ok": true, "card": cards[card_id].duplicate(true), "rank_before": int(s.ranks.get(card_id, 0)),
		"rank_after": ranks[card_id], "before": before, "after": after, "changes": changes}

static func valid(s: Dictionary, cards: Dictionary) -> bool:
	if not _valid_cards(cards) or not _keys(s, STATE_KEYS): return false
	if s.schema != SCHEMA or not _token(s.run_id, 120) or not _whole(s.epoch, 1, 2147483647) or s.catalog_hash != _catalog_hash(cards): return false
	if not _whole(s.seed, 0, RNG_MODULUS - 2) or not _whole(s.rng_state, 1, RNG_MODULUS - 1): return false
	if not _whole(s.max_stages, 1, MAX_STAGES) or not _whole(s.stage, 1, int(s.max_stages)) or not _whole(s.revision, 0, MAX_COMMANDS): return false
	if not s.phase in ["awaiting_choice", "stage_active", "ended"] or not s.end_reason in ["", "exited", "failed", "completed"]: return false
	if (s.phase == "ended") != (s.end_reason != "") or (s.end_reason == "completed" and s.stage != s.max_stages): return false
	if not s.ranks is Dictionary or s.ranks.size() > cards.size() or not s.offer is Array or s.offer.size() > OFFER_SIZE: return false
	if not s.selections is Array or s.selections.size() > int(s.stage) or not s.ledger is Dictionary or s.ledger.size() != int(s.revision): return false
	var expected_ranks: Dictionary = {}
	var last_stage = 0
	for selection in s.selections:
		if not selection is Dictionary or not _keys(selection, ["stage", "card_id"]): return false
		if not _whole(selection.stage, last_stage + 1, int(s.stage)) or not selection.card_id is String or not cards.has(selection.card_id): return false
		last_stage = int(selection.stage)
		expected_ranks[selection.card_id] = int(expected_ranks.get(selection.card_id, 0)) + 1
		if expected_ranks[selection.card_id] > cards[selection.card_id].max_rank: return false
	if _stats(expected_ranks, cards).charge.projectile_count > 0 and _stats(expected_ranks, cards).charge.chain_max_targets > 0: return false
	if s.phase == "ended":
		if not s.ranks.is_empty() or not s.offer.is_empty(): return false
	else:
		if s.ranks != expected_ranks: return false
		for id in s.ranks:
			if not cards.has(id) or not _whole(s.ranks[id], 1, int(cards[id].max_rank)): return false
		var eligible = _eligible(s.ranks, cards)
		if s.phase == "awaiting_choice":
			if last_stage == int(s.stage) or s.offer.is_empty() or s.offer.size() != mini(OFFER_SIZE, eligible.size()): return false
			var seen: Dictionary = {}
			for id in s.offer:
				if not id is String or not id in eligible or seen.has(id): return false
				seen[id] = true
		else:
			if not s.offer.is_empty() or (int(s.stage) > 1 and last_stage != int(s.stage) and not eligible.is_empty()): return false
	var revisions: Dictionary = {}
	for id in s.ledger:
		var entry: Variant = s.ledger[id]
		if not _token(id, 160) or not entry is Dictionary or not _keys(entry, ["fingerprint", "result"]): return false
		if not _hex_hash(entry.fingerprint) or not entry.result is Dictionary: return false
		var receipt: Dictionary = entry.result
		if not _keys(receipt, ["ok", "revision", "action", "stage", "end_reason"]) or receipt.ok != true: return false
		if not _whole(receipt.revision, 1, int(s.revision)) or revisions.has(receipt.revision) or not _whole(receipt.stage, 1, int(s.stage)): return false
		if not receipt.action in ["choose", "clear_stage", "exit", "fail"] or not receipt.end_reason in ["", "exited", "failed", "completed"]: return false
		revisions[receipt.revision] = true
	return true

static func _stats(ranks: Dictionary, cards: Dictionary) -> Dictionary:
	var modifiers: Dictionary = {}
	for key in MODIFIER_LIMITS: modifiers[key] = 0.0
	var ids = ranks.keys()
	ids.sort()
	for id in ids:
		for key in cards[id].modifiers:
			modifiers[key] += float(cards[id].modifiers[key]) * int(ranks[id])
	var ranged = modifiers.ranged_charge > 0.0
	var chain = modifiers.chain_charge > 0.0
	var counter_rank = clampi(int(modifiers.counter_style), 0, 3)
	var normal_trails = clampi(1 + int(modifiers.normal_trails), 1, 3)
	var charge_trails = clampi(1 + int(modifiers.charge_trails), 1, 3)
	var ranged_reach = clampf(5.5 + modifiers.charge_reach, 5.5, 6.0) if ranged else 0.0
	return {
		"normal": {"enabled": true, "mode": "melee", "attack_rate_hz": clampf(1.5 * (1.0 + modifiers.normal_rate), 1.5, 2.7),
			"reach_m": clampf(1.25 + modifiers.normal_reach, 1.25, 1.70), "trail_layers": normal_trails},
		"charge": {"enabled": true, "mode": "ranged_charge" if ranged else ("chain_charge" if chain else "melee_charge"), "requires_charge": true,
			"hold_seconds": clampf(0.90 * (0.12 if modifiers.snap_charge > 0.0 else 1.0) / (1.0 + modifiers.charge_rate), 0.06, 0.90), "recovery_seconds": 0.55,
			"melee_reach_m": clampf(1.50 + modifiers.charge_reach, 1.50, 2.00), "trail_layers": charge_trails,
			"projectile_reach_m": ranged_reach, "projectile_speed_mps": 10.0 if ranged else 0.0,
			"projectile_count": 1 if ranged else 0, "projectile_pierce": 1 if ranged else 0,
			"projectile_max_targets": 2 if ranged else 0, "projectile_lifetime_seconds": ranged_reach / 10.0 if ranged else 0.0,
			"chain_max_targets": 3 if chain else 0, "chain_search_radius_m": 3.0 if chain else 0.0,
			"chain_max_step_m": 2.0 if chain else 0.0, "chain_duration_seconds": 0.60 if chain else 0.0},
		"defense": {"enabled": true, "damage_reduction": 0.65, "arc_degrees": 120.0,
			"counter_enabled": true, "counter_window_seconds": 0.10 + 0.02 * counter_rank,
			"counter_damage_multiplier": 1.25 + 0.25 * counter_rank,
			"counter_reach_m": 1.25 + 0.10 * counter_rank,
			"counter_haste_multiplier": 1.0 + 0.10 * counter_rank,
			"counter_haste_seconds": 1.0 if counter_rank > 0 else 0.0},
		"effects": {"max_live_emitters": 8, "max_live_particles": 48, "particles_per_hit": 8,
			"normal_hitstop_seconds": 0.035, "charge_hitstop_seconds": 0.055,
			"max_hitstop_per_attack_seconds": 0.07, "max_hitstop_per_second_seconds": 0.12,
			"invulnerability_seconds": 0.0},
	}

static func _eligible(ranks: Dictionary, cards: Dictionary) -> Array:
	var ids = cards.keys()
	ids.sort()
	var eligible: Array = []
	var before = _stats(ranks, cards)
	for id in ids:
		if int(ranks.get(id, 0)) >= int(cards[id].max_rank): continue
		# Shape conversions are mutually exclusive within one run; never silently override.
		var mods: Dictionary = cards[id].modifiers
		if mods.has("ranged_charge") and before.charge.mode == "chain_charge": continue
		if mods.has("chain_charge") and before.charge.mode == "ranged_charge": continue
		var next = ranks.duplicate(true)
		next[id] = int(next.get(id, 0)) + 1
		if _stats(next, cards) != before: eligible.append(id)
	return eligible

static func _deal(s: Dictionary, cards: Dictionary) -> void:
	var pool = _eligible(s.ranks, cards)
	s.offer = []
	for _index in mini(OFFER_SIZE, pool.size()):
		var draw = _draw(int(s.rng_state), pool.size())
		s.rng_state = draw.state
		s.offer.append(pool[draw.index])
		pool.remove_at(draw.index)
	s.phase = "stage_active" if s.offer.is_empty() else "awaiting_choice"

static func _draw(state: int, bound: int) -> Dictionary:
	# Park-Miller integer PRNG, rejection sampling avoids modulo bias. No global RNG.
	var limit = (RNG_MODULUS - 1) - ((RNG_MODULUS - 1) % bound)
	for _attempt in bound:
		state = (state * 48271) % RNG_MODULUS
		var sample = state - 1
		if sample < limit: return {"state": state, "index": sample % bound}
	return {}

static func _end(s: Dictionary, reason: String, events: Array) -> void:
	s.phase = "ended"
	s.end_reason = reason
	s.offer = []
	s.ranks = {}
	events.append({"kind": "tower_run_ended", "reason": reason, "stage": s.stage})

static func _valid_payload(action: String, payload: Dictionary) -> bool:
	match action:
		"choose": return _keys(payload, ["stage", "card_id"]) and _whole(payload.stage, 1, MAX_STAGES) and _token(payload.card_id, 60)
		"clear_stage": return _keys(payload, ["stage"]) and _whole(payload.stage, 1, MAX_STAGES)
		"exit", "fail": return payload.is_empty()
	return false

static func _valid_cards(cards: Dictionary) -> bool:
	if cards.is_empty() or cards.size() > MAX_CARDS: return false
	for id in cards:
		if not _valid_card(cards[id]) or id != cards[id].id: return false
	return true

static func _valid_card(card: Variant) -> bool:
	if not card is Dictionary or not _keys(card, ["id", "name", "description", "style", "max_rank", "modifiers"]): return false
	if not _token(card.id, 60) or not card.name is String or card.name.strip_edges().is_empty() or card.name.length() > 80: return false
	if not card.description is String or card.description.strip_edges().is_empty() or card.description.length() > 300: return false
	if not card.style in ["normal", "charge", "counter", "mixed"] or not _whole(card.max_rank, 1, 3): return false
	if not card.modifiers is Dictionary or card.modifiers.is_empty() or card.modifiers.size() > 3: return false
	for key in card.modifiers:
		var value: Variant = card.modifiers[key]
		if not MODIFIER_LIMITS.has(key) or not (value is int or value is float) or not is_finite(float(value)): return false
		if value < 0.01 or value > MODIFIER_LIMITS[key]: return false
		if key in ["normal_trails", "charge_trails", "ranged_charge", "snap_charge", "chain_charge", "counter_style"] and not _whole(value, 1, 1): return false
		if card.style == "normal" and not key.begins_with("normal_"): return false
		if card.style == "charge" and not (key.begins_with("charge_") or key in ["ranged_charge", "snap_charge", "chain_charge"]): return false
		if card.style == "counter" and key != "counter_style": return false
	for exclusive in ["ranged_charge", "chain_charge", "snap_charge"]:
		if card.modifiers.has(exclusive) and (card.max_rank != 1 or card.modifiers.size() != 1 or card.style != "charge"): return false
	return true

static func _catalog_hash(cards: Dictionary) -> String: return JSON.stringify(cards, "", true).sha256_text()
static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}
static func _keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true
static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high
static func _token(value: Variant, maximum: int) -> bool:
	if not value is String or value.is_empty() or value.length() > maximum: return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:-.": return false
	return true
static func _hex_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true
