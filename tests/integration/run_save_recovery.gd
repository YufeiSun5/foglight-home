extends SceneTree
const Store = preload("res://src/app/state_store.gd")
const FileSave = preload("res://src/adapters/file_save.gd")
const Rules = preload("res://src/domain/story_rules.gd")
const Content = preload("res://src/adapters/content_loader.gd")
var nodes: Dictionary
var test_root: String
var checks = 0
var failures: Array = []
var case_id = 0

func _initialize() -> void:
	var loaded = Content.load_chapter()
	if not loaded.get("ok", false):
		printerr("SAVE CONTENT BLOCKER: ", loaded.get("error", "Invalid content"))
		quit(1)
		return
	nodes = loaded.nodes
	test_root = "/tmp/foglight-save-tests-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(test_root)
	_test_roundtrip()
	_test_faults()
	_test_recovery()
	_test_versions()
	_test_migration()
	_test_barriers()
	_test_cabin_saves()
	print("SAVE: %d checks; %d failures; fixtures %s" % [checks, failures.size(), test_root])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _case() -> Dictionary:
	case_id += 1
	var path = test_root + "/case-" + str(case_id)
	var port = FileSave.new(path)
	var store = Store.new(nodes, port)
	return {"path": path, "port": port, "store": store}

func _write(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _envelope(state: Dictionary, sequence: int = 50, format_version: int = 1) -> String:
	var payload = JSON.stringify(state)
	return JSON.stringify({"format": format_version, "sequence": sequence, "payload": payload, "checksum": payload.sha256_text()})

func _test_roundtrip() -> void:
	var case = _case()
	var store = case.store
	store.command("choose", {"node": "g1"})
	store.command("outfit", {"coat_color": "indigo", "bottom_id": "short_skirt"})
	store.command("suspend")
	store.command("begin", {"target": "qi"})
	var expected = store.view()
	check(store.save().ok, "save returns only after full reread")
	var before_load = store.make_command("choose", {"node": "talk_qi"})
	store.command("choose", {"node": "talk_qi"})
	check(store.load_game().ok and store.view() == expected, "full state / ledger / outfit / suspended story roundtrip")
	check(not store.submit(before_load).ok, "pre-load callback rejected")
	var new_port = FileSave.new(case.path)
	var new_store = Store.new(nodes, new_port)
	check(new_store.load_game().ok and new_store.view() == expected, "new process-style instance restores same save")
	check(new_store.command("choose", {"node": "talk_qi"}).ok, "fresh command IDs do not collide with saved ledger")
	check(new_store.save().sequence > 1, "cross-instance sequence advances")
	check(new_store.command("begin", {"target": "continue"}).ok and new_store.view().node == "g2", "main story resumes after loaded optional conversation")

func _test_faults() -> void:
	for fault in ["disk_full", "partial", "validated", "backup", "before_replace", "after_replace", "final_read"]:
		var case = _case()
		check(case.store.save().ok, "baseline save " + fault)
		case.store.command("choose", {"node": "g1"})
		case.port.fault = fault
		check(not case.store.save().ok, "fault never claims success " + fault)
		var recovered = case.port.read_snapshot()
		check(recovered.get("ok", false), "valid primary or backup survives " + fault)
		check(recovered.state.revision == (1 if fault in ["after_replace", "final_read"] else 0), "crash boundary outcome " + fault)
		case.port.fault = ""
		check(case.store.save().ok, "retry succeeds " + fault)
		check(case.port.read_snapshot().state.revision == 1, "retry writes expected revision " + fault)

func _test_recovery() -> void:
	var case = _case()
	case.store.save()
	case.store.command("choose", {"node": "g1"})
	case.store.save()
	var backup_bytes = FileAccess.get_file_as_string(case.path + "/slot.bak")
	_write(case.path + "/slot.json", "{bad-json")
	var result = case.store.load_game()
	check(result.ok and result.recovered and case.store.view().revision == 0, "corrupt primary restores previous validated backup")
	check(FileAccess.get_file_as_string(case.path + "/slot.json") == "{bad-json", "reading corruption is nondestructive")
	check(case.store.save().ok, "recovered state may be explicitly saved")
	check(FileAccess.get_file_as_string(case.path + "/slot.bak") == backup_bytes, "corrupt primary never replaces valid backup")
	_write(case.path + "/slot.json", "{}")
	check(case.store.load_game().get("recovered", false), "missing version is corruption and may recover backup")
	var invalid = Rules.fresh()
	invalid.node = "missing-content-reference"
	_write(case.path + "/slot.json", _envelope(invalid))
	check(case.store.load_game().get("recovered", false), "checksum-valid invalid story falls back to backup")
	invalid = Rules.fresh()
	invalid.ledger["bad"] = {"fingerprint": "x", "result": {"ok": true, "revision": 0}}
	_write(case.path + "/slot.json", _envelope(invalid))
	check(case.store.load_game().get("recovered", false), "invalid ledger falls back")
	var bare = _case()
	_write(bare.path + "/slot.tmp", _envelope(Rules.fresh()))
	check(not bare.store.load_game().ok, "uncommitted temporary file is not loaded")
	_write(bare.path + "/slot.json", "broken")
	var before = bare.store.view()
	check(not bare.store.load_game().ok and bare.store.view() == before, "failed load does not mutate live state")
	_write(bare.path + "/slot.json", _envelope(Rules.fresh()).replace('"checksum":"', '"checksum":"tamper'))
	check(not bare.store.load_game().ok, "checksum tamper rejected")

func _test_versions() -> void:
	for target in ["envelope", "schema", "content"]:
		var case = _case()
		case.store.save()
		case.store.command("choose", {"node": "g1"})
		case.store.save()
		var future = Rules.fresh()
		if target == "schema": future.schema = 999
		if target == "content": future.content_version = "future-content"
		var bytes = _envelope(future, 100, 999 if target == "envelope" else 1)
		_write(case.path + "/slot.json", bytes)
		var before = case.store.view()
		check(not case.store.load_game().ok and case.store.view() == before, "unknown version refuses silent backup load " + target)
		check(not case.store.save().ok and FileAccess.get_file_as_string(case.path + "/slot.json") == bytes, "unknown version protected from overwrite " + target)
	var case = _case()
	var unknown = Rules.fresh()
	unknown.schema = 0
	_write(case.path + "/slot.json", _envelope(unknown))
	check(not case.store.load_game().ok, "unmigratable old version rejected")

func _test_migration() -> void:
	var case = _case()
	var old = {"schema": 1, "revision": 0, "stage": "gate", "node": "g1", "flags": {},
		"appearance": {"top": "shirt", "coat": "short", "color": "wine", "bottom": "pleated"},
		"journal": [], "choices": {}, "ledger": {}, "anchor": [-7.0, 4.0], "route": {}}
	_write(case.path + "/slot.json", _envelope(old))
	var result = case.store.load_game()
	check(result.ok and result.migrated, "PR1 schema explicitly migrated")
	check(case.store.view().appearance == {"coat_color": "indigo", "bottom_id": "short_skirt"}, "legacy clothing ID migration")
	check(case.store.save().ok and not case.port.read_snapshot().migrated, "migrated state saved as current schema")
	check(FileAccess.get_file_as_string(case.path + "/slot.bak") == _envelope(old), "legacy source preserved as backup")

func _test_barriers() -> void:
	var case = _case()
	var old_snapshot = case.store.view()
	var old_epoch: int = case.store.context().epoch
	case.store.save()
	case.store.command("choose", {"node": "g1"})
	case.store.command("choose", {"node": "g2"})
	var newer = case.store.save()
	check(newer.ok, "newer revision saved")
	check(not case.port.write_snapshot(old_snapshot, old_epoch).ok, "same-session older revision cannot overwrite")
	case.store.new_game()
	check(not case.port.write_snapshot(old_snapshot, old_epoch).ok, "new game barrier rejects stale save")
	var reset = case.store.save()
	check(reset.ok and reset.revision == 0 and reset.sequence > newer.sequence, "new-session lower revision allowed with newer sequence")
	case.store.command("choose", {"node": "g1"})
	case.store.save()
	DirAccess.copy_absolute(case.path + "/slot.bak", case.path + "/slot.json")
	check(case.store.load_game().ok and case.store.view().revision == 0, "older valid save may be loaded")
	check(case.store.save().ok, "load barrier permits valid low-revision persistence")

func _test_cabin_saves()->void:
	var case=_case()
	case.store.command("suspend")
	case.store.command("travel",{"scene_id":"PILOT_CABIN"})
	case.store.command("anchor",{"position":[-1.0,1.5]})
	case.store.command("outfit",{"coat_color":"cream","bottom_id":"long_skirt"})
	var expected=case.store.view()
	check(case.store.save().ok,"indoor state saved")
	case.store.command("travel",{"scene_id":"FOG_HARBOR"})
	check(case.store.load_game().ok and case.store.view()==expected,"load restores room, local position, appearance and suspended story")
	var legacy=Rules.fresh()
	legacy.schema=2
	_write(case.path+"/slot.json",_envelope(legacy))
	check(case.store.load_game().ok and case.store.view().schema==3,"schema2 migrates to schema3")
	check(case.store.view().world.scene_id=="FOG_HARBOR","old outdoor anchor preserved")
