class_name CWWorld
extends RefCounted
## 世界回合开始流程：清理上一回合标记、固化计数衰减、第 10 回合进化选秀、
## 卡池激活与世界事件触发。事件的具体效果实现在 cw_events.gd。

var game: CWGame


func _init(p_game: CWGame) -> void:
	game = p_game


func round_start() -> void:
	var stage := "前期" if game.round_num <= 10 else "后期"
	game.log_line("")
	game.log_line("━━━━━ 世界回合 %d / %d（%s） ━━━━━" % [game.round_num, CWData.TOTAL_ROUNDS, stage])
	game.phase_text = "世界回合 %d / %d" % [game.round_num, CWData.TOTAL_ROUNDS]
	# 清除上一世界回合的标记
	game.flag_all_crit = false
	game.flag_walls_off = false
	game.flag_immune_atk = 0
	game.flag_immune_rage = false
	game.flag_move_bonus_immune = 0
	game.flag_move_bonus_cancer = 0
	game.flag_no_attack = false
	game.flag_rest = false
	for p in game.players:
		p.skip_this_round = false
	# 固化计数衰减：无癌细胞驻守的普通癌组织，计数 -1
	var decayed: Array = []
	for h in game.board.solid_count.keys():
		var occupied := false
		for p in game.living_players(CWData.FACTION_CANCER):
			if p.pos == h:
				occupied = true
		if not occupied:
			var n: int = game.board.solid_count[h] - 1
			if n <= 0:
				game.board.solid_count.erase(h)
			else:
				game.board.solid_count[h] = n
			decayed.append(h)
	if not decayed.is_empty():
		game.log_line("固化计数衰减：%d 处无癌细胞驻守的固化计数 -1。" % decayed.size())
	# 第 10 回合开始时：进化
	if game.round_num == 10:
		await _evolution_draft()
	# 卡池激活 + 世界事件：前期第 3/6/9 回合；后期偶数回合
	var trigger := false
	if game.round_num <= 10:
		trigger = game.round_num in [3, 6, 9]
	else:
		trigger = game.round_num % 2 == 0
	if trigger:
		game.board.activate_all_pools()
		game.log_line("🃏 棋盘上的所有【卡池】变为激活状态！")
		await _trigger_world_event()
	game.touch()


func _evolution_draft() -> void:
	game.log_line("🧬 第 10 回合：所有玩家按行动顺序进行【进化】！")
	for p in game.players:
		var table = CWData.EVOS_IMMUNE if p.is_immune() else CWData.EVOS_CANCER
		var taken: Array = []
		for q in game.players:
			if q.faction == p.faction and q.evo != "":
				taken.append(q.evo)
		var labels: Array = []
		var values: Array = []
		for e in table:
			if not taken.has(e["id"]):
				labels.append("%s：%s" % [e["name"], e["text"]])
				values.append(e["id"])
		if values.is_empty():
			continue
		var pick = await game.ask_option(p, "%s 选择进化能力（不可与队友重复）" % p.pname, labels, values)
		if pick == null:
			pick = values[0]
		p.evo = pick
		game.log_line("🧬 %s 进化为【%s】" % [p.pname, CWData.evo_def(p.faction, pick)["name"]])
		game.touch()


func _trigger_world_event() -> void:
	var pool: Array = []
	for e in CWData.WORLD_EVENTS:
		if e["limited"] and game.used_limited.has(e["id"]):
			continue
		pool.append(e)
	var ev: Dictionary = pool[game.rng.randi_range(0, pool.size() - 1)]
	if ev["limited"]:
		game.used_limited.append(ev["id"])
	var side_cn := "共同事件"
	if ev["side"] == "immune":
		side_cn = "免疫事件"
	elif ev["side"] == "cancer":
		side_cn = "癌症事件"
	game.last_event_text = "【%s】%s" % [ev["name"], ev["text"]]
	game.log_line("🌍 世界事件（%s）——【%s】：%s" % [side_cn, ev["name"], ev["text"]])
	game.touch()
	await game.events.apply(ev["id"])
	game.touch()
