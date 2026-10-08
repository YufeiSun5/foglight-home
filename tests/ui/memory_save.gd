extends "res://src/app/ports/save_port.gd"
## Test/demo-only save port; never reads or writes a player's disk slot.
var snapshot: Dictionary = {}
var writes: int = 0
var reads: int = 0
var barriers: int = 0
func write_snapshot(value: Dictionary, _epoch: int) -> Dictionary:
	writes += 1
	snapshot = value.duplicate(true)
	return {"ok": true}
func read_snapshot() -> Dictionary:
	reads += 1
	if snapshot.is_empty(): return {"ok": false, "error": "尚无存档"}
	return {"ok": true, "state": snapshot.duplicate(true)}
func barrier(_epoch: int) -> void:
	barriers += 1
