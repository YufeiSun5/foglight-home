extends "res://src/app/ports/save_port.gd"
## Synchronous single-slot transaction: temp -> validated backup -> atomic rename -> reread.
var root: String
var epoch = 0
var sequence = 0
var fault = ""
func _init(directory: String = "user://saves"):
	root = directory
	DirAccess.make_dir_recursive_absolute(root)
	for path in [root + "/slot.json", root + "/slot.bak"]:
		var r = _read(path)
		if r.get("ok", false): sequence = maxi(sequence, int(r.sequence))
func barrier(new_epoch: int) -> void:
	epoch = new_epoch
func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "还没有存档"}
	var e = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not e is Dictionary or e.get("format") != 1 or not e.get("payload") is String or not e.get("checksum") is String or not (e.get("sequence") is int or e.get("sequence") is float): return {"ok": false, "error": "存档版本或格式不可读取"}
	if e.payload.sha256_text() != e.checksum: return {"ok": false, "error": "存档校验失败"}
	var state = JSON.parse_string(e.payload)
	if not state is Dictionary: return {"ok": false, "error": "存档内容无效"}
	return {"ok": true, "state": state, "sequence": int(e.sequence)}
func read_snapshot() -> Dictionary:
	var r = _read(root + "/slot.json")
	if r.get("ok", false): return r
	# Unknown future versions must be surfaced rather than silently replaced.
	if FileAccess.file_exists(root + "/slot.json"):
		var e = JSON.parse_string(FileAccess.get_file_as_string(root + "/slot.json"))
		if e is Dictionary and e.get("format", 1) != 1: return r
	var b = _read(root + "/slot.bak")
	if b.get("ok", false): b["recovered"] = true; return b
	return r
func write_snapshot(snapshot: Dictionary, request_epoch: int) -> Dictionary:
	if request_epoch != epoch: return {"ok": false, "error": "旧存档请求已取消"}
	sequence += 1
	var payload = JSON.stringify(snapshot)
	var data = JSON.stringify({"format": 1, "sequence": sequence, "payload": payload, "checksum": payload.sha256_text()})
	var file = FileAccess.open(root + "/slot.tmp", FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "无法写入存档目录"}
	file.store_string(data.left(data.length() / 2) if fault == "partial" else data)
	file.flush()
	file.close()
	if fault == "partial": return {"ok": false, "error": "模拟写入中断"}
	if not _read(root + "/slot.tmp").get("ok", false): return {"ok": false, "error": "临时存档校验失败"}
	if fault == "validated": return {"ok": false, "error": "模拟校验后中断"}
	if _read(root + "/slot.json").get("ok", false):
		var copy_err = DirAccess.copy_absolute(root + "/slot.json", root + "/slot.backup.tmp")
		if copy_err != OK or not _read(root + "/slot.backup.tmp").get("ok", false): return {"ok": false, "error": "备份失败"}
		if DirAccess.rename_absolute(root + "/slot.backup.tmp", root + "/slot.bak") != OK: return {"ok": false, "error": "备份替换失败"}
	if fault == "before_replace": return {"ok": false, "error": "模拟替换前中断"}
	if request_epoch != epoch: return {"ok": false, "error": "旧存档请求已取消"}
	if DirAccess.rename_absolute(root + "/slot.tmp", root + "/slot.json") != OK: return {"ok": false, "error": "存档替换失败"}
	if fault == "after_replace": return {"ok": false, "error": "模拟替换后中断"}
	var result = _read(root + "/slot.json")
	if not result.get("ok", false) or result.sequence != sequence: return {"ok": false, "error": "最终存档回读失败"}
	return {"ok": true, "sequence": sequence}
