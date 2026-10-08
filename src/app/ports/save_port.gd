extends RefCounted
## Boundary contract. Concrete IO is injected by bootstrap.
var _validator: Callable
func set_validator(validator: Callable) -> void:
	_validator = validator
func write_snapshot(_snapshot: Dictionary, _epoch: int) -> Dictionary:
	return {"ok": false, "error": "未配置存档"}
func read_snapshot() -> Dictionary:
	return {"ok": false, "error": "尚无存档"}
## Read-only startup probe. Implementations must explicitly report exists=false
## only when neither primary nor recovery data exists. Unknown errors stay gated.
func probe_snapshot() -> Dictionary:
	var result: Dictionary = read_snapshot().duplicate(true)
	result["exists"] = result.get("exists", true)
	return result
func barrier(_epoch: int) -> void:
	pass
