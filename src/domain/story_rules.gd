extends RefCounted
## Pure rules. No engine nodes, files, or mutable authority.
const COLORS = {"blue": "708ba9", "cream": "dbceb2", "green": "658c7c", "wine": "a06468"}
const TOPS = ["shirt", "tunic"]
const COATS = ["short", "long", "none"]
const BOTTOMS = ["work", "wide", "culottes", "pleated", "long_skirt"]
const STAGES = ["gate", "meet", "repair", "cabin", "depart", "complete"]

static func fresh() -> Dictionary:
	return {"schema": 1, "revision": 0, "stage": "gate", "node": "g1", "flags": {}, "appearance": {"top": "shirt", "coat": "short", "color": "blue", "bottom": "work"}, "journal": [], "choices": {}, "ledger": {}, "anchor": [-7.0, 4.0], "route": {}}

static func valid(s: Dictionary, nodes: Dictionary) -> bool:
	if s.get("schema") != 1 or not s.get("revision") is float and not s.get("revision") is int:
		return false
	if not s.get("stage") in STAGES or not s.get("node") is String or not s.get("flags") is Dictionary or not s.get("ledger") is Dictionary or not s.get("choices") is Dictionary or not s.get("journal") is Array or not s.get("route") is Dictionary:
		return false
	if s.node != "" and not nodes.has(s.node):
		return false
	var a = s.get("appearance", {})
	if not a is Dictionary or not a.get("top") in TOPS or not a.get("coat") in COATS or not COLORS.has(a.get("color")) or not a.get("bottom") in BOTTOMS:
		return false
	var anchor = s.get("anchor", [])
	return anchor is Array and anchor.size() == 2 and (anchor[0] is float or anchor[0] is int) and (anchor[1] is float or anchor[1] is int) and absf(anchor[0]) < 25 and absf(anchor[1]) < 25

static func reduce(s: Dictionary, action: String, p: Dictionary, nodes: Dictionary) -> Dictionary:
	var n = s.duplicate(true)
	match action:
		"choose":
			if n.node == "" or n.node != p.get("node") or not nodes.has(n.node):
				return {"error": "旧对白已结束"}
			var line: Dictionary = nodes[n.node]
			var options: Array = line.get("choices", [])
			var next: String = line.get("next", "")
			if not options.is_empty():
				var idx = p.get("index", -1)
				if not idx is int or idx < 0 or idx >= options.size():
					return {"error": "选项无效"}
				var choice: Dictionary = options[idx]
				n.choices[n.node] = choice.id
				next = choice.next
				n.journal.append("岑星遥：" + choice.text)
			n.journal.append(line.speaker + "：" + line.text)
			var effect: Dictionary = line.get("effect", {})
			if effect.has("stage"):
				n.stage = effect.stage
			if effect.has("flag"):
				n.flags[effect.flag] = true
			n.node = next
		"begin":
			if n.node != "": return {"error": "先结束当前对话"}
			var target: String = p.get("target", "")
			var starts = {"meet": "m1", "repair": "r1", "cabin": "c1", "depart": "d1"}
			if starts.has(n.stage) and target == n.stage:
				n.node = starts[n.stage]
			elif target == "mirror": n.node = "mirror1"
			elif target in ["shen", "xu", "qi", "board", "bag"]: n.node = "talk_" + target
			else: return {"error": "现在可以自由走走"}
		"outfit":
			for k in ["top", "coat", "color", "bottom"]:
				if p.has(k): n.appearance[k] = p[k]
		"anchor":
			n.anchor = p.get("position", n.anchor).duplicate()
		"route_start":
			if not n.route.is_empty() or n.node != "": return {"error": "当前不能出航"}
			n.route = {"seed": p.get("seed", 1), "step": 0, "warmth": 3, "boon": "无", "events": []}
		"route_pick":
			if n.route.is_empty(): return {"error": "尚未出航"}
			if p.get("step") != n.route.step: return {"error": "旧路线选项"}
			var rest: bool = p.get("rest", false)
			n.route.warmth += 1 if rest else -1
			n.route.step += 1
			n.route.boon = "顺风" if rest else "远望"
			n.route.events.append("休息听潮" if rest else "迎风远望")
		"route_end":
			n.route = {}
		_: return {"error": "未知命令"}
	if not valid(n, nodes): return {"error": "状态校验失败"}
	n.revision = int(n.revision) + 1
	return {"state": n}
