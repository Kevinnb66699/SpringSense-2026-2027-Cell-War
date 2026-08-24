extends SceneTree
## 无头自动测试：用随机策略跑完整局游戏，校验核心不变量。
## 运行方式（在 game/ 目录下）：
##   godot --headless -s tests/headless_test.gd
## 输出 ALL TESTS PASSED 表示通过；退出码为失败数。

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)


func _init() -> void:
	print("=== Cell War 无头测试开始 ===")
	_test_all_scripts_compile()
	_test_hexlib()
	var seeds := [11, 22, 33, 44]
	for i in range(seeds.size()):
		var n := 4 if i % 2 == 0 else 6
		await _run_full_game(n, seeds[i])
	if failures == 0:
		print("=== ALL TESTS PASSED ===")
	else:
		printerr("=== %d 项检查失败 ===" % failures)
	quit(failures)


## 加载全部 .gd 脚本与主场景，确保没有解析错误（UI 脚本不会被对局测试覆盖）
func _test_all_scripts_compile() -> void:
	var to_scan: Array[String] = ["res://scripts", "res://tests"]
	var n_checked := 0
	while not to_scan.is_empty():
		var dir_path: String = to_scan.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			check(false, "无法打开目录 " + dir_path)
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			var full := dir_path + "/" + fname
			if dir.current_is_dir():
				if not fname.begins_with("."):
					to_scan.append(full)
			elif fname.ends_with(".gd"):
				var res = load(full)
				check(res != null, "脚本解析失败: " + full)
				n_checked += 1
			fname = dir.get_next()
		dir.list_dir_end()
	var scene = load("res://scenes/Main.tscn")
	check(scene != null, "主场景加载失败: res://scenes/Main.tscn")
	print("脚本编译检查完成（%d 个脚本 + 主场景）" % n_checked)


func _test_hexlib() -> void:
	check(HexLib.all_cells().size() == 61, "棋盘应有 61 格，实际 %d" % HexLib.all_cells().size())
	check(HexLib.distance(Vector2i.ZERO, Vector2i(4, 0)) == 4, "六边形距离计算错误")
	check(HexLib.distance(Vector2i(-4, 0), Vector2i(4, 0)) == 8, "六边形距离计算错误(对角)")
	check(HexLib.neighbors(Vector2i.ZERO).size() == 6, "邻居数量应为 6")
	var ek := HexLib.edge_key(Vector2i(1, 0), Vector2i(0, 0))
	check(ek == HexLib.edge_key(Vector2i(0, 0), Vector2i(1, 0)), "边的规范化不对称")
	var cells := HexLib.edge_cells(ek)
	check(cells.size() == 2 and cells.has(Vector2i(0, 0)) and cells.has(Vector2i(1, 0)), "edge_cells 还原失败")
	var corners := HexLib.edge_corners(Vector2i(0, 0), Vector2i(1, 0))
	check(corners.size() == 2 and corners[0] != corners[1], "边应有两个不同角点")
	# 相邻两条边应共享一个角点
	var c1 := HexLib.edge_corners(Vector2i(0, 0), Vector2i(1, 0))
	var c2 := HexLib.edge_corners(Vector2i(0, 0), Vector2i(1, -1))
	var shared := false
	for a in c1:
		for b in c2:
			if a == b:
				shared = true
	check(shared, "同一格相邻的两条边应共享角点")
	# 官方地图布局应全部在棋盘内且互不重叠
	check(CWData.OFFICIAL_LAYOUT.size() == 8, "官方布局应有 8 个特殊事件")
	for h in CWData.OFFICIAL_LAYOUT:
		check(HexLib.in_board(h), "官方布局位置 %s 不在棋盘内" % str(h))
	# 官方癌组织布局不与特殊事件相邻
	for h in CWData.official_cancer_layout():
		check(not CWData.OFFICIAL_LAYOUT.has(h), "官方癌组织与特殊事件重合")
		for nb in HexLib.neighbors(h):
			check(not CWData.OFFICIAL_LAYOUT.has(nb), "官方癌组织与特殊事件相邻: %s" % str(h))
	print("HexLib / 数据表检查完成")


func _run_full_game(n_players: int, seed_value: int) -> void:
	var bridge := DemoBridge.new(seed_value)
	bridge.tree = null  # 无延迟
	var game := CWGame.new(bridge, n_players, seed_value)
	await game.run_setup()
	check(game.setup_done, "布置阶段未完成")
	check(game.board.cancer_tissue_count() == 7, "开局癌组织应为 7 块")
	for p in game.players:
		check(HexLib.in_board(p.pos), "玩家初始位置不在棋盘内")
		if p.is_cancer():
			check(game.board.is_cancer_tissue(p.pos), "癌细胞初始位置应为癌组织")
		else:
			check(game.board.tissue_at(p.pos) == CWData.Tissue.NORMAL, "免疫细胞初始位置应为正常组织")
	await game.run_game()
	check(game.game_over, "游戏应已结束")
	check(game.winner != "", "应有获胜阵营")
	check(game.round_num <= CWData.TOTAL_ROUNDS, "回合数越界")
	for p in game.players:
		check(p.biomass >= 0 and p.biomass <= CWData.MAX_BIOMASS,
			"%s 生物质越界: %d" % [p.pname, p.biomass])
		check(HexLib.in_board(p.pos), "%s 位置在棋盘外" % p.pname)
		if p.alive:
			check(p.biomass >= 1, "%s 存活但生物质为 0" % p.pname)
		if p.evo != "":
			check(CWData.evo_def(p.faction, p.evo).size() > 0, "%s 进化 id 非法" % p.pname)
	# 墙壁边必须合法（两端都在棋盘内）
	for k in game.board.walls:
		var wc := HexLib.edge_cells(k)
		check(HexLib.in_board(wc[0]) and HexLib.in_board(wc[1]), "墙壁边越界: %s" % k)
	# 组织总数不变
	check(game.board.tissue.size() == 61, "组织总数应恒为 61")
	print("完整对局测试通过：%d 人局 seed=%d，%d 回合后 %s 获胜（%s）" %
		[n_players, seed_value, game.round_num, CWData.faction_cn(game.winner), game.win_reason])
