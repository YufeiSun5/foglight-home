extends CanvasLayer
const Art = preload("res://src/presentation/pixel_art.gd")
const NAMES = {"star": "岑星遥 · 26", "shen": "沈砚舟 · 32", "xu": "许知微 · 33", "qi": "祁岚 · 29", "narrator": "雾港 · 今夜"}
const STAGE_TEXT = {"gate": "港口的临时姓名", "meet": "与沈砚舟交谈", "repair": "走到引灯台，见证四人协作", "cabin": "到船舱，坐下来谈同行", "depart": "准备好时，到离港栈桥", "complete": "第一章已完成 · 可继续散步、换装、听潮"}
var store: RefCounted
var harbor: Node3D
var root: Control
var hud: Control
var modal: Control
var chapter: Label
var hint: Label
var notice: Label
var mode = "menu"
var portrait: TextureRect
var speaker = "star"
var mood = "calm"
var wardrobe_full: TextureRect
var wardrobe_half: TextureRect
var anim_time = 0.0
var last_blink = false
var last_sprite_frame = -1
var choice_lock = false
func configure(app: RefCounted, world: Node3D) -> void:
	store = app; harbor = world
func _ready() -> void:
	root = Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
	var theme = Theme.new(); theme.default_font = load("res://assets/fonts/NotoSansSC.ttf"); theme.default_font_size = 20
	var button_style = style(Color("253945"), Color("a58c64")); theme.set_stylebox("normal", "Button", button_style); theme.set_stylebox("hover", "Button", style(Color("37525d"), Color("dfc08c"))); theme.set_stylebox("pressed", "Button", style(Color("182d35"), Color("dfc08c"))); theme.set_stylebox("focus", "Button", style(Color(0,0,0,0), Color("d6cb95")))
	theme.set_color("font_color", "Button", Color("f0e7d1")); theme.set_color("font_color", "Label", Color("e7e2d6")); root.theme = theme
	hud = Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(hud)
	chapter = text_label("", Vector2(28, 20), Vector2(720, 80), 21); hud.add_child(chapter)
	var nav = HBoxContainer.new(); nav.position = Vector2(724, 25); nav.size = Vector2(530, 42); nav.add_theme_constant_override("separation", 8); hud.add_child(nav)
	for item in [["衣柜 [C]", "wardrobe"], ["回看 [J]", "journal"], ["存档", "save"], ["读档", "load"], ["菜单", "pause"]]: nav.add_child(button(item[0], func(): toolbar(item[1])))
	hint = text_label("", Vector2(28, 719), Vector2(880, 48), 20); hud.add_child(hint)
	notice = text_label("", Vector2(30, 108), Vector2(1180, 80), 18); notice.modulate = Color("e4c999"); hud.add_child(notice)
	store.changed.connect(refresh)
	show_menu()
func style(fill: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new(); s.bg_color = fill; s.border_color = border; s.set_border_width_all(1); s.set_corner_radius_all(9); s.content_margin_left = 15; s.content_margin_right = 15; s.content_margin_top = 10; s.content_margin_bottom = 10; return s
func text_label(value: String, at: Vector2, dimensions: Vector2, font_size = 22) -> Label:
	var l = Label.new(); l.text = value; l.position = at; l.size = dimensions; l.add_theme_font_size_override("font_size", font_size); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; return l
func button(value: String, callback: Callable) -> Button:
	var b = Button.new(); b.text = value; b.custom_minimum_size = Vector2(0, 42); b.pressed.connect(callback); b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; return b
func clear_modal() -> void:
	if modal:
		root.remove_child(modal); modal.queue_free()
	modal = null; portrait = null; wardrobe_full = null; wardrobe_half = null
	choice_lock = false
func panel(at: Vector2, dimensions: Vector2) -> Panel:
	var p = Panel.new(); p.position = at; p.size = dimensions; p.add_theme_stylebox_override("panel", style(Color(0.055, 0.095, 0.13, 0.97), Color("b19a72"))); return p
func modal_base() -> void:
	clear_modal(); modal = Control.new(); modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(modal)
	var shade = ColorRect.new(); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.color = Color(0.015,0.025,0.04,0.45); modal.add_child(shade)
	harbor.player.controls_enabled = false
func show_menu() -> void:
	mode = "menu"; modal_base(); hud.visible = false
	var p = panel(Vector2(78, 95), Vector2(460, 620)); modal.add_child(p)
	p.add_child(text_label("FOGLIGHT HOME", Vector2(34,32), Vector2(390,35), 18))
	p.add_child(text_label("雾灯归航", Vector2(30,75), Vector2(410,65), 45))
	p.add_child(text_label("第一章 · 雾港没有出口", Vector2(34,153), Vector2(390,45), 23))
	p.add_child(text_label("在雾里写下自己的名字。\n真实3D雾港 · 像素人物 · 自选衣装", Vector2(34,214), Vector2(390,100), 20))
	var v = VBoxContainer.new(); v.position = Vector2(34,345); v.size = Vector2(390,160); v.add_theme_constant_override("separation", 12); p.add_child(v)
	v.add_child(button("开始新的第一章", func(): store.new_game(); mode = "play"; hud.visible = true; restore_anchor(); refresh()))
	v.add_child(button("继续上次存档", func(): load_slot()))
	v.add_child(button("离开试玩", func(): get_tree().quit()))
	p.add_child(text_label("WASD / 方向键走动 · E / 空格交谈\nC 衣柜 · J 回看 · F5 存档 · F9 读档\n内容提示：家庭否定；全部角色成年。", Vector2(34,525), Vector2(390,80), 16))
func restore_anchor() -> void:
	var s = store.view(); harbor.player.position = Vector3(s.anchor[0], 0.78, s.anchor[1]); harbor.player.velocity = Vector3.ZERO
func refresh() -> void:
	var s = store.view(); harbor.set_state(s); chapter.text = "雾灯归航 / 第一章\n" + STAGE_TEXT[s.stage]
	if mode == "menu": return
	if mode == "wardrobe": update_previews(); return
	if s.node != "": show_dialogue()
	elif not s.route.is_empty(): show_route()
	elif mode in ["dialogue", "route", "play"]:
		mode = "play"; clear_modal(); harbor.player.controls_enabled = true
		if s.stage == "complete": notice.text = "第一章完整收束。存档会保留选择与衣装；可以自由继续游玩。"
func toolbar(action: String) -> void:
	match action:
		"wardrobe": show_wardrobe()
		"journal": show_journal()
		"save": save_slot()
		"load": load_slot()
		"pause": show_pause()
func save_slot() -> void:
	if mode == "menu": return
	store.command("anchor", {"position": [harbor.player.position.x, harbor.player.position.z]})
	var r = store.save(); notice.text = "已保存 · 衣装、分支、当前对白和位置" if r.get("ok", false) else r.error
func load_slot() -> void:
	var r = store.load_game()
	if not r.get("ok", false): notice.text = r.error; hud.visible = true; return
	mode = "play"; hud.visible = true; restore_anchor(); refresh(); notice.text = "已恢复存档" + ("（使用有效备份）" if r.get("recovered",false) else "")
func show_dialogue() -> void:
	mode = "dialogue"; modal_base()
	var s = store.view(); var n: Dictionary = store.nodes[s.node]; speaker = n.speaker; mood = n.get("expression", "calm")
	# Modal occupies lower scene. Portrait is half-body, fully clothed, pixel filtered.
	var p = panel(Vector2(24, 439), Vector2(1232, 337)); modal.add_child(p)
	portrait = TextureRect.new(); portrait.position = Vector2(28, 445); portrait.size = Vector2(250, 300); portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; modal.add_child(portrait)
	portrait.texture = Art.portrait("star" if speaker == "narrator" else speaker, s.appearance, mood)
	if speaker == "narrator": portrait.modulate.a = 0.65
	p.add_child(text_label(NAMES[speaker], Vector2(275, 18), Vector2(730, 36), 25))
	var line = text_label(n.text, Vector2(275, 62), Vector2(885, 132), 22); p.add_child(line)
	var row = HBoxContainer.new(); row.position = Vector2(275, 203); row.size = Vector2(920, 90); row.add_theme_constant_override("separation", 12); p.add_child(row)
	var gen: int = store.generation; var ep: int = store.epoch; var rev: int = int(s.revision); var node: String = s.node
	var options: Array = n.get("choices", [])
	if options.is_empty():
		row.add_child(button("继续 [空格]", func(): select_line(node, 0, gen, ep, rev)))
	else:
		for i in range(options.size()):
			var b = button(str(i + 1) + "  " + options[i].text, func(): select_line(node, i, gen, ep, rev)); b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; b.custom_minimum_size = Vector2(288, 85); row.add_child(b)
	p.add_child(text_label("无计时 · 不计好感分 · 可随时存档或换装", Vector2(275, 305), Vector2(700,24), 14))
	var skip = button("本段摘要", func(): summary_current()); skip.position = Vector2(1095, 387); skip.size = Vector2(150,40); modal.add_child(skip)
	harbor.player.interact()
	if harbor.actors.has(speaker): harbor.actors[speaker].interact()
func select_line(node: String, index: int, gen: int, ep: int, rev: int) -> void:
	if choice_lock: return
	choice_lock = true
	var result = store.submit({"id": str(ep)+":"+str(gen)+":"+node+":"+str(index), "source":"dialogue", "epoch":ep, "generation":gen, "revision":rev, "action":"choose", "payload":{"node":node,"index":index}})
	if not result.get("ok",false): notice.text = result.error; choice_lock = false
	else:
		var r = store.save()
		if not r.get("ok",false): notice.text = r.error
func summary_current() -> void:
	# Skips prose only; stops at the next choice. All story facts use the same commit path.
	var count = 0
	while store.view().node != "" and count < 90:
		var s = store.view(); var n: Dictionary = store.nodes[s.node]
		if not n.get("choices", []).is_empty(): break
		store.command("choose", {"node":s.node,"index":0}); count += 1
	store.save()
	notice.text = "已记录本段内容，可在回看中阅读；表达选择仍由你决定。"
func show_wardrobe() -> void:
	mode = "wardrobe"; modal_base()
	var p = panel(Vector2(65, 86), Vector2(1150, 650)); modal.add_child(p)
	p.add_child(text_label("衣柜 · 今天想穿什么", Vector2(30,22), Vector2(780,50), 32))
	p.add_child(text_label("所有固定衣装直接可用。外观不影响身份、关系或能力。", Vector2(30,83), Vector2(1000,40), 18))
	wardrobe_full = TextureRect.new(); wardrobe_full.position = Vector2(48,158); wardrobe_full.size = Vector2(245,365); wardrobe_full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; wardrobe_full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; wardrobe_full.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; p.add_child(wardrobe_full)
	wardrobe_half = TextureRect.new(); wardrobe_half.position = Vector2(303,158); wardrobe_half.size = Vector2(270,325); wardrobe_half.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; wardrobe_half.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; wardrobe_half.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; p.add_child(wardrobe_half)
	p.add_child(text_label("全身 · 下装在这里显示", Vector2(55,540),Vector2(250,40),17)); p.add_child(text_label("半身 · 上衣 / 外套 / 配色同步", Vector2(290,540),Vector2(320,50),17))
	var specs = [["上衣", "top", [["shirt","衬衣"],["tunic","柔软短衫"]]], ["配色", "color", [["blue","雾蓝"],["cream","米白"],["green","铜绿"],["wine","莓红"]]], ["外套", "coat", [["short","短外套"],["long","长外套"],["none","只穿上衣"]]], ["下装", "bottom", [["work","工裤"],["wide","阔腿裤"],["culottes","裙裤"],["pleated","褶裙"],["long_skirt","长裙"]]]]
	var y = 143
	for spec in specs:
		p.add_child(text_label(spec[0], Vector2(635,y), Vector2(470,35),22)); y += 39
		var row = HBoxContainer.new(); row.position = Vector2(635,y); row.add_theme_constant_override("separation",6); p.add_child(row)
		for choice in spec[2]:
			row.add_child(button(choice[1], func(): var payload = {}; payload[spec[1]] = choice[0]; store.command("outfit",payload); notice.text = "已换装 · 立绘与场景人物同步"))
		y += 69
	var close = button("穿这套回港 [Esc]", func(): close_overlay()); close.position = Vector2(830,585); close.size = Vector2(270,45); p.add_child(close)
	update_previews()
func update_previews() -> void:
	var s = store.view()
	if wardrobe_full: wardrobe_full.texture = Art.sprite("star",s.appearance,0,"idle",0)
	if wardrobe_half: wardrobe_half.texture = Art.portrait("star",s.appearance,"smile", false)
func close_overlay() -> void:
	mode = "play"; clear_modal(); refresh()
func show_journal() -> void:
	mode = "journal"; modal_base()
	var p = panel(Vector2(125,70),Vector2(1030,660)); modal.add_child(p)
	p.add_child(text_label("今夜的回声 · 对话回看",Vector2(28,20),Vector2(850,50),30))
	var scroll = ScrollContainer.new(); scroll.position = Vector2(30,90); scroll.size = Vector2(968,475); p.add_child(scroll)
	var content = Label.new(); content.custom_minimum_size.x = 922; content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; content.add_theme_font_size_override("font_size",19); content.text = "\n\n".join(store.view().journal); scroll.add_child(content)
	var close = button("回到港口 [Esc]",func(): close_overlay()); close.position = Vector2(730,588); close.size = Vector2(268,43); p.add_child(close)
func show_pause() -> void:
	mode = "pause"; modal_base()
	var p = panel(Vector2(445,155),Vector2(390,480)); modal.add_child(p)
	p.add_child(text_label("港里歇一会儿",Vector2(30,25),Vector2(330,50),30))
	var v = VBoxContainer.new(); v.position = Vector2(30,110); v.size.x = 330; v.add_theme_constant_override("separation",15); p.add_child(v)
	v.add_child(button("继续",func(): close_overlay())); v.add_child(button("保存当前进度",func(): save_slot())); v.add_child(button("恢复上次存档",func(): load_slot())); v.add_child(button("回到标题",func(): show_menu())); v.add_child(button("离开试玩",func(): get_tree().quit()))
func show_route() -> void:
	mode = "route"; modal_base()
	var s = store.view(); var route: Dictionary = s.route
	var p = panel(Vector2(300,150),Vector2(680,470)); modal.add_child(p)
	var step: int = int(route.step)
	var events = ["雾中的浮标", "泊在礁后的旧船", "海鸟掠过的支流", "顺潮归港"]
	var title = events[(int(route.seed) + step) % 3] if step < 3 else events[3]
	p.add_child(text_label("短程听潮 · "+title,Vector2(30,24),Vector2(610,50),29))
	p.add_child(text_label("第 "+str(mini(step+1,3))+" / 3 段  ·  暖意 "+str(route.warmth)+"  ·  临时感受："+str(route.boon),Vector2(30,100),Vector2(600,50),20))
	p.add_child(text_label("这是一趟可选的短路线。听潮或远望，都能返回据点。故事与衣装始终保留。",Vector2(30,164),Vector2(600,90),22))
	var gen: int = store.generation; var ep: int = store.epoch; var rev: int = int(s.revision)
	var row = HBoxContainer.new(); row.position = Vector2(30,300); row.add_theme_constant_override("separation",15); p.add_child(row)
	if step < 3 and route.warmth > 0:
		for rest in [true,false]: row.add_child(button("靠岸听潮 · 暖意 +1" if rest else "迎风远望 · 暖意 −1",func(): store.submit({"id":str(ep)+":route:"+str(gen),"source":"route","epoch":ep,"generation":gen,"revision":rev,"action":"route_pick","payload":{"step":step,"rest":rest}}); store.save()))
	else: row.add_child(button("顺潮归港",func(): store.command("route_end"); store.save(); notice.text = "回到雾港。故事与衣装都还在。"))
	var back = button("现在返回据点 [Esc]",func(): store.command("route_end"); store.save()); back.position = Vector2(30,390); back.size = Vector2(600,43); p.add_child(back)
func interact_nearby() -> void:
	var id: String = harbor.nearest(); var stage: String = store.view().stage
	if id == "": return
	if id == "route": store.command("route_start",{"seed": randi_range(1,9999)}); return
	if id == "shen" and stage == "meet": id = "meet"
	if id in ["xu","qi"]: pass
	if id == "mirror": store.command("begin",{"target":"mirror"}); return
	if id == "cabin" and stage != "cabin": show_wardrobe(); return
	var r = store.command("begin",{"target":id})
	if not r.get("ok",false): notice.text = r.error
func _process(delta: float) -> void:
	anim_time += delta
	if mode == "play":
		var id: String = harbor.nearest()
		var descriptions = {"board":"看招工告示", "bag":"看图袋", "meet":"和砚舟交谈", "shen":"和砚舟交谈", "xu":"和知微交谈", "qi":"和祁岚交谈", "repair":"见证引灯演出", "cabin":"进入船舱 / 衣柜", "mirror":"照会儿镜子", "depart":"准备离港", "route":"可选短程听潮"}
		hint.text = "WASD 走动 · E 交谈 · C 衣柜" if id == "" else "[E / 空格] "+descriptions.get(id,id)
	var blink = fmod(anim_time, 4.0) > 3.78
	if portrait and blink != last_blink:
		portrait.texture = Art.portrait("star" if speaker == "narrator" else speaker,store.view().appearance,mood,blink)
	if wardrobe_half and blink != last_blink: wardrobe_half.texture = Art.portrait("star",store.view().appearance,"smile",blink)
	var frame = int(anim_time * 5) % 4
	if wardrobe_full and frame != last_sprite_frame: wardrobe_full.texture = Art.sprite("star",store.view().appearance,0,"walk",frame)
	last_blink = blink; last_sprite_frame = frame
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_C: if mode != "menu": show_wardrobe()
		KEY_J: if mode != "menu": show_journal()
		KEY_F5: save_slot()
		KEY_F9: load_slot()
		KEY_ESCAPE:
			if mode == "route": store.command("route_end"); store.save()
			elif mode in ["wardrobe","journal","pause"]: close_overlay()
			elif mode != "menu": show_pause()
		KEY_E, KEY_SPACE, KEY_ENTER:
			if mode == "play": interact_nearby()
			elif mode == "dialogue":
				var s = store.view()
				if store.nodes[s.node].get("choices",[]).is_empty(): select_line(s.node,0,store.generation,store.epoch,int(s.revision))
		KEY_1, KEY_2, KEY_3:
			if mode == "dialogue":
				var s = store.view(); var index: int = event.physical_keycode - KEY_1
				if index < store.nodes[s.node].get("choices",[]).size(): select_line(s.node,index,store.generation,store.epoch,int(s.revision))
		KEY_F12:
			get_viewport().get_texture().get_image().save_png("user://screenshot-"+str(Time.get_unix_time_from_system())+".png")
