extends SceneTree
## MC 搜索桥胜率基准（手动运行，不进 CI；跑一次约几十秒）：
##   godot --headless --path game -s tests/mc_benchmark.gd
## 对比同一批种子下的癌症胜率：
##   基线 = 双方启发式（历史战绩免疫 11:1 占优）
##   实验 = 癌症用 MC 推演，免疫仍用启发式

const SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1010, 1111, 1212]
const PLAYOUTS := 10
const HORIZON := 4
const MAX_CANDIDATES := 8
const VALIDATE := false   # 回放对齐自检（开着约慢 10 倍，抽查时才开）


func _init() -> void:
	print("=== MC 胜率基准：%d 个种子 ===" % SEEDS.size())
	var base_wins := 0
	for s in SEEDS:
		if await _heuristic_game(s) == CWData.FACTION_CANCER:
			base_wins += 1
	print("基线（双方启发式）      ：癌症胜 %d / %d" % [base_wins, SEEDS.size()])
	var mc_wins := 0
	var total_searches := 0
	var total_playouts := 0
	var total_mismatch := 0
	var t0 := Time.get_ticks_msec()
	for s in SEEDS:
		var r: Array = await _mc_game(s)
		if r[0] == CWData.FACTION_CANCER:
			mc_wins += 1
		total_searches += r[1]
		total_playouts += r[2]
		total_mismatch += r[3]
	var dt := Time.get_ticks_msec() - t0
	print("MC 癌症（K=%d, 视界=%d）：癌症胜 %d / %d" % [PLAYOUTS, HORIZON, mc_wins, SEEDS.size()])
	print("共 %d 次搜索、%d 局推演，总耗时 %d ms（平均每局 %d ms）" %
		[total_searches, total_playouts, dt, dt / SEEDS.size()])
	var mci_wins := 0
	for s in SEEDS:
		var r2: Array = await _mc_game(s, CWData.FACTION_IMMUNE)
		if r2[0] == CWData.FACTION_IMMUNE:
			mci_wins += 1
		total_mismatch += r2[3]
	print("MC 免疫（K=%d, 视界=%d）：免疫胜 %d / %d（基线免疫胜 %d / %d）" %
		[PLAYOUTS, HORIZON, mci_wins, SEEDS.size(), SEEDS.size() - base_wins, SEEDS.size()])
	if total_mismatch > 0:
		print("⚠️ 回放对齐自检失败 %d 次——快照/回放机制有 bug，胜率数字不可信！" % total_mismatch)
	else:
		print("回放对齐自检：全部一致 ✓")
	quit(0)


func _heuristic_game(seed_value: int) -> String:
	var bridge := HybridBridge.new(seed_value)
	bridge.tree = null
	bridge.human_faction = ""
	var game := CWGame.new(bridge, 4, seed_value)
	bridge.game = game
	await game.run_setup()
	await game.run_game()
	var w := String(game.winner)
	game.dispose()
	return w


func _mc_game(seed_value: int, faction: String = CWData.FACTION_CANCER) -> Array:
	var bridge := MCBridge.new(seed_value)
	bridge.tree = null
	bridge.human_faction = ""
	bridge.mc_faction = faction
	bridge.playouts = PLAYOUTS
	bridge.horizon = HORIZON
	bridge.max_candidates = MAX_CANDIDATES
	bridge.validate_replay = VALIDATE
	var game := CWGame.new(bridge, 4, seed_value)
	bridge.game = game
	await game.run_setup()
	await game.run_game()
	var out := [String(game.winner), bridge.stat_searches, bridge.stat_playouts,
		bridge.stat_replay_mismatch]
	game.dispose()
	return out
