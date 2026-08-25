class_name CWSetup
extends RefCounted
## 布置阶段：特殊事件布置 → 癌组织选择 → 初始位置。
## 想调整开局规则（禁放范围、官方布局候选等）改这里即可。

var game: CWGame


func _init(p_game: CWGame) -> void:
	game = p_game


func run() -> void:
	game.phase_text = "布置阶段：特殊事件"
	game.touch()
	await _setup_specials()
	game.phase_text = "布置阶段：癌组织"
	game.touch()
	await _setup_cancer_tissues()
	game.phase_text = "布置阶段：初始位置"
	game.touch()
	await _setup_positions()
	game.setup_done = true
	game.log_line("—— 布置完成，游戏开始！——")
	game.touch()


func _setup_specials() -> void:
	var mode = await game.ask_option(CWData.FACTION_IMMUNE, "由免疫阵营决定特殊事件的位置",
		["使用官方地图布局（推荐）", "自定义布置"], ["official", "custom"])
	if mode == "official" or mode == null:
		for h in CWData.OFFICIAL_LAYOUT:
			game.board.place_special(h, CWData.OFFICIAL_LAYOUT[h])
		game.log_line("特殊事件采用官方地图布局。")
		game.touch()
		return
	var to_place := [
		[CWData.SP_POOL, "卡池 1/4"], [CWData.SP_POOL, "卡池 2/4"],
		[CWData.SP_POOL, "卡池 3/4"], [CWData.SP_POOL, "卡池 4/4"],
		[CWData.SP_VESSEL, "血管 1/2"], [CWData.SP_VESSEL, "血管 2/2"],
		[CWData.SP_BIO, "生物质工厂"], [CWData.SP_WALL, "墙壁工厂"],
	]
	for item in to_place:
		var free: Array = []
		for h in HexLib.all_cells():
			if not game.board.specials.has(h):
				free.append(h)
		var pick = await game.ask_hex(CWData.FACTION_IMMUNE, "放置【%s】" % item[1], free)
		if pick == null:
			pick = free[0]
		game.board.place_special(pick, item[0])
		game.touch()
	game.log_line("特殊事件布置完成。")


func _setup_cancer_tissues() -> void:
	# 癌组织不能与特殊事件重合，也不能位于其周围
	var forbidden: Dictionary = {}
	for h in game.board.specials:
		forbidden[h] = true
		for n in HexLib.neighbors(h):
			forbidden[n] = true
	var official: Array[Vector2i] = CWData.official_cancer_layout()
	var official_ok := true
	for h in official:
		if forbidden.has(h):
			official_ok = false
	var labels := ["自定义选择 7 块"]
	var values := ["custom"]
	if official_ok:
		labels.push_front("官方示例布局（中心花型）")
		values.push_front("official")
	var mode = await game.ask_option(CWData.FACTION_CANCER, "由癌细胞阵营选择 7 块癌组织（不能在特殊事件及其周围）", labels, values)
	if mode == "official":
		for h in official:
			game.board.tissue[h] = CWData.Tissue.CANCER
		game.log_line("癌组织采用官方示例布局（中心花型）。")
		game.touch()
		return
	for i in range(CWData.CANCER_TISSUE_START):
		var valid: Array = []
		for h in HexLib.all_cells():
			if not forbidden.has(h) and game.board.tissue_at(h) == CWData.Tissue.NORMAL:
				valid.append(h)
		var pick = await game.ask_hex(CWData.FACTION_CANCER, "选择第 %d/7 块癌组织" % (i + 1), valid)
		if pick == null:
			pick = valid[0]
		game.board.tissue[pick] = CWData.Tissue.CANCER
		game.touch()
	game.log_line("癌组织选择完成。")


func _setup_positions() -> void:
	for p in game.players:
		var valid: Array = []
		if p.is_cancer():
			for h in game.board.cancer_tissues():
				valid.append(h)
		else:
			for h in HexLib.all_cells():
				if game.board.tissue_at(h) == CWData.Tissue.NORMAL:
					valid.append(h)
		var tip := "癌组织" if p.is_cancer() else "正常组织"
		var pick = await game.ask_hex(p, "%s 选择初始位置（%s）" % [p.pname, tip], valid, "", {"tag": "setup_pos"})
		if pick == null:
			pick = valid[0]
		p.pos = pick
		game.log_line("%s 初始位置已就位。" % p.pname)
		game.touch()
