extends SceneTree
const Content = preload("res://src/adapters/content_loader.gd")
var checks = 0
var failures: Array = []
func _initialize() -> void:
	var loaded = Content.load_chapter()
	check(loaded.get("ok", false), "chapter loads")
	if not loaded.get("ok", false):
		printerr(loaded)
		quit(1)
		return
	var nodes: Dictionary = loaded.nodes
	check(nodes.size() == 75, "75 reviewed dialogue nodes retained")
	var tests = [
		["dangling next", "g1", "next", "missing"],
		["blank text", "g1", "text", "  "],
		["unknown speaker", "g1", "speaker", "stranger"],
		["bad mood", "g1", "expression", "none"],
		["script injection field", "g1", "script", "res://evil.gd"],
		["illegal effect", "g1", "effect", {"reward": "medicine"}],
		["effect wrong location", "g1", "effect", {"flag": "CH01_COMPLETE"}],
		["bad effect type", "g1", "effect", []],
		["bad choice type", "g1", "choices", {}],
		["missing scene", "g1", "scene", "other"],
		["no reachable exit", "g6", "next", "g1"],
		["cross-scene edge", "g6", "next", "r1"]]
	for test in tests:
		var changed = nodes.duplicate(true)
		changed[test[1]][test[2]] = test[3]
		check(not Content.validate(changed).get("ok", false), test[0])
	var changed = nodes.duplicate(true)
	changed.m5.choices[1].id = changed.m5.choices[0].id
	check(not Content.validate(changed).get("ok", false), "duplicate option ID")
	changed = nodes.duplicate(true)
	changed.m5.choices[0].next = "missing"
	check(not Content.validate(changed).get("ok", false), "dangling option")
	changed = nodes.duplicate(true)
	changed["orphan"] = nodes.g1.duplicate(true)
	check(not Content.validate(changed).get("ok", false), "unreachable node")
	changed = nodes.duplicate(true)
	changed.g2 = 42
	check(not Content.validate(changed).get("ok", false), "referenced malformed node rejected without runtime failure")
	changed = nodes.duplicate(true)
	changed.erase("g1")
	check(not Content.validate(changed).get("ok", false), "missing root")
	var characters: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters.json"))
	check(characters is Dictionary and characters.size() == 4, "four characters")
	var expected = {"cen_xingyao": 26, "shen_yanzhou": 32, "xu_zhiwei": 33, "qi_lan": 29}
	for id in expected:
		check(characters[id].age == expected[id] and characters[id].age >= 18, "adult age " + id)
	print("CONTENT: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
