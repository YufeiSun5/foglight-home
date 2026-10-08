extends RefCounted
## Sole authoritative writer. Presentation receives isolated snapshots only.
const Rules = preload("res://src/domain/story_rules.gd")
signal changed
signal committed(events: Array)
var _state: Dictionary
var _nodes: Dictionary
var _epoch = 0
var _generation = 0
var _counter = 0
var _instance_id = str(Time.get_unix_time_from_system()) + ":" + str(Time.get_ticks_usec()) + ":" + str(get_instance_id())
var _save_port: RefCounted
var _submitting = false

func _init(definitions: Dictionary, port: RefCounted):
	_nodes = definitions.duplicate(true)
	_save_port = port
	_save_port.set_validator(Callable(self, "validate_snapshot"))
	new_game()

func view() -> Dictionary: return _state.duplicate(true)
func content() -> Dictionary: return _nodes.duplicate(true)
func line() -> Dictionary: return _nodes.get(_state.node, {}).duplicate(true)
func context() -> Dictionary:
	return {"revision": int(_state.revision), "epoch": _epoch, "generation": _generation}
func validate_snapshot(snapshot: Dictionary) -> bool: return Rules.valid(snapshot, _nodes)

func invalidate_interactions()->Dictionary:
	# A UI/activity boundary, not a persistent story mutation or save operation.
	if _submitting:return {"ok":false,"error":"已有命令正在提交"}
	_submitting=true
	_generation+=1
	changed.emit()
	_submitting=false
	return {"ok":true}


func new_game() -> Dictionary:
	if _submitting: return {"ok": false, "error": "已有命令正在提交"}
	_epoch += 1
	_generation += 1
	_save_port.barrier(_epoch)
	_state = Rules.fresh()
	changed.emit()
	return {"ok": true}

func make_command(action: String, payload: Dictionary = {}) -> Dictionary:
	_counter += 1
	return {"id": _instance_id + ":" + str(_epoch) + ":" + str(_counter), "source": "player", "epoch": _epoch,
		"generation": _generation, "revision": int(_state.revision), "action": action, "payload": payload.duplicate(true)}

func command(action: String, payload: Dictionary = {}) -> Dictionary:
	return submit(make_command(action, payload))

func inspect_command(c: Dictionary) -> Dictionary:
	if _submitting: return {"ok": false, "error": "已有命令正在提交"}
	if c.get("epoch") != _epoch: return {"ok": false, "error": "旧会话回调"}
	var id: Variant = c.get("id", "")
	if not id is String or id.is_empty() or id.length() > 200 or not c.get("payload") is Dictionary or not c.get("action") is String or not c.get("source") is String:
		return {"ok": false, "error": "命令格式错误"}
	var fingerprint = JSON.stringify([c.action, c.payload, c.source, c.get("generation"), c.get("revision")], "", true).sha256_text()
	if _state.ledger.has(id):
		var previous: Dictionary = _state.ledger[id]
		return {"ok":true,"replay":true} if previous.fingerprint == fingerprint else {"ok": false, "error": "命令ID冲突"}
	if c.get("revision") != int(_state.revision) or c.get("generation") != _generation:
		return {"ok": false, "error": "旧交互回调"}
	var candidate=Rules.reduce(_state,c.action,c.payload,_nodes)
	if candidate.has("error"):return {"ok":false,"error":candidate.error}
	return {"ok":true,"replay":false}

func submit(c:Dictionary)->Dictionary:
	var inspected=inspect_command(c)
	if not inspected.ok:return inspected
	if inspected.replay:return _state.ledger[c.id].result.duplicate(true)
	var id:String=c.id
	var fingerprint=JSON.stringify([c.action,c.payload,c.source,c.get("generation"),c.get("revision")],"",true).sha256_text()
	_submitting = true
	var reduced = Rules.reduce(_state, c.action, c.payload, _nodes)
	if reduced.has("error"):
		_submitting = false
		return {"ok": false, "error": reduced.error}
	var events: Array = reduced.events
	for index in events.size():
		events[index]["event_id"] = str(_epoch) + ":" + id + ":" + str(index)
		events[index]["revision"] = reduced.state.revision
	var result = {"ok": true, "revision": reduced.state.revision, "events": events.duplicate(true)}
	reduced.state.ledger[id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	_state = reduced.state
	if c.action in ["choose", "begin", "suspend", "skip", "travel"]: _generation += 1
	# Block signal-driven reentrancy until this complete transaction is published.
	changed.emit()
	committed.emit(events.duplicate(true))
	_submitting = false
	return result.duplicate(true)

func save() -> Dictionary: return _save_port.write_snapshot(view(), _epoch)

## Startup inspection never replaces live state, advances its epoch or writes IO.
func saved_game_status() -> Dictionary:
	var result: Dictionary = _save_port.probe_snapshot()
	if not result.get("exists", true): return {"exists": false, "can_continue": false}
	var valid = result.get("ok", false) and result.get("state") is Dictionary and validate_snapshot(result.state)
	return {"exists": true, "can_continue": valid, "recovered": result.get("recovered", false),
		"error": "" if valid else result.get("error", "存档内容与当前章节不兼容")}

func load_game(preflight: Callable = Callable()) -> Dictionary:
	if _submitting: return {"ok": false, "error": "已有命令正在提交"}
	var result = _save_port.read_snapshot()
	if not result.get("ok", false): return result
	if not validate_snapshot(result.state): return {"ok": false, "error": "存档内容与当前章节不兼容"}
	# A world adapter may reject unavailable scenes/anchors before the epoch,
	# persistence barrier or authoritative state changes. Give it an isolated value.
	if preflight.is_valid():
		_submitting = true
		var checked: Variant = preflight.call(result.state.duplicate(true))
		_submitting = false
		if not checked is Dictionary or not checked.get("ok", false):
			return checked.duplicate(true) if checked is Dictionary else {"ok": false, "error": "读档场景检查无效"}
	_epoch += 1
	_generation += 1
	_save_port.barrier(_epoch)
	_state = result.state.duplicate(true)
	changed.emit()
	return {"ok": true, "recovered": result.get("recovered", false), "migrated": result.get("migrated", false)}
