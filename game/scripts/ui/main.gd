extends Control
## 主控制器：主菜单、游戏内界面、问答桥接线。全部 UI 由代码构建。

var game = null      # CWGame
var bridge = null    # UIBridge / DemoBridge
var pending_req: Dictionary = {}

var board_view: BoardView
var top_label: Label
var event_label: Label
var players_rtl: RichTextLabel
var prompt_label: Label
var buttons_box: VBoxContainer
var buttons_scroll: ScrollContainer
var log_rtl: RichTextLabel
var menu_layer: CenterContainer
var menu_vbox: VBoxContainer


func _ready() -> void:
	theme = _make_theme()
	_build_ui()
	_show_menu("")


func _process(_delta: float) -> void:
	if game != null:
		_refresh()


# ==================== 主题 ====================

func _make_theme() -> Theme:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei",
		"Noto Sans CJK SC", "Noto Sans SC", "PingFang SC",
		"WenQuanYi Micro Hei", "sans-serif",
	])
	var th := Theme.new()
	th.default_font = f
	th.default_font_size = 18

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color("#1f3540")
	btn_normal.set_corner_radius_all(6)
	btn_normal.content_margin_left = 12.0
	btn_normal.content_margin_right = 12.0
	btn_normal.content_margin_top = 7.0
	btn_normal.content_margin_bottom = 7.0
	var btn_hover: StyleBoxFlat = btn_normal.duplicate()
	btn_hover.bg_color = Color("#2a4a58")
	var btn_pressed: StyleBoxFlat = btn_normal.duplicate()
	btn_pressed.bg_color = Color("#35607a")
	var btn_focus: StyleBoxFlat = btn_hover.duplicate()
	th.set_stylebox("normal", "Button", btn_normal)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_pressed)
	th.set_stylebox("focus", "Button", btn_focus)
	th.set_color("font_color", "Button", Color("#dfe9ec"))
	th.set_color("font_hover_color", "Button", Color("#ffffff"))
	th.set_color("font_pressed_color", "Button", Color("#ffffff"))

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#131f26")
	panel.set_corner_radius_all(8)
	panel.border_color = Color("#24404c")
	panel.set_border_width_all(1)
	panel.content_margin_left = 10.0
	panel.content_margin_right = 10.0
	panel.content_margin_top = 8.0
	panel.content_margin_bottom = 8.0
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


# ==================== 构建界面 ====================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0a1114")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	board_view = BoardView.new()
	board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.size_flags_stretch_ratio = 2.6
	board_view.hex_clicked.connect(_on_board_hex)
	board_view.edge_clicked.connect(_on_board_edge)
	hbox.add_child(board_view)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(510, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	hbox.add_child(side)

	# 标题与状态
	var head := PanelContainer.new()
	side.add_child(head)
	var head_v := VBoxContainer.new()
	head.add_child(head_v)
	var title := Label.new()
	title.text = "CELL WAR  细胞战争"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#8fd6e8"))
	head_v.add_child(title)
	top_label = Label.new()
	top_label.text = ""
	top_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_v.add_child(top_label)
	event_label = Label.new()
	event_label.text = ""
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.add_theme_font_size_override("font_size", 15)
	event_label.add_theme_color_override("font_color", Color("#ffd75e"))
	head_v.add_child(event_label)

	# 玩家面板
	var pp := PanelContainer.new()
	side.add_child(pp)
	players_rtl = RichTextLabel.new()
	players_rtl.bbcode_enabled = true
	players_rtl.fit_content = true
	players_rtl.scroll_active = false
	players_rtl.custom_minimum_size = Vector2(0, 140)
	pp.add_child(players_rtl)

	# 操作提示 + 按钮
	var op := PanelContainer.new()
	side.add_child(op)
	var op_v := VBoxContainer.new()
	op_v.add_theme_constant_override("separation", 6)
	op.add_child(op_v)
	prompt_label = Label.new()
	prompt_label.text = ""
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_color_override("font_color", Color("#ffe9a8"))
	op_v.add_child(prompt_label)
	buttons_scroll = ScrollContainer.new()
	buttons_scroll.custom_minimum_size = Vector2(0, 240)
	buttons_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	op_v.add_child(buttons_scroll)
	buttons_box = VBoxContainer.new()
	buttons_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_box.add_theme_constant_override("separation", 5)
	buttons_scroll.add_child(buttons_box)

	# 日志
	var lp := PanelContainer.new()
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(lp)
	log_rtl = RichTextLabel.new()
	log_rtl.bbcode_enabled = false
	log_rtl.scroll_following = true
	log_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rtl.add_theme_font_size_override("normal_font_size", 15)
	lp.add_child(log_rtl)

	# 主菜单层
	menu_layer = CenterContainer.new()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_layer)
	var mp := PanelContainer.new()
	mp.custom_minimum_size = Vector2(520, 0)
	menu_layer.add_child(mp)
	menu_vbox = VBoxContainer.new()
	menu_vbox.add_theme_constant_override("separation", 10)
	mp.add_child(menu_vbox)


func _show_menu(result_text: String) -> void:
	for c in menu_vbox.get_children():
		menu_vbox.remove_child(c)
		c.queue_free()
	var t := Label.new()
	t.text = "CELL WAR"
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", Color("#8fd6e8"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_vbox.add_child(t)
	var st := Label.new()
	st.text = "细胞战争 · 桌游电子版 ver 0.98"
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_color_override("font_color", Color("#9ab3bd"))
	menu_vbox.add_child(st)
	if result_text != "":
		var rl := Label.new()
		rl.text = result_text
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.add_theme_color_override("font_color", Color("#ffd75e"))
		rl.add_theme_font_size_override("font_size", 18)
		menu_vbox.add_child(rl)
	_menu_section("人机对战（你控制整个阵营，AI 控制对方）")
	_menu_row([
		["执免疫 · 4 人局", _start.bind(4, "ai", CWData.FACTION_IMMUNE)],
		["执癌症 · 4 人局", _start.bind(4, "ai", CWData.FACTION_CANCER)],
	])
	_menu_row([
		["执免疫 · 6 人局", _start.bind(6, "ai", CWData.FACTION_IMMUNE)],
		["执癌症 · 6 人局", _start.bind(6, "ai", CWData.FACTION_CANCER)],
	])
	_menu_section("本地对战（热座，所有玩家轮流操作本机）")
	_menu_row([
		["4 人局", _start.bind(4, "pvp", "")],
		["6 人局", _start.bind(6, "pvp", "")],
	])
	_menu_section("观战演示（双方均由 AI 随机操作）")
	_menu_row([
		["演示 · 4 人局", _start.bind(4, "demo", "")],
		["演示 · 6 人局", _start.bind(6, "demo", "")],
	])
	var hint := Label.new()
	hint.text = "黄色高亮 = 可点击的棋盘格 / 墙壁位置。窗口可任意拉大，界面会等比缩放。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("#7d949e"))
	menu_vbox.add_child(hint)
	menu_layer.visible = true


func _menu_section(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("#9ab3bd"))
	menu_vbox.add_child(lbl)


func _menu_row(buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	menu_vbox.add_child(row)
	for item in buttons:
		var b := Button.new()
		b.text = item[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(item[1])
		row.add_child(b)


# ==================== 开局 / 主循环 ====================

func _start(n_players: int, mode: String, human_faction: String) -> void:
	menu_layer.visible = false
	log_rtl.clear()
	pending_req = {}
	if mode == "demo":
		bridge = DemoBridge.new()
		bridge.tree = get_tree()
	elif mode == "ai":
		bridge = HybridBridge.new()
		bridge.main = self
		bridge.tree = get_tree()
		bridge.human_faction = human_faction
	else:
		bridge = UIBridge.new()
		bridge.main = self
	bridge.log_added.connect(_on_log)
	game = CWGame.new(bridge, n_players)
	if bridge is HybridBridge:
		bridge.game = game
		log_rtl.add_text("人机对战：你执【%s】阵营，对方由 AI 操作。\n" % CWData.faction_cn(human_faction))
	board_view.game = game
	_run_async()


func _run_async() -> void:
	var g = game
	await g.run_setup()
	if g != game:
		return
	await g.run_game()
	if g != game:
		return
	_show_menu(game.win_reason)


# ==================== 每帧刷新 ====================

func _refresh() -> void:
	var threshold: int = game.win_threshold()
	var count: int = game.board.cancer_tissue_count()
	var line: String = game.phase_text
	if game.setup_done:
		line += "\n癌组织 %d / %d（癌细胞获胜线）" % [count, threshold]
	top_label.text = line
	event_label.text = ("最近世界事件：" + game.last_event_text) if game.last_event_text != "" else ""
	players_rtl.text = _players_bb()
	board_view.queue_redraw()


func _players_bb() -> String:
	var bb := ""
	var cur = game.cur_player()
	var human_f := ""
	var is_hybrid := bridge is HybridBridge
	if is_hybrid:
		human_f = bridge.human_faction
	for p in game.players:
		var c := "#4fc3f7" if p.is_immune() else "#ef5350"
		var mark := "▶ " if (cur != null and cur == p) else "    "
		var ctrl := ""
		if is_hybrid:
			ctrl = "·你" if p.faction == human_f else "·AI"
		bb += "[color=%s][b]%s%s%s[/b][/color]  " % [c, mark, p.pname, ctrl]
		if p.alive:
			bb += "生物质 [b]%d[/b]/5" % p.biomass
			if p.is_cancer() and p.walls_stock > 0:
				bb += "  墙×%d" % p.walls_stock
		else:
			bb += "[color=#7a8a92]死亡[/color]"
		if p.evo != "":
			var ed := CWData.evo_def(p.faction, p.evo)
			bb += "  [color=#ffd75e]%s[/color]" % ed.get("name", "")
		if not p.abilities.is_empty():
			var names: Array = []
			for aid in p.abilities:
				names.append(CWData.card_def(p.faction, aid)["name"])
			bb += "  [color=#a5d6a7]%s[/color]" % "、".join(names)
		var tags: Array[String] = p.status_tags()
		if not tags.is_empty():
			bb += "  [color=#ff9d3b]%s[/color]" % " ".join(tags)
		bb += "\n"
	return bb


# ==================== 问答桥回调 ====================

func show_request(req: Dictionary) -> void:
	pending_req = req
	var who: String = req.get("who", "")
	var prompt: String = req.get("prompt", "")
	prompt_label.text = ("【%s】" % who) + prompt if who != "" else prompt
	_clear_buttons()
	var cancel: String = req.get("cancel", "")
	var t: String = req.get("type", "")
	if t == "pick_option":
		var labels: Array = req.get("labels", [])
		var values: Array = req.get("values", [])
		for i in range(labels.size()):
			var b := Button.new()
			b.text = _wrap(str(labels[i]), 28)
			b.pressed.connect(_on_option_pressed.bind(values[i]))
			buttons_box.add_child(b)
	elif t == "pick_hex":
		board_view.set_pick_hex(req.get("options", []))
		var tip := Label.new()
		tip.text = "👉 点击棋盘上的黄色高亮格子"
		tip.add_theme_color_override("font_color", Color("#9ab3bd"))
		buttons_box.add_child(tip)
	elif t == "pick_edge":
		board_view.set_pick_edge(req.get("options", []))
		var tip2 := Label.new()
		tip2.text = "👉 点击棋盘上高亮的边（墙壁位置）"
		tip2.add_theme_color_override("font_color", Color("#9ab3bd"))
		buttons_box.add_child(tip2)
	if cancel != "":
		var cb := Button.new()
		cb.text = cancel
		cb.add_theme_color_override("font_color", Color("#ffb74d"))
		cb.pressed.connect(_on_option_pressed.bind(null))
		buttons_box.add_child(cb)


func clear_request() -> void:
	pending_req = {}
	prompt_label.text = ""
	_clear_buttons()
	board_view.clear_pick()


func _clear_buttons() -> void:
	for c in buttons_box.get_children():
		buttons_box.remove_child(c)
		c.queue_free()


func _on_option_pressed(value) -> void:
	if bridge != null and bridge.has_method("answer"):
		bridge.answer(value)


func _on_board_hex(h: Vector2i) -> void:
	if pending_req.get("type", "") == "pick_hex" and bridge != null and bridge.has_method("answer"):
		bridge.answer(h)


func _on_board_edge(k: String) -> void:
	if pending_req.get("type", "") == "pick_edge" and bridge != null and bridge.has_method("answer"):
		bridge.answer(k)


func _on_log(text: String) -> void:
	log_rtl.add_text(text + "\n")


func _wrap(s: String, width: int) -> String:
	if s.length() <= width:
		return s
	var out := ""
	var i := 0
	while i < s.length():
		out += s.substr(i, width)
		i += width
		if i < s.length():
			out += "\n"
	return out
