extends RefCounted
func write_snapshot(_snapshot: Dictionary, _epoch: int) -> Dictionary:
	return {"ok": false, "error": "未配置存档"}
func read_snapshot() -> Dictionary:
	return {"ok": false, "error": "尚无存档"}
func barrier(_epoch: int) -> void:
	pass
