class_name SidePanel
extends VBoxContainer
## 游戏内侧边面板：回合状态、玩家列表、操作提示+选项按钮、日志。
## 静态布局在 scenes/SidePanel.tscn（编辑器里改），本脚本只负责往里面填内容。
## 选项按钮是每次提问时动态生成的（数量与文案由引擎的 req 决定），容器为 %ButtonsBox。

## 玩家点了某个选项按钮；value 为该选项的语义值，null 表示点了"取消"
signal option_pressed(value)

@onready var _top: Label = %TopLabel
@onready var _event: Label = %EventLabel
@onready var _players: RichTextLabel = %PlayersRTL
@onready var _prompt: Label = %PromptLabel
@onready var _buttons: VBoxContainer = %ButtonsBox
@onready var _log: RichTextLabel = %LogRTL


## 每帧刷新顶部状态与玩家列表（main._process 调用）
func refresh(game, bridge) -> void:
	var line: String = game.phase_text
	if game.setup_done:
		line += "\n癌组织 %d / %d（癌细胞获胜线）" % [game.board.cancer_tissue_count(), game.win_threshold()]
	_top.text = line
	_event.text = ("最近世界事件：" + game.last_event_text) if game.last_event_text != "" else ""
	_players.text = _players_bb(game, bridge)


## 展示一次决策请求的提示与按钮。棋盘上的高亮由 main 负责，这里只管面板内的部分
func show_request(req: Dictionary) -> void:
	var who: String = req.get("who", "")
	var prompt: String = req.get("prompt", "")
	_prompt.text = ("【%s】" % who) + prompt if who != "" else prompt
	_clear_buttons()
	var t: String = req.get("type", "")
	if t == "pick_option":
		var labels: Array = req.get("labels", [])
		var values: Array = req.get("values", [])
		for i in range(labels.size()):
			var b := Button.new()
			b.text = _wrap(str(labels[i]), 28)
			b.pressed.connect(_emit_option.bind(values[i]))
			_buttons.add_child(b)
	elif t == "pick_hex":
		_add_tip("👉 点击棋盘上的黄色高亮格子")
	elif t == "pick_edge":
		_add_tip("👉 点击棋盘上高亮的边（墙壁位置）")
	var cancel: String = req.get("cancel", "")
	if cancel != "":
		var cb := Button.new()
		cb.text = cancel
		cb.add_theme_color_override("font_color", Color("#ffb74d"))
		cb.pressed.connect(_emit_option.bind(null))
		_buttons.add_child(cb)


func clear_request() -> void:
	_prompt.text = ""
	_clear_buttons()


func add_log(text: String) -> void:
	_log.add_text(text + "\n")


func clear_log() -> void:
	_log.clear()


func _emit_option(value) -> void:
	option_pressed.emit(value)


func _add_tip(text: String) -> void:
	var tip := Label.new()
	tip.text = text
	tip.add_theme_color_override("font_color", Color("#9ab3bd"))
	_buttons.add_child(tip)


func _clear_buttons() -> void:
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()


## 玩家列表 BBCode：行动标记、人机归属、生物质/墙存量、进化、能力卡、状态
func _players_bb(game, bridge) -> String:
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


## 长选项文案按固定宽度折行，避免把按钮撑出面板
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
