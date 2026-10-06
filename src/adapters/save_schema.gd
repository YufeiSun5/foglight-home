extends RefCounted
## Explicit migration of the unaccepted PR #1 format; never drops story choices.
static func migrate(input: Dictionary) -> Dictionary:
	var schema: Variant = input.get("schema", 0)
	if not (schema is int or schema is float) or not is_finite(float(schema)) or schema != floor(float(schema)):
		return {"ok": false, "error": "存档 schema 无效"}
	if schema > 3: return {"ok": false, "error": "这是较新版本的存档，已保留原文件", "blocked_version": true}
	if schema == 3:
		if input.get("content_version") != "chapter01-cloud-1": return {"ok": false, "error": "未知剧情版本，已保留原文件", "blocked_version": true}
		return {"ok": true, "state": _normalize(input), "migrated": false}
	if schema==2:
		if input.get("content_version")!="chapter01-cloud-1":return {"ok":false,"error":"未知剧情版本，已保留原文件","blocked_version":true}
		if input.get("world")!={"scene_id":"FOG_HARBOR","spawn_id":"PLAYER_ANCHOR"}:return {"ok":false,"error":"旧版场景锚点无效"}
		var upgraded=input.duplicate(true)
		upgraded.schema=3
		_upgrade_cabin_anchor(upgraded)
		return {"ok":true,"state":_normalize(upgraded),"migrated":true}
	if schema != 1: return {"ok": false, "error": "没有此存档版本的迁移规则"}
	var n = input.duplicate(true)
	var old: Variant = n.get("appearance")
	if not old is Dictionary or not n.get("node") is String: return {"ok": false, "error": "旧版存档结构无效"}
	var colors = {"blue": "blue", "cream": "cream", "green": "green", "wine": "indigo"}
	var bottoms = {"work": "trousers", "wide": "trousers", "culottes": "culottes", "pleated": "short_skirt", "long_skirt": "long_skirt"}
	if not colors.has(old.get("color")) or not bottoms.has(old.get("bottom")): return {"ok": false, "error": "旧版衣装不可识别"}
	n.appearance = {"coat_color": colors[old.color], "bottom_id": bottoms[old.bottom]}
	n.schema = 3
	n.content_version = "chapter01-cloud-1"
	n.resume_node = ""
	n.mode = "exploration" if n.node == "" else ("optional" if n.node.begins_with("mirror") or n.node.begins_with("talk_") else "story")
	n.story_time = {"chapter_id": "CH01", "day_index": 1, "time_slot": "night"}
	n.world = {"scene_id": "FOG_HARBOR", "spawn_id": "PLAYER_ANCHOR"}
	if not n.get("flags") is Dictionary: return {"ok": false, "error": "旧版剧情事实无效"}
	for flag in ["hrt_recognition_received", "hrt_supply_received", "family_opposition"]: n.flags[flag] = true
	n.erase("route")
	_upgrade_cabin_anchor(n)
	return {"ok": true, "state": _normalize(n), "migrated": true}

static func _upgrade_cabin_anchor(state:Dictionary)->void:
	if state.get("stage")=="cabin" and state.get("mode")=="story" and state.get("node","")!="":
		state.world={"scene_id":"PILOT_CABIN","spawn_id":"PLAYER_ANCHOR"}
		state.anchor=[0.0,2.2]

# Godot JSON parses every number as float; normalize only schema-owned integer fields.
# Arrays and Dictionaries use strict nested type equality, unlike scalar ==.
static func _normalize(input: Dictionary) -> Dictionary:
	var n = input.duplicate(true)
	for key in ["schema", "revision"]:
		if _whole(n.get(key)): n[key] = int(n[key])
	if n.get("story_time") is Dictionary and _whole(n.story_time.get("day_index")):
		n.story_time.day_index = int(n.story_time.day_index)
	if n.get("anchor") is Array:
		for index in n.anchor.size():
			if n.anchor[index] is int or n.anchor[index] is float: n.anchor[index] = float(n.anchor[index])
	if n.get("ledger") is Dictionary:
		for key in n.ledger:
			var record: Variant = n.ledger[key]
			if not record is Dictionary or not record.get("result") is Dictionary: continue
			if _whole(record.result.get("revision")): record.result.revision = int(record.result.revision)
			if record.result.get("events") is Array:
				for event in record.result.events:
					if event is Dictionary and _whole(event.get("revision")): event.revision = int(event.revision)
	return n

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 9007199254740991 and value == floor(float(value))
