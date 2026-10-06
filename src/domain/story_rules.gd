extends RefCounted
## Pure story rules, adapted and hardened from PR #1. No nodes, IO, or authority.
const SCHEMA = 2
const CONTENT_VERSION = "chapter01-cloud-1"
const COLORS = {"blue": "708ba9", "cream": "dbceb2", "green": "658c7c", "indigo": "465673"}
const BOTTOMS = ["trousers", "culottes", "long_skirt", "short_skirt"]
const STAGES = ["gate", "meet", "repair", "cabin", "depart", "complete"]
const STARTS = {"gate": "g1", "meet": "m1", "repair": "r1", "cabin": "c1", "depart": "d1"}
const NAMES = {"star": "岑星遥", "shen": "沈砚舟", "xu": "许知微", "qi": "祁岚", "narrator": "旁白"}
const BASE_FLAGS = {"hrt_recognition_received": true, "hrt_supply_received": true, "family_opposition": true}
const FLAGS = ["relit", "CH01_COMPLETE", "hrt_recognition_received", "hrt_supply_received", "family_opposition"]

static func fresh() -> Dictionary:
	return {"schema": SCHEMA, "content_version": CONTENT_VERSION, "revision": 0,
		"stage": "gate", "node": "g1", "mode": "story", "resume_node": "", "flags": BASE_FLAGS.duplicate(),
		"appearance": {"coat_color": "blue", "bottom_id": "trousers"},
		"journal": [], "choices": {}, "ledger": {}, "anchor": [-7.0, 4.0],
		"world": {"scene_id": "FOG_HARBOR", "spawn_id": "PLAYER_ANCHOR"},
		"story_time": {"chapter_id": "CH01", "day_index": 1, "time_slot": "night"}}

static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 0 and value <= 9007199254740991

static func valid(s: Dictionary, nodes: Dictionary) -> bool:
	if s.size() != 15: return false
	if s.get("schema") != SCHEMA or s.get("content_version") != CONTENT_VERSION or not whole(s.get("revision")):
		return false
	if not s.get("stage") in STAGES or not s.get("mode") in ["story", "optional", "exploration"]:
		return false
	for key in ["flags", "ledger", "choices", "appearance", "story_time", "world"]:
		if not s.get(key) is Dictionary: return false
	for key in ["node", "resume_node"]:
		if not s.get(key) is String: return false
		if s[key] != "" and not nodes.has(s[key]): return false
	if (s.mode == "exploration") != (s.node == ""): return false
	if s.node != "" and nodes[s.node].get("scene", "") != (s.stage if s.mode == "story" else "optional"):
		return false
	if s.resume_node != "" and (s.mode == "story" or nodes[s.resume_node].get("scene", "") != s.stage): return false
	if s.world != {"scene_id": "FOG_HARBOR", "spawn_id": "PLAYER_ANCHOR"}: return false
	for flag in BASE_FLAGS:
		if s.flags.get(flag) != true: return false
	for flag in s.flags:
		if not flag in FLAGS or s.flags[flag] != true: return false
	if s.stage in ["cabin", "depart", "complete"] and not s.flags.get("relit", false): return false
	if s.flags.get("CH01_COMPLETE", false) != (s.stage == "complete"): return false
	if not COLORS.has(s.appearance.get("coat_color")) or not s.appearance.get("bottom_id") in BOTTOMS or s.appearance.size() != 2:
		return false
	if not s.get("journal") is Array or s.journal.size() > 20000: return false
	for entry in s.journal:
		if not entry is String or entry.length() > 3000: return false
	for node_id in s.choices:
		if not nodes.has(node_id) or not s.choices[node_id] is String: return false
		var found = false
		for option in nodes[node_id].get("choices", []):
			if option.id == s.choices[node_id]: found = true
		if not found: return false
	for command_id in s.ledger:
		var record: Variant = s.ledger[command_id]
		if not command_id is String or command_id.is_empty() or not record is Dictionary: return false
		if not record.get("fingerprint") is String or record.fingerprint.length() != 64: return false
		if not record.get("result") is Dictionary or record.result.get("ok") != true: return false
		if not whole(record.result.get("revision")) or record.result.revision > s.revision: return false
	var anchor: Variant = s.get("anchor")
	if not anchor is Array or anchor.size() != 2: return false
	for axis in anchor:
		if not (axis is float or axis is int) or not is_finite(float(axis)) or absf(axis) > 100: return false
	return s.story_time == {"chapter_id": "CH01", "day_index": 1, "time_slot": "night"}

static func reduce(s: Dictionary, action: String, payload: Dictionary, nodes: Dictionary) -> Dictionary:
	var n = s.duplicate(true)
	var events: Array = []
	match action:
		"choose":
			if n.node == "" or n.node != payload.get("node") or not nodes.has(n.node): return {"error": "旧对白已结束"}
			var line: Dictionary = nodes[n.node]
			var options: Array = line.get("choices", [])
			var next: String = line.get("next", "")
			n.journal.append(NAMES[line.speaker] + "：" + line.text)
			if not options.is_empty():
				var index: Variant = payload.get("index", -1)
				if not index is int or index < 0 or index >= options.size(): return {"error": "选项无效"}
				var choice: Dictionary = options[index]
				n.choices[n.node] = choice.id
				next = choice.next
				n.journal.append("岑星遥：" + choice.text)
				events.append({"kind": "choice_recorded", "object_id": choice.id})
			elif payload.get("index", -1) != -1:
				return {"error": "当前对白没有该选项"}
			var effect: Dictionary = line.get("effect", {})
			if effect.has("stage"):
				n.stage = effect.stage
				events.append({"kind": "stage_changed", "object_id": effect.stage})
			if effect.has("flag"):
				n.flags[effect.flag] = true
				events.append({"kind": "fact_recorded", "object_id": effect.flag})
			n.node = next
			if next == "": n.mode = "exploration"
		"skip":
			if n.node == "" or not nodes[n.node].get("choices", []).is_empty(): return {"error": "请先选择表达，或继续自由探索"}
			var count = 0
			while n.node != "" and nodes[n.node].get("choices", []).is_empty() and count < 150:
				var step = reduce(n, "choose", {"node": n.node}, nodes)
				if step.has("error"): return step
				n = step.state
				events.append_array(step.events)
				count += 1
			if count == 150: return {"error": "演出出口不可用"}
			n.revision = s.revision
		"begin":
			if n.node != "": return {"error": "先结束或暂放当前对话"}
			var target: Variant = payload.get("target", "")
			if not target is String: return {"error": "交互目标无效"}
			if target == "continue":
				if n.resume_node == "": return {"error": "当前没有暂放的对话"}
				n.node = n.resume_node
				n.resume_node = ""
				n.mode = "story"
			elif STARTS.has(n.stage) and target == n.stage:
				n.node = n.resume_node if n.resume_node != "" else STARTS[n.stage]
				n.resume_node = ""
				n.mode = "story"
			elif target in ["shen", "xu", "qi", "board", "bag", "mirror"]:
				n.node = "mirror1" if target == "mirror" else "talk_" + target
				n.mode = "optional"
			else: return {"error": "现在可以自由走走"}
		"suspend":
			if n.node == "": return {"error": "已经在自由探索"}
			if n.mode == "story": n.resume_node = n.node
			n.node = ""
			n.mode = "exploration"
		"outfit":
			if payload.is_empty(): return {"error": "请选择衣装"}
			for key in payload:
				if not key in ["coat_color", "bottom_id"]: return {"error": "未知衣装字段"}
				n.appearance[key] = payload[key]
			events.append({"kind": "appearance_changed", "object_id": "cen_xingyao"})
		"anchor":
			if not payload.get("position") is Array: return {"error": "位置无效"}
			if payload.position.size() != 2: return {"error": "位置无效"}
			for axis in payload.position:
				if not (axis is int or axis is float): return {"error": "位置无效"}
			n.anchor = [float(payload.position[0]), float(payload.position[1])]
		_: return {"error": "未知命令"}
	if not valid(n, nodes): return {"error": "状态校验失败"}
	n.revision = int(n.revision) + 1
	return {"state": n, "events": events}
