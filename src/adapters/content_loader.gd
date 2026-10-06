extends RefCounted
static func load_chapter() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://content/chapter01.json"))
	if not data is Dictionary: return {"error": "章节数据无法读取"}
	for id in data:
		var n = data[id]
		if not n is Dictionary or not n.get("text") is String or n.text.is_empty() or not n.get("speaker") in ["star", "shen", "xu", "qi", "narrator"]: return {"error": "对白格式错误：" + id}
		if n.get("next", "") != "" and not data.has(n.next): return {"error": "对白引用缺失：" + id}
		if not n.get("expression", "calm") in ["calm", "smile", "wary", "hurt", "angry"]: return {"error": "表情无效：" + id}
		for c in n.get("choices", []):
			if not c is Dictionary or not c.get("id") is String or not c.get("text") is String or not data.has(c.get("next")): return {"error": "选项引用缺失：" + id}
		for k in n.get("effect", {}):
			if not k in ["stage", "flag"]: return {"error": "非法效果：" + id}
	return {"nodes": data}
