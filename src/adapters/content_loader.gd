extends RefCounted
## Data-only loader. All entry points, references and effects are allowlisted.
const ROOTS = ["g1", "m1", "r1", "c1", "d1", "mirror1", "talk_shen", "talk_xu", "talk_qi", "talk_board", "talk_bag"]
const ROOT_SCENES = {"g1": "gate", "m1": "meet", "r1": "repair", "c1": "cabin", "d1": "depart"}
const SCENES = ["gate", "meet", "repair", "cabin", "depart", "optional"]
const STAGE_EFFECTS = {"g6": "meet", "m6": "repair", "r20": "cabin", "c15": "depart", "d8": "complete"}
const FLAG_EFFECTS = {"r13": "relit", "d8": "CH01_COMPLETE"}

static func load_chapter(path: String = "res://content/chapter01.json") -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "章节文件不存在"}
	var parsed = JSON.new()
	if parsed.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"ok": false, "error": "章节 JSON 无效：" + parsed.get_error_message()}
	if not parsed.data is Dictionary: return {"ok": false, "error": "章节数据无法读取"}
	return validate(parsed.data)

static func validate(data: Dictionary) -> Dictionary:
	if data.is_empty(): return {"ok": false, "error": "章节为空"}
	var choice_ids: Dictionary = {}
	for id in data:
		var n: Variant = data[id]
		if not id is String or id.is_empty() or not n is Dictionary: return _bad("对白 ID", str(id))
		for field in n:
			if not field in ["speaker", "text", "expression", "next", "choices", "effect", "scene"]: return _bad("非法字段", id)
		if not n.get("text") is String or n.text.strip_edges().is_empty() or not n.get("speaker") in ["star", "shen", "xu", "qi", "narrator"]: return _bad("对白格式", id)
		if not n.get("scene") in SCENES or not n.get("next") is String: return _bad("场景或出口", id)
		if n.next != "" and not data.has(n.next): return _bad("对白引用缺失", id)
		if not n.get("expression", "calm") in ["calm", "smile", "wary", "hurt", "angry"]: return _bad("表情无效", id)
		if not n.get("choices", []) is Array or not n.get("effect", {}) is Dictionary: return _bad("选项或效果格式", id)
		if not n.get("choices", []).is_empty() and n.next != "": return _bad("分支出口重复", id)
		for choice in n.get("choices", []):
			if not choice is Dictionary or choice.size() != 3 or not choice.get("id") is String or choice.id.is_empty() or not choice.get("text") is String or choice.text.strip_edges().is_empty() or not data.has(choice.get("next")): return _bad("选项引用或文本", id)
			if choice_ids.has(choice.id): return _bad("选项 ID 重复", choice.id)
			choice_ids[choice.id] = true
		for field in n.get("effect", {}):
			if field == "stage" and STAGE_EFFECTS.get(id) == n.effect[field]: continue
			if field == "flag" and FLAG_EFFECTS.get(id) == n.effect[field]: continue
			return _bad("非法效果", id)
	for id in data:
		for target in _edges(data[id]):
			if data[target].scene != data[id].scene: return _bad("跨场对白引用", id)
	for id in STAGE_EFFECTS:
		if not data.has(id) or data[id].get("effect", {}).get("stage") != STAGE_EFFECTS[id]: return _bad("缺少章节收束", id)
	for id in FLAG_EFFECTS:
		if not data.has(id) or data[id].get("effect", {}).get("flag") != FLAG_EFFECTS[id]: return _bad("缺少演出事实", id)
	for root_id in ROOTS:
		if not data.has(root_id) or data[root_id].scene != ROOT_SCENES.get(root_id, "optional"): return _bad("入口场景不符", root_id)
	var seen: Dictionary = {}
	var pending: Array = ROOTS.duplicate()
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if not data.has(id): return _bad("入口缺失", id)
		if seen.has(id): continue
		seen[id] = true
		pending.append_array(_edges(data[id]))
	if seen.size() != data.size(): return _bad("有不可达对白", str(data.size() - seen.size()))
	# Every node must reach a terminal; intentional loops with an exit remain legal.
	var exits: Dictionary = {}
	for id in data:
		if _edges(data[id]).is_empty(): exits[id] = true
	for _pass in data.size():
		var changed = false
		for id in data:
			if exits.has(id): continue
			for target in _edges(data[id]):
				if exits.has(target):
					exits[id] = true
					changed = true
					break
		if not changed: break
	if exits.size() != data.size(): return _bad("对白没有可达出口", "graph")
	return {"ok": true, "nodes": data.duplicate(true)}

static func _edges(node: Dictionary) -> Array:
	var result: Array = []
	if node.get("next", "") != "": result.append(node.next)
	for choice in node.get("choices", []): result.append(choice.next)
	return result
static func _bad(reason: String, id: String) -> Dictionary:
	return {"ok": false, "error": reason + "：" + id}
