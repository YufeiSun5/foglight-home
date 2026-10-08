extends RefCounted
## Application composition. StateStore alone writes persistent facts;
## ExpeditionSession alone writes disposable combat. No scene or file imports.
const Store = preload("res://src/app/state_store.gd")
const Rules = preload("res://src/domain/story_rules.gd")
const Expedition = preload("res://src/app/expedition_session.gd")

signal changed
signal committed(events: Array)
signal route_effects(events: Array)
signal transition_requested(transition: Dictionary)

const COAT_LABELS = {"blue": "雾蓝", "cream": "米白", "green": "苔绿", "indigo": "靛蓝"}
const BOTTOM_LABELS = {"trousers": "工裤", "culottes": "裙裤", "long_skirt": "长裙", "short_skirt": "短裙"}
const STAGE_LABELS = {"gate": "港口的临时姓名", "meet": "把手递出去之前", "repair": "四个人才能稳住的灯", "cabin": "坐哪一张椅子", "depart": "雾还在前面", "complete": "第一章结束"}
var _store: RefCounted
var _world_port: RefCounted
var _catalog: Dictionary
var _route: RefCounted
var _prepared_route: RefCounted
var _overlay = ""
var _generation = 0
var _counter = 0
var _run_counter = 0
var _transition_counter = 0
var _instance = ""
var _busy = false
var _ledger: Dictionary = {}
var _pending: Dictionary = {}
var _status: Dictionary = {"ok": true}
var _events: Array = []
var _route_events: Array = []
var _last_route: Dictionary = {}
var _saved_revision = -1
var _position_provider: Callable
var _startup: Dictionary = {}

## Production bootstrap may pass its existing StateStore as the first argument
## and null as save_port. Dictionary + SavePort remains a convenient test seam.
func _init(definitions_or_store: Variant, save_port: RefCounted = null, route_catalog: Dictionary = {}, world_port: RefCounted = null, startup_gate: bool = false):
	_store = definitions_or_store if definitions_or_store is RefCounted else Store.new(definitions_or_store, save_port)
	_catalog = route_catalog.duplicate(true)
	_world_port = world_port
	_instance = str(get_instance_id()) + ":" + str(Time.get_ticks_usec())
	_store.committed.connect(_collect_committed)
	if startup_gate:
		var saved: Dictionary = _store.saved_game_status()
		if saved.get("exists", false):
			_startup = saved
			_startup.confirm_new_game = false

## Bootstrap injects a read-only physical-position sampler. A provider returns
## {position:[visual x,z], mapping_id} or {} when no stable world is available.
## It is sampled only after the original UI command passes replay/context checks;
## movement and the requested action publish one final UI refresh. No per-frame
## save-anchor commits or replacement of stale button commands are required.
func set_position_provider(provider: Callable) -> void:
	_position_provider = provider

func view() -> Dictionary:
	var story: Dictionary = _store.view()
	var line: Dictionary = _store.line()
	var dialogue: Dictionary = {}
	if not line.is_empty():
		var choices: Array = []
		for index in line.get("choices", []).size():
			var option: Dictionary = line.choices[index]
			choices.append({"id": option.id, "text": option.text, "index": index})
		dialogue = {"active": true, "node_id": story.node, "speaker_id": line.speaker,
			"speaker_name": Rules.NAMES[line.speaker], "text": line.text,
			"expression": line.get("expression", "calm"), "choices": choices,
			"can_advance": choices.is_empty(), "can_skip": choices.is_empty()}
	var appearance: Dictionary = story.appearance.duplicate(true)
	appearance.coat_hex = Rules.COLORS[appearance.coat_color]
	var coats: Array = []
	var bottoms: Array = []
	for id in Rules.COLORS: coats.append({"id": id, "label": COAT_LABELS[id], "hex": Rules.COLORS[id]})
	for id in Rules.BOTTOMS: bottoms.append({"id": id, "label": BOTTOM_LABELS[id]})
	var expedition: Dictionary = _route.view() if _route != null else {"ready": false}
	if _route != null: expedition.cards = _route.card_previews()
	var mode = _mode()
	return {"story": story, "context": _context(), "dialogue": dialogue,
		"chapter": {"id": "CH01", "title": "雾港没有出口", "stage_id": story.stage, "stage_label": STAGE_LABELS[story.stage], "complete": story.stage == "complete"},
		"appearance": appearance, "wardrobe": {"coats": coats, "bottoms": bottoms, "combinations": 16},
		"journal": story.journal.duplicate(), "mode": mode, "input_owner": mode,
		"world": {"scene_id": story.world.scene_id, "anchor": story.anchor.duplicate(),
			"presentation_bound": _world_port != null, "mapping": _resolve(story)},
		"expedition": expedition, "last_route": _last_route.duplicate(true),
		"transition": _public_transition(), "startup": _startup.duplicate(true), "status": _status.duplicate(true),
		"saved_revision": _saved_revision, "unsaved": int(story.revision) != _saved_revision}

func intent(action: String, payload: Dictionary = {}) -> Dictionary:
	_counter += 1
	var command = {"id": _instance + ":" + str(_counter), "action": action,
		"payload": payload.duplicate(true), "context": _context()}
	if action == "route_frame" and _route != null: command.route_revision = _route.view().revision
	return command

func submit(command: Dictionary) -> Dictionary:
	if _busy: return _error("已有操作正在提交")
	if not command.get("id") is String or command.id.is_empty() or command.id.length() > 200 or not command.get("action") is String or not command.get("payload") is Dictionary or not command.get("context") is Dictionary:
		return _error("操作格式错误")
	var current = _context()
	if command.context.get("epoch") != current.epoch: return _error("旧会话回调")
	# Reject malformed / non-JSON coordinates before fingerprinting or invoking a
	# mapping adapter. Adapters may rely on this public boundary's pair contract.
	if command.action == "visual_anchor" and (not command.payload.get("position") is Array or not _valid_position(command.payload.position)):
		return _error("画面位置格式无效")
	var fingerprint = JSON.stringify(command, "", true).sha256_text()
	if _ledger.has(command.id):
		var prior: Dictionary = _ledger[command.id]
		return prior.result.duplicate(true) if prior.fingerprint == fingerprint else _error("操作ID冲突")
	if command.context != current: return _error("旧界面回调")
	if command.action == "route_frame" and (_route == null or command.get("route_revision") != _route.view().revision): return _error("旧短途采样")
	_busy = true
	_events = []
	_route_events = []
	var result: Dictionary = _sample_position(command.action)
	if result.get("ok", false): result = _dispatch(command.action, command.payload)
	if result.get("ok", false):
		# Combat frames refresh transient revision, not every displayed UI token.
		if command.action != "route_frame": _generation += 1
		if _context().epoch != current.epoch: _ledger.clear()
		if command.action != "route_frame":
			_ledger[command.id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	_status = result.duplicate(true)
	_status.erase("events")
	changed.emit()
	if not _events.is_empty(): committed.emit(_events.duplicate(true))
	if not _route_events.is_empty(): route_effects.emit(_route_events.duplicate(true))
	if result.get("pending", false): transition_requested.emit(_public_transition())
	_busy = false
	return result.duplicate(true)

## Continuous world samplers use these read-only helpers, then submit route_frame.
func projectile_sweeps() -> Array:
	return _route.projectile_sweeps() if _route != null else []

func chain_sweep(sampled_intent: Dictionary = {}) -> Dictionary:
	return _route.chain_sweep(sampled_intent) if _route != null else {}

func _context() -> Dictionary:
	var context: Dictionary = _store.context()
	context.generation = _generation
	# A stable UI token survives ordinary combat ticks, but not a new encounter.
	if _route != null:
		var route: Dictionary = _route.view()
		context.run_id = route.run.run_id
		context.route_generation = route.generation
	return context

func _mode() -> String:
	if not _pending.is_empty(): return "transition"
	if not _startup.is_empty(): return "startup"
	if _overlay != "": return _overlay
	if _route != null: return "expedition"
	return "dialogue" if _store.view().node != "" else "exploration"

func _sample_position(action: String) -> Dictionary:
	if not _position_provider.is_valid() or _mode() != "exploration" or action not in ["save", "open_wardrobe", "open_journal", "pause", "begin", "travel", "route_start"]:
		return {"ok": true}
	var sampled: Variant = _position_provider.call()
	if not sampled is Dictionary: return _error("当前位置采样格式无效")
	if sampled.is_empty(): return {"ok": true}
	if not sampled.get("position") is Array or not _valid_position(sampled.position): return _error("当前位置采样格式无效")
	if _world_port == null: return _error("当前位置缺少可逆映射")
	var mapping = _resolve(_store.view())
	if not mapping.get("ok", false): return mapping
	if sampled.get("mapping_id") != mapping.mapping_id: return _error("当前位置映射已过期")
	# Visual transforms use float32. An unchanged rendered spawn must not rewrite
	# its exact saved logical anchor just because inverse arithmetic rounds it.
	if absf(float(sampled.position[0]) - float(mapping.visual_anchor[0])) <= 0.00001 and absf(float(sampled.position[1]) - float(mapping.visual_anchor[1])) <= 0.00001:
		return {"ok": true}
	return _dispatch("visual_anchor", {"position": sampled.position.duplicate(), "mapping_id": sampled.mapping_id})

func _dispatch(action: String, payload: Dictionary) -> Dictionary:
	if not _pending.is_empty():
		match action:
			"scene_ready": return _complete_transition(payload)
			"scene_failed", "cancel_transition": return _cancel_transition(payload, action)
			_: return _error("场景正在准备，可取消返回")
	if not _startup.is_empty(): return _startup_action(action)
	match action:
		"open_wardrobe": return _open_overlay("wardrobe")
		"open_journal": return _open_overlay("journal")
		"pause": return _open_overlay("pause")
		"close": return _close_overlay()
		"outfit":
			if _overlay != "wardrobe": return _error("请先打开衣柜")
			return _store.command("outfit", payload)
		"route_exit": return _route_action("exit", {})
		"route_frame":
			if _overlay != "": return _error("当前界面已暂停短途")
			return _route_action("frame", payload)
		"route_choose":
			if _overlay != "": return _error("请先关闭当前界面")
			return _route_action("choose", payload)
		"cancel_input": return _route_action("cancel_input", {})
	if _route != null: return _error("请先返回，主线进度会保留")
	if action == "save": return _save()
	if action == "load": return _load()
	if action == "new_game": return _new_game()
	if _overlay != "": return _error("请先关闭当前界面")
	match action:
		"advance": return _story_command("choose", {"node": _store.view().node, "index": -1})
		"choose": return _story_command("choose", {"node": _store.view().node, "index": payload.get("index", -1)})
		"skip", "suspend": return _story_command(action, {})
		"begin", "travel": return _story_command(action, payload)
		"anchor":
			if _mode() != "exploration": return _error("当前位置不能提交移动")
			return _story_command("anchor", payload)
		"visual_anchor":
			if _world_port == null or not payload.get("position") is Array: return _error("缺少位置映射")
			if not _valid_position(payload.position): return _error("画面位置格式无效")
			var position: Dictionary = _world_port.logical_position(_store.view().world.scene_id, payload.position.duplicate(), str(payload.get("mapping_id", "")))
			if not position.get("ok", false): return position
			return _dispatch("anchor", {"position": position.get("position")})
		"route_start": return _start_route(payload)
	return _error("未知操作")

func _startup_action(action: String) -> Dictionary:
	match action:
		"load":
			if _startup.confirm_new_game: return _error("请先取消重新开始，再读取存档")
			return _load()
		"new_game":
			_startup.confirm_new_game = true
			return {"ok": true, "confirmation_required": true}
		"cancel_new_game":
			if not _startup.confirm_new_game: return _error("当前没有重新开始确认")
			_startup.confirm_new_game = false
			return {"ok": true, "canceled": true}
		"confirm_new_game":
			if not _startup.confirm_new_game: return _error("请先确认是否替换现有进度")
			_startup.confirm_new_game = false
			return _new_game()
	return _error("请先继续存档，或确认开始新游戏")

func _open_overlay(name: String) -> Dictionary:
	if _overlay != "": return _error("请先关闭当前界面")
	if _route != null:
		var paused = _route_action("pause", {})
		if not paused.get("ok", false): return paused
	_store.invalidate_interactions()
	_overlay = name
	return {"ok": true}

func _close_overlay() -> Dictionary:
	if _overlay == "": return _error("当前没有打开的界面")
	_store.invalidate_interactions()
	_overlay = ""
	if _route != null: return _route_action("resume", {})
	return {"ok": true}

func _story_command(action: String, payload: Dictionary) -> Dictionary:
	var command: Dictionary = _store.make_command(action, payload)
	var checked: Dictionary = _store.inspect_command(command)
	if not checked.get("ok", false): return checked
	var before: Dictionary = _store.view()
	var next: Dictionary = Rules.reduce(before, action, payload, _store.content()).state
	var mapping: Dictionary = _resolve(next)
	if not mapping.get("ok", false): return mapping
	if _world_port != null and next.world.scene_id != before.world.scene_id:
		var saved = _save()
		if not saved.get("ok", false): return saved
		return _stage_transition("command", next, mapping, command)
	return _store.submit(command)

func _save() -> Dictionary:
	var result: Dictionary = _store.save()
	if result.get("ok", false): _saved_revision = int(_store.view().revision)
	return result

func _load() -> Dictionary:
	if _world_port == null:
		var result: Dictionary = _store.load_game()
		if result.get("ok", false): _after_replacement()
		return result
	var result: Dictionary = _store.load_game(Callable(self, "_stage_load"))
	if result.get("pending", false): return {"ok": true, "pending": true}
	return result

func _stage_load(snapshot: Dictionary) -> Dictionary:
	var mapping = _resolve(snapshot)
	if not mapping.get("ok", false): return mapping
	_stage_transition("load", snapshot, mapping)
	return {"ok": false, "pending": true, "error": "正在准备存档场景"}

func _new_game() -> Dictionary:
	var fresh: Dictionary = Rules.fresh()
	var mapping = _resolve(fresh)
	if not mapping.get("ok", false): return mapping
	if _world_port != null: return _stage_transition("new_game", fresh, mapping)
	var result: Dictionary = _store.new_game()
	if result.get("ok", false):
		_after_replacement()
		_saved_revision = -1
	return result

func _after_replacement() -> void:
	_startup = {}
	_overlay = ""
	_last_route = {}
	_saved_revision = int(_store.view().revision)

func _stage_transition(kind: String, target: Dictionary, mapping: Dictionary, command: Dictionary = {}) -> Dictionary:
	_transition_counter += 1
	_pending = {"id": _instance + ":transition:" + str(_transition_counter), "kind": kind,
		"target": target.duplicate(true), "mapping": mapping.duplicate(true), "command": command.duplicate(true)}
	return {"ok": true, "pending": true}

func _complete_transition(payload: Dictionary) -> Dictionary:
	if payload.get("transition_id") != _pending.id: return _error("旧场景回执")
	var result: Dictionary
	var kind: String = _pending.kind
	match kind:
		"command": result = _store.submit(_pending.command)
		"load": result = _store.load_game(Callable(self, "_accept_staged_load"))
		"new_game": result = _store.new_game()
		"route_start":
			_activate_route(_prepared_route)
			result = {"ok": true, "run_id": _route.view().run.run_id}
		_: result = _error("场景转换类型无效")
	_pending = {}
	_prepared_route = null
	if result.get("ok", false):
		if kind == "command":
			var saved = _save()
			if not saved.get("ok", false):
				# Live target is committed; do not replay story to retry persistence.
				result = {"ok": true, "saved": false, "warning": saved.get("error", "新位置尚未保存")}
			else: result.saved = true
		elif kind != "route_start":
			_after_replacement()
			if kind == "new_game": _saved_revision = -1
	return result

func _accept_staged_load(snapshot: Dictionary) -> Dictionary:
	if snapshot != _pending.target: return _error("准备期间存档已改变，请重新读档")
	return _resolve(snapshot)

func _cancel_transition(payload: Dictionary, action: String) -> Dictionary:
	if payload.get("transition_id") != _pending.id: return _error("旧场景回执")
	_pending = {}
	_prepared_route = null
	return {"ok": true, "canceled": true, "warning": str(payload.get("error", "场景准备失败，已保留原位置"))} if action == "scene_failed" else {"ok": true, "canceled": true}

func _public_transition() -> Dictionary:
	var transition = _pending.duplicate(true)
	transition.erase("command")
	return transition

func _resolve(snapshot: Dictionary) -> Dictionary:
	if _world_port == null:
		return {"ok": true, "mapping_id": "logical_only", "scene_id": snapshot.world.scene_id,
			"logical_anchor": snapshot.anchor.duplicate(), "visual_anchor": [], "transformed": false}
	var resolved: Variant = _world_port.resolve_snapshot(snapshot.duplicate(true))
	if not resolved is Dictionary: return _error("场景映射格式错误")
	if not resolved.get("ok", false): return resolved.duplicate(true)
	if not resolved.get("mapping_id") is String or resolved.mapping_id.is_empty() or resolved.get("scene_id") != snapshot.world.scene_id or resolved.get("logical_anchor") != snapshot.anchor or not resolved.get("transformed") is bool:
		return _error("场景映射不能替换存档场景或位置")
	var anchor: Variant = resolved.get("visual_anchor")
	if not anchor is Array or anchor.size() != 2: return _error("画面位置映射无效")
	for axis in anchor:
		if not (axis is float or axis is int) or not is_finite(float(axis)): return _error("画面位置映射无效")
	if not resolved.transformed and anchor != snapshot.anchor: return _error("位置变换必须明确标记")
	return resolved.duplicate(true)

func _start_route(payload: Dictionary) -> Dictionary:
	if _mode() != "exploration": return _error("先暂放对话，就可以自由出发")
	if not payload.get("seed", 1) is int or not payload.get("stages", 3) is int: return _error("短途参数无效")
	var origin_mapping = _resolve(_store.view())
	if not origin_mapping.get("ok", false): return origin_mapping
	var candidate = Expedition.new()
	_run_counter += 1
	var run_id = _instance + ":run:" + str(_run_counter)
	var started: Dictionary = candidate.start(_catalog, run_id, int(_store.context().epoch), payload.get("seed", 1), payload.get("stages", 3))
	if not started.get("ok", false): return started
	if _world_port != null:
		var resolved: Variant = _world_port.resolve_expedition(candidate.view())
		if not resolved is Dictionary or not resolved.get("ok", false):
			return resolved.duplicate(true) if resolved is Dictionary else _error("短途场景检查无效")
	# No run state is saved. A failed departure save leaves exploration usable.
	var saved = _save()
	if not saved.get("ok", false): return saved
	if _world_port != null:
		_prepared_route = candidate
		var staged = _stage_transition("route_start", _store.view(), origin_mapping)
		_pending.expedition = candidate.view()
		return staged
	_activate_route(candidate)
	return {"ok": true, "run_id": run_id}

func _activate_route(candidate: RefCounted) -> void:
	_store.invalidate_interactions()
	_route = candidate
	_route.effects.connect(_collect_route_effects)
	_last_route = {}

func _route_action(action: String, payload: Dictionary) -> Dictionary:
	if _route == null: return _error("当前没有短途")
	var result: Dictionary = _route.submit(_route.intent(action, payload))
	if result.get("ok", false) and _route.view().run.phase == "ended":
		var ended: Dictionary = _route.view().run
		_last_route = {"run_id": ended.run_id, "reason": ended.end_reason}
		_route = null
		_overlay = ""
		_store.invalidate_interactions()
		_generation += 1
		_events.append({"event_id": ended.run_id + ":returned", "revision": _store.view().revision,
			"kind": "route_returned", "object_id": ended.run_id, "reason": ended.end_reason})
	return result

func _collect_committed(events: Array) -> void:
	_events.append_array(events.duplicate(true))

func _collect_route_effects(events: Array) -> void:
	_route_events.append_array(events.duplicate(true))

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _valid_position(position: Array) -> bool:
	if position.size() != 2: return false
	for axis in position:
		if not (axis is int or axis is float) or not is_finite(float(axis)): return false
	return true
