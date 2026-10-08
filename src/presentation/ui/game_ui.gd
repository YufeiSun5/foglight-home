extends Control
## Snapshot-only UI. The composition root connects intent_requested to GameFlow.submit.
## No story state, saves, world transforms or application rules live here.
signal intent_requested(command: Dictionary)
const AppearanceView = preload("res://src/presentation/ui/appearance_view.gd")
const UITheme = preload("res://src/presentation/ui/ui_theme.gd")
var _flow: RefCounted
var _snapshot: Dictionary = {}
var _draft: Dictionary = {}
var _serial: int = 0
var _dispatching: bool = false
var _buttons: Dictionary = {}
var _commands: Dictionary = {}
var _surfaces: Dictionary = {}
var _canvas: Control
var _focus_key: String = ""
var _return_focus: String = ""
var _forced_focus: String = ""
var _confirm_new_game: bool = false
var _journal_page: int = 0
var _world_hint: String = ""
var _hint_label: Label
const JOURNAL_PAGE_SIZE = 30

func _ready() -> void:
	name = "GameUI"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.make()
	resized.connect(_layout)
	if not _snapshot.is_empty(): _rebuild()

func bind_flow(flow: RefCounted) -> void:
	unbind_flow()
	_flow = flow
	_flow.changed.connect(_refresh)
	_refresh()

func unbind_flow() -> void:
	if _flow != null and _flow.changed.is_connected(_refresh): _flow.changed.disconnect(_refresh)
	_flow = null
	_serial += 1
	_snapshot = {}
	_draft = {}
	_buttons.clear()
	_commands.clear()
	if is_instance_valid(_canvas): _canvas.queue_free()
	_canvas = null

func _exit_tree() -> void:
	unbind_flow()

func _refresh() -> void:
	if _flow == null: return
	var prior_mode: String = _snapshot.get("mode", "")
	var next: Dictionary = _flow.view().duplicate(true)
	# Normal combat ticks have stable interaction context. Keep their toolbar
	# nodes/focus instead of rebuilding controls for every transient frame.
	if is_instance_valid(_canvas) and _visible_state(next) == _visible_state(_snapshot):
		_snapshot = next
		return
	var overlays = ["wardrobe", "journal", "pause"]
	if next.get("mode") in overlays and not prior_mode in overlays:
		var focused = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		_return_focus = str(focused.get_meta("ui_key", "")) if focused != null else ""
	elif prior_mode in overlays and not next.get("mode") in overlays:
		_forced_focus = _return_focus
		_return_focus = ""
	_snapshot = next
	_draft = _snapshot.get("appearance", {}).duplicate(true)
	_confirm_new_game = false
	_dispatching = false
	_journal_page = 0
	if is_inside_tree(): _rebuild()

func _visible_state(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["context", "mode", "dialogue", "chapter", "appearance", "wardrobe", "journal", "transition", "saved_revision", "unsaved"]:
		result[key] = value.get(key)
	var status: Dictionary = value.get("status", {})
	result.status = {"ok": status.get("ok", true), "error": status.get("error", ""), "warning": status.get("warning", ""), "message": status.get("message", "")}
	return result

func set_world_hint(value: String) -> void:
	_world_hint = value
	if is_instance_valid(_hint_label): _hint_label.text = value

func rendered_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func preview_appearance() -> Dictionary:
	return _draft.duplicate(true)

func button_for(key: String) -> Button:
	return _buttons.get(key)

func command_for(key: String) -> Dictionary:
	return _commands.get(key, {}).duplicate(true)

func surface_rects() -> Dictionary:
	var result = {}
	for key in _surfaces: result[key] = _surfaces[key].get_global_rect()
	return result

func _rebuild() -> void:
	var focused = get_viewport().gui_get_focus_owner()
	if not _forced_focus.is_empty():
		_focus_key = _forced_focus
		_forced_focus = ""
	elif focused != null and focused.has_meta("ui_key"): _focus_key = focused.get_meta("ui_key")
	_serial += 1
	_buttons.clear()
	_commands.clear()
	_surfaces.clear()
	if is_instance_valid(_canvas):
		remove_child(_canvas)
		_canvas.queue_free()
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hud()
	var mode: String = _snapshot.get("mode", "exploration")
	if mode in ["wardrobe", "journal", "pause", "transition"]:
		var shade = ColorRect.new()
		shade.color = Color(0.02, 0.045, 0.07, 0.65)
		_canvas.add_child(shade)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if mode == "wardrobe": _build_wardrobe()
		elif mode == "journal": _build_journal()
		elif mode == "pause": _build_pause()
		else: _build_transition()
	elif mode == "dialogue": _build_dialogue()
	_build_status()
	_layout()
	_restore_focus.call_deferred(_serial)

func _restore_focus(generation: int) -> void:
	if generation != _serial or not is_inside_tree(): return
	var key = _focus_key
	if not _buttons.has(key) or _buttons[key].disabled:
		key = "advance" if _buttons.has("advance") else ("choice_0" if _buttons.has("choice_0") else "close")
	if _buttons.has(key) and not _buttons[key].disabled: _buttons[key].grab_focus()

func _panel(key: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.name = key.capitalize().replace(" ", "")
	# Wrapped text measures after its first container sort. Reapply the intended
	# bounds when that minimum shrinks, rather than retaining a tall first frame.
	panel.minimum_size_changed.connect(_layout, CONNECT_DEFERRED)
	_canvas.add_child(panel)
	_surfaces[key] = panel
	return panel

func _column(parent: Node, separation: int = 8) -> VBoxContainer:
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column

func _row(parent: Node) -> HBoxContainer:
	var row = HBoxContainer.new()
	parent.add_child(row)
	return row

func _label(parent: Node, value: String, font_size: int = 20, muted: bool = false) -> Label:
	var label = Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	if muted: label.add_theme_color_override("font_color", UITheme.MUTED)
	parent.add_child(label)
	return label

func _copy(parent: Node, value: String, min_height: float = 0) -> Label:
	var text = Label.new()
	text.text = value
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.y = min_height
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(text)
	return text

func _button(parent: Node, key: String, text: String, action: String = "", payload: Dictionary = {}) -> Button:
	var button = Button.new()
	button.name = key
	button.text = text
	button.custom_minimum_size.y = 40
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("ui_key", key)
	parent.add_child(button)
	_buttons[key] = button
	if not action.is_empty():
		var command: Dictionary = _flow.intent(action, payload).duplicate(true)
		_commands[key] = command
		button.pressed.connect(_emit_command.bind(command, _serial))
	return button

func _emit_command(command: Dictionary, generation: int) -> void:
	if generation != _serial or _dispatching or _flow == null: return
	_dispatching = true
	var enabled_before = {}
	for key in _buttons:
		enabled_before[key] = _buttons[key].disabled
		_buttons[key].disabled = true
	# Emission can synchronously cause changed -> redraw. Never enable an old view.
	intent_requested.emit(command.duplicate(true))
	if generation == _serial:
		_dispatching = false
		for key in _buttons: _buttons[key].disabled = enabled_before.get(key, false)

func _build_hud() -> void:
	var heading = _column(_panel("heading"), 1)
	_label(heading, "雾灯归航", 23)
	_label(heading, "第一章 · 雾港没有出口" + (" · 未保存" if _snapshot.get("unsaved", true) else " · 已保存"), 14, true)
	var toolbar = _row(_panel("toolbar"))
	_button(toolbar, "wardrobe", "衣柜  I", "open_wardrobe")
	_button(toolbar, "journal", "记录  J", "open_journal")
	_button(toolbar, "pause", "暂停  Esc", "pause")
	var mode: String = _snapshot.get("mode", "exploration")
	for key in ["wardrobe", "journal", "pause"]: _buttons[key].disabled = mode in ["wardrobe", "journal", "pause", "transition"]
	if mode == "exploration":
		var hint = _column(_panel("exploration_hint"), 2)
		_hint_label = _label(hint, _world_hint, 18)
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_label.add_theme_color_override("font_color", UITheme.GOLD)
		var controls = _label(hint, "WASD / 方向键  移动    E  交谈    Q  切换", 14, true)
		controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_dialogue() -> void:
	var dialogue: Dictionary = _snapshot.get("dialogue", {})
	var body = _row(_panel("dialogue"))
	body.add_theme_constant_override("separation", 24)
	var speaker: String = dialogue.get("speaker_id", "narrator")
	if speaker != "narrator":
		var portrait_column = _column(body, 2)
		portrait_column.custom_minimum_size.x = 156
		var portrait = AppearanceView.portrait(speaker, dialogue.get("expression", "calm"), _snapshot.get("appearance", {}))
		portrait.custom_minimum_size = Vector2(156, 206)
		portrait_column.add_child(portrait)
		if portrait.get_meta("art_kind") == "npc_idle_placeholder": _label(portrait_column, "像素形象 · 立绘待完善", 12, true)
	var content = _column(body, 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header = _row(content)
	var speaker_label = _label(header, dialogue.get("speaker_name", "旁白"), 22)
	speaker_label.add_theme_color_override("font_color", UITheme.GOLD)
	speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "suspend", "暂放对话", "suspend").add_theme_font_size_override("font_size", 15)
	var speech = _copy(content, dialogue.get("text", ""), 58)
	speech.name = "DialogueText"
	speech.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var choices: Array = dialogue.get("choices", [])
	for choice in choices:
		var key = "choice_%d" % int(choice.index)
		var button = _button(content, key, "%d   %s" % [int(choice.index) + 1, choice.text], "choose", {"index": int(choice.index)})
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer = _row(content)
	var flexible = Control.new()
	flexible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(flexible)
	if dialogue.get("can_skip", false): _button(footer, "skip", "略过这一段", "skip").add_theme_font_size_override("font_size", 16)
	if dialogue.get("can_advance", false): _button(footer, "advance", "继续  空格", "advance")

func _modal_header(column: VBoxContainer, title: String) -> void:
	var header = _row(column)
	var label = _label(header, title, 26)
	label.add_theme_color_override("font_color", UITheme.GOLD)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "close", "返回  Esc", "close")
	column.add_child(HSeparator.new())

func _build_wardrobe() -> void:
	var column = _column(_panel("wardrobe"), 10)
	_modal_header(column, "衣柜")
	_label(column, "4 种配色 · 4 种下装 · 全部可选", 16, true)
	var body = _row(column)
	body.add_theme_constant_override("separation", 22)
	var previews = _row(body)
	previews.custom_minimum_size = Vector2(330, 248)
	var full = AppearanceView.wardrobe(_draft)
	full.custom_minimum_size = Vector2(170, 238)
	previews.add_child(full)
	var portrait = AppearanceView.portrait("star", "calm", _draft)
	portrait.name = "WardrobePortrait"
	portrait.custom_minimum_size = Vector2(145, 238)
	previews.add_child(portrait)
	var options = _column(body, 10)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(options, "外套配色", 19)
	var colors = GridContainer.new()
	colors.columns = 2
	colors.add_theme_constant_override("h_separation", 8)
	colors.add_theme_constant_override("v_separation", 8)
	options.add_child(colors)
	for coat in _snapshot.get("wardrobe", {}).get("coats", []):
		var selected: bool = coat.id == _draft.get("coat_color")
		var button = _button(colors, "coat_" + str(coat.id), ("● " if selected else "○ ") + str(coat.label))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_draft.bind("coat_color", coat.id, _serial))
		button.tooltip_text = "仅试穿，点击「穿上这套」后应用"
	_label(options, "下装", 19)
	var bottoms = GridContainer.new()
	bottoms.columns = 2
	bottoms.add_theme_constant_override("h_separation", 8)
	bottoms.add_theme_constant_override("v_separation", 8)
	options.add_child(bottoms)
	for bottom in _snapshot.get("wardrobe", {}).get("bottoms", []):
		var selected: bool = bottom.id == _draft.get("bottom_id")
		var button = _button(bottoms, "bottom_" + str(bottom.id), ("● " if selected else "○ ") + str(bottom.label))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_draft.bind("bottom_id", bottom.id, _serial))
	var changed = _draft.get("coat_color") != _snapshot.get("appearance", {}).get("coat_color") or _draft.get("bottom_id") != _snapshot.get("appearance", {}).get("bottom_id")
	_label(column, "试穿中 · 尚未应用" if changed else "当前衣装 · 世界形象与对白同步", 16, true)
	var footer = _row(column)
	var note = _label(footer, "返回会取消未应用的试穿", 15, true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(footer, "apply_outfit", "穿上这套", "outfit", {"coat_color": _draft.get("coat_color"), "bottom_id": _draft.get("bottom_id")})

func _select_draft(field: String, value: String, generation: int) -> void:
	if generation != _serial or _dispatching: return
	_draft[field] = value
	if field == "coat_color":
		for coat in _snapshot.get("wardrobe", {}).get("coats", []):
			if coat.id == value: _draft.coat_hex = coat.hex
	_rebuild()

func _build_journal() -> void:
	var column = _column(_panel("journal"), 10)
	_modal_header(column, "故事记录")
	var entries: Array = _snapshot.get("journal", [])
	var total_pages = maxi(1, ceili(entries.size() / float(JOURNAL_PAGE_SIZE)))
	_journal_page = clampi(_journal_page, 0, total_pages - 1)
	var scroll = ScrollContainer.new()
	scroll.name = "JournalScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var lines = _column(scroll, 10)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if entries.is_empty(): _copy(lines, "还没有记录。交谈之后，已读对白会留在这里。")
	for index in range(_journal_page * JOURNAL_PAGE_SIZE, mini((_journal_page + 1) * JOURNAL_PAGE_SIZE, entries.size())):
		_copy(lines, str(entries[index]))
	var footer = _row(column)
	_button(footer, "journal_previous", "上一页").pressed.connect(_turn_journal.bind(-1, _serial))
	_buttons.journal_previous.disabled = _journal_page == 0
	var page = _label(footer, "%d / %d 页 · %d 条记录" % [_journal_page + 1, total_pages, entries.size()], 15, true)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(footer, "journal_next", "下一页").pressed.connect(_turn_journal.bind(1, _serial))
	_buttons.journal_next.disabled = _journal_page + 1 >= total_pages

func _turn_journal(offset: int, generation: int) -> void:
	if generation != _serial: return
	_journal_page += offset
	_rebuild()

func _build_pause() -> void:
	var column = _column(_panel("pause"), 12)
	_modal_header(column, "暂停")
	_label(column, "重建试玩 · 画面待验收", 14, true)
	if _confirm_new_game:
		_copy(column, "重新开始会结束当前游玩并重置当前故事进度。要重新开始吗？")
		_button(column, "cancel_new_game", "返回暂停菜单").pressed.connect(_cancel_restart.bind(_serial))
		_button(column, "confirm_new_game", "确认重新开始", "new_game")
	else:
		_button(column, "resume", "继续游玩", "close")
		_button(column, "save", "保存进度  F5", "save")
		_button(column, "load", "读取存档  F9", "load")
		_button(column, "new_game", "重新开始").pressed.connect(_request_restart.bind(_serial))
		_copy(column, "I 衣柜    J 记录    Esc 返回\n对白：空格继续，数字键选择", 42)

func _request_restart(generation: int) -> void:
	if generation != _serial: return
	_confirm_new_game = true
	_rebuild()

func _cancel_restart(generation: int) -> void:
	if generation != _serial: return
	_confirm_new_game = false
	_rebuild()

func _build_transition() -> void:
	var column = _column(_panel("transition"), 12)
	_label(column, "正在准备场景", 24)
	_copy(column, "请稍候。准备完成后继续；也可以取消并留在原处。")
	_button(column, "cancel_transition", "取消并返回", "cancel_transition", {"transition_id": _snapshot.get("transition", {}).get("id", "")})

func _build_status() -> void:
	var status: Dictionary = _snapshot.get("status", {})
	var message: String = status.get("error", "") if not status.get("ok", true) else status.get("warning", status.get("message", ""))
	if message.is_empty(): return
	var panel = _panel("status")
	var label = _copy(panel, message)
	label.add_theme_color_override("font_color", Color("f0c894") if not status.get("ok", true) else UITheme.INK)

func _layout() -> void:
	if _surfaces.is_empty(): return
	var width = size.x
	var height = size.y
	var margin = 20.0 if width >= 1000 else 12.0
	var small = height < 620
	theme.default_font_size = 18 if small else 20
	_place("heading", Rect2(margin, margin, 275, 70))
	_place("toolbar", Rect2(width - margin - 377, margin, 377, 62))
	_place("exploration_hint", Rect2((width - 560) * 0.5, height - margin - 76, 560, 76))
	var dialogue_height = 296.0 if _snapshot.get("dialogue", {}).get("choices", []).size() > 0 else 252.0
	_place("dialogue", Rect2(margin, height - margin - dialogue_height, width - margin * 2, dialogue_height))
	var modal_size = Vector2(minf(840, width - margin * 2), minf(470, height - margin * 2))
	_place("wardrobe", Rect2((size - modal_size) * 0.5, modal_size))
	modal_size = Vector2(minf(880, width - margin * 2), minf(540, height - margin * 2))
	_place("journal", Rect2((size - modal_size) * 0.5, modal_size))
	modal_size = Vector2(minf(520, width - margin * 2), minf(452, height - margin * 2))
	_place("pause", Rect2((size - modal_size) * 0.5, modal_size))
	_place("transition", Rect2((size - Vector2(520, 190)) * 0.5, Vector2(520, 190)))
	_place("status", Rect2(margin, 98, minf(680, width - margin * 2), 56))

func _place(key: String, rectangle: Rect2) -> void:
	if _surfaces.has(key):
		_surfaces[key].position = rectangle.position
		_surfaces[key].size = rectangle.size

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _flow == null: return
	var key = ""
	var mode: String = _snapshot.get("mode", "exploration")
	match event.keycode:
		KEY_ESCAPE:
			if _confirm_new_game: _cancel_restart(_serial); get_viewport().set_input_as_handled(); return
			key = "cancel_transition" if mode == "transition" else ("close" if mode in ["wardrobe", "journal", "pause"] else "pause")
		KEY_I: key = "close" if mode == "wardrobe" else "wardrobe"
		KEY_J:
			if mode == "expedition": return
			key = "close" if mode == "journal" else "journal"
		KEY_SPACE: key = "advance"
		KEY_1, KEY_2, KEY_3: key = "choice_%d" % (event.keycode - KEY_1)
		KEY_F5:
			if mode == "transition": return
			_emit_command(_flow.intent("save"), _serial); get_viewport().set_input_as_handled(); return
		KEY_F9:
			if mode == "transition": return
			_emit_command(_flow.intent("load"), _serial); get_viewport().set_input_as_handled(); return
	if _buttons.has(key) and not _buttons[key].disabled:
		_buttons[key].pressed.emit()
		get_viewport().set_input_as_handled()
