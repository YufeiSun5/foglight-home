extends "res://src/app/ports/save_port.gd"
## Synchronous transaction: validated temp -> previous valid backup -> atomic rename -> reread.
## flush() is not a claim of power-loss durability. Replacement is platform-tested separately.
const Schema = preload("res://src/adapters/save_schema.gd")
const MAX_BYTES = 8 * 1024 * 1024
var root: String
var _epoch = 0
var _sequence = 0
var _last_written_revision = -1
var fault = "" # Test-only injection; empty in production.

func _init(directory: String = "user://saves"):
	root = directory
	DirAccess.make_dir_recursive_absolute(root)
	for path in [root + "/slot.json", root + "/slot.bak"]:
		var result = _read(path)
		if result.get("ok", false): _sequence = maxi(_sequence, int(result.sequence))

func barrier(new_epoch: int) -> void:
	if new_epoch != _epoch: _last_written_revision = -1
	_epoch = new_epoch

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "还没有存档"}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "无法读取存档"}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "error": "存档大小超出限制"}
	var serialized = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(serialized) != OK: return {"ok": false, "error": "存档 JSON 已损坏"}
	var envelope: Variant = parser.data
	if not envelope is Dictionary: return {"ok": false, "error": "存档 JSON 已损坏"}
	if not _whole(envelope.get("format")): return {"ok": false, "error": "存档封装版本字段已损坏"}
	if envelope.format > 1:
		return {"ok": false, "error": "存档封装版本无法读取，已保留原文件", "blocked_version": true}
	if envelope.format != 1: return {"ok": false, "error": "没有此封装版本的迁移规则"}
	if not envelope.get("payload") is String or not envelope.get("checksum") is String or not _whole(envelope.get("sequence")) or envelope.sequence < 1:
		return {"ok": false, "error": "存档封装结构无效"}
	if envelope.payload.sha256_text() != envelope.checksum: return {"ok": false, "error": "存档校验失败"}
	if parser.parse(envelope.payload) != OK: return {"ok": false, "error": "存档内容 JSON 已损坏"}
	var state: Variant = parser.data
	if not state is Dictionary: return {"ok": false, "error": "存档内容无效"}
	var migrated = Schema.migrate(state)
	if not migrated.get("ok", false): return migrated
	if _validator.is_valid() and not _validator.call(migrated.state): return {"ok": false, "error": "存档状态校验失败"}
	return {"ok": true, "state": migrated.state, "sequence": int(envelope.sequence), "migrated": migrated.migrated}

func read_snapshot() -> Dictionary:
	var result = _read(root + "/slot.json")
	if result.get("ok", false) or result.get("blocked_version", false): return result
	var backup = _read(root + "/slot.bak")
	if backup.get("ok", false):
		backup["recovered"] = true
		return backup
	return result

func write_snapshot(snapshot: Dictionary, request_epoch: int) -> Dictionary:
	if request_epoch != _epoch: return {"ok": false, "error": "旧存档请求已取消"}
	if not _validator.is_valid() or not _validator.call(snapshot): return {"ok": false, "error": "拒绝保存未验证状态"}
	if snapshot.revision < _last_written_revision: return {"ok": false, "error": "拒绝同会话旧快照覆盖"}
	var current = _read(root + "/slot.json")
	var backup = _read(root + "/slot.bak")
	if current.get("blocked_version", false) or backup.get("blocked_version", false):
		return {"ok": false, "error": "存在未知版本存档，未覆盖文件"}
	for prior in [current, backup]:
		if prior.get("ok", false): _sequence = maxi(_sequence, int(prior.sequence))
	_sequence += 1
	var payload = JSON.stringify(snapshot, "", true)
	var serialized = JSON.stringify({"format": 1, "sequence": _sequence, "payload": payload, "checksum": payload.sha256_text(), "build": "cloud-playable-0.1", "saved_at": Time.get_datetime_string_from_system(true)})
	if serialized.to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "error": "存档超过大小限制"}
	if fault == "disk_full": return {"ok": false, "error": "模拟磁盘写入失败"}
	var file = FileAccess.open(root + "/slot.tmp", FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法写入存档目录"}
	file.store_string(serialized.left(serialized.length() / 2) if fault == "partial" else serialized)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK: return {"ok": false, "error": "存档写入失败"}
	if fault == "partial": return {"ok": false, "error": "模拟写入中断"}
	var staged = _read(root + "/slot.tmp")
	if not staged.get("ok", false) or staged.sequence != _sequence: return {"ok": false, "error": "临时存档校验失败"}
	if fault == "validated": return {"ok": false, "error": "模拟校验后中断"}
	# A damaged primary must never replace the last known good backup.
	if current.get("ok", false):
		if fault == "backup": return {"ok": false, "error": "模拟备份失败"}
		var copy_error = DirAccess.copy_absolute(root + "/slot.json", root + "/slot.backup.tmp")
		if copy_error != OK or not _read(root + "/slot.backup.tmp").get("ok", false): return {"ok": false, "error": "备份失败"}
		if DirAccess.rename_absolute(root + "/slot.backup.tmp", root + "/slot.bak") != OK: return {"ok": false, "error": "备份替换失败"}
	if fault == "before_replace": return {"ok": false, "error": "模拟替换前中断"}
	if request_epoch != _epoch: return {"ok": false, "error": "旧存档请求已取消"}
	if DirAccess.rename_absolute(root + "/slot.tmp", root + "/slot.json") != OK: return {"ok": false, "error": "存档替换失败"}
	_last_written_revision = int(snapshot.revision)
	if fault in ["after_replace", "final_read"]: return {"ok": false, "error": "模拟替换后回读中断"}
	var final = _read(root + "/slot.json")
	if not final.get("ok", false) or final.sequence != _sequence or final.state != snapshot: return {"ok": false, "error": "最终存档回读失败"}
	return {"ok": true, "sequence": _sequence, "revision": snapshot.revision}

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 9007199254740991 and value == floor(float(value))
