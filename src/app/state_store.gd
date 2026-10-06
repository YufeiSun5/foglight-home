extends RefCounted
const Rules = preload("res://src/domain/story_rules.gd")
signal changed
var _state: Dictionary
var nodes: Dictionary
var epoch = 0
var generation = 0
var save_port: RefCounted
var counter = 0
func _init(definitions: Dictionary, port: RefCounted):
	nodes = definitions.duplicate(true)
	save_port = port
	new_game()
func view() -> Dictionary: return _state.duplicate(true)
func new_game() -> void:
	epoch += 1
	generation += 1
	save_port.barrier(epoch)
	_state = Rules.fresh()
	changed.emit()
func command(action: String, payload: Dictionary = {}) -> Dictionary:
	counter += 1
	return submit({"id": str(epoch) + ":" + str(counter), "source": "player", "epoch": epoch, "generation": generation, "revision": int(_state.revision), "action": action, "payload": payload})
func submit(c: Dictionary) -> Dictionary:
	if c.get("epoch") != epoch: return {"ok": false, "error": "旧会话回调"}
	var id = c.get("id", "")
	if not id is String or id.is_empty() or not c.get("payload") is Dictionary or not c.get("action") is String: return {"ok": false, "error": "命令格式错误"}
	var fingerprint = JSON.stringify([c.action, c.payload, c.get("source"), c.get("generation"), c.get("revision")]).sha256_text()
	if _state.ledger.has(id):
		var old: Dictionary = _state.ledger[id]
		return old.result.duplicate(true) if old.fingerprint == fingerprint else {"ok": false, "error": "命令ID冲突"}
	if c.get("revision") != int(_state.revision) or c.get("generation") != generation: return {"ok": false, "error": "旧交互回调"}
	var r = Rules.reduce(_state, c.action, c.payload, nodes)
	if r.has("error"): return {"ok": false, "error": r.error}
	var result = {"ok": true, "revision": r.state.revision}
	r.state.ledger[id] = {"fingerprint": fingerprint, "result": result}
	_state = r.state
	if c.action in ["choose", "begin", "route_pick", "route_start", "route_end"]: generation += 1
	changed.emit()
	return result
func save() -> Dictionary: return save_port.write_snapshot(view(), epoch)
func load_game() -> Dictionary:
	var r = save_port.read_snapshot()
	if not r.get("ok", false): return r
	if not Rules.valid(r.state, nodes): return {"ok": false, "error": "存档内容与当前章节不兼容"}
	epoch += 1
	generation += 1
	save_port.barrier(epoch)
	_state = r.state.duplicate(true)
	changed.emit()
	return {"ok": true, "recovered": r.get("recovered", false)}
