extends RefCounted
## Boundary contract. Concrete IO is injected by bootstrap.
var _validator: Callable
func set_validator(validator: Callable) -> void:
	_validator = validator
func write_snapshot(_snapshot: Dictionary, _epoch: int) -> Dictionary:
	return {"ok": false, "error": "未配置存档"}
func read_snapshot() -> Dictionary:
	return {"ok": false, "error": "尚无存档"}
func barrier(_epoch: int) -> void:
	pass
