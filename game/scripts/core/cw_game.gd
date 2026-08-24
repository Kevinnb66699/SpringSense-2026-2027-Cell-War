class_name CWGame
extends RefCounted
## 游戏流程状态机：完整实现《Cell War》ver.0.98 规则。
## 所有需要玩家决策的地方通过 bridge.ask() 问答（UI 或自动测试提供答案）。

var board: CWBoard
var players: Array = []          # CWPlayer，按行动顺序
var decks: Dictionary = {}       # faction -> CWDeck
var bridge                        # CWBridge
var rng := RandomNumberGenerator.new()

var num_players := 4
var round_num := 0               # 1..20
var cur_player_idx := -1
var game_over := false
var winner := ""                 # 获胜阵营
var win_reason := ""
var setup_done := false

# ---- 本世界回合有效的标记 ----
var flag_all_crit := false        # 战斗狂潮
var flag_walls_off := false       # 洪水
var flag_immune_atk := 0          # 炎症风暴
var flag_immune_rage := false     # 免疫暴走
var flag_move_bonus_immune := 0   # 免疫巡逻
var flag_move_bonus_cancer := 0   # 癌症渗透
var flag_no_attack := false       # 免疫逃逸
var flag_rest := false            # 休养生息

# ---- 永久增益 ----
var perm_wall_bonus := 0          # 地狱制造（限定）
var perm_bio_bonus := 0           # 天堂制造（限定）
var used_limited: Array[String] = []

# ---- 当前回合状态 ----
var extra_moves := 0              # 额外移动机会（Information detection / Infiltration）
var phase_text := ""              # UI 顶栏
var last_event_text := ""         # 最近一次世界事件


func _init(p_bridge, p_num_players: int = 4, seed_value: int = 0) -> void:
	bridge = p_bridge
	num_players = p_num_players
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	board = CWBoard.new()
	decks[CWData.FACTION_IMMUNE] = CWDeck.new(CWData.FACTION_IMMUNE, rng)
	decks[CWData.FACTION_CANCER] = CWDeck.new(CWData.FACTION_CANCER, rng)
	_create_players()


func _create_players() -> void:
	# 4 人：免疫A-癌症A-免疫B-癌症B
	# 6 人：免疫A-癌症A-癌症B-免疫B-免疫C-癌症C
	var order: Array = []
	if num_players == 4:
		order = [
			[CWData.FACTION_IMMUNE, "免疫A"], [CWData.FACTION_CANCER, "癌症A"],
			[CWData.FACTION_IMMUNE, "免疫B"], [CWData.FACTION_CANCER, "癌症B"],
		]
	else:
		order = [
			[CWData.FACTION_IMMUNE, "免疫A"], [CWData.FACTION_CANCER, "癌症A"],
			[CWData.FACTION_CANCER, "癌症B"], [CWData.FACTION_IMMUNE, "免疫B"],
			[CWData.FACTION_IMMUNE, "免疫C"], [CWData.FACTION_CANCER, "癌症C"],
		]
	for i in range(order.size()):
		var p := CWPlayer.new()
		p.id = i
		p.faction = order[i][0]
		p.pname = order[i][1]
		players.append(p)


# ==================== 通用工具 ====================

func log_line(text: String) -> void:
	bridge.log_line(text)


func touch() -> void:
	bridge.notify_changed()


func d6(reason: String = "") -> int:
	var v := rng.randi_range(1, 6)
	await bridge.show_roll(reason, v)
	if reason != "":
		log_line("🎲 %s：掷出 %d" % [reason, v])
	return v


func ask_option(who: String, prompt: String, labels: Array, values: Array, cancel: String = ""):
	return await bridge.ask({
		"type": "pick_option", "who": who, "prompt": prompt,
		"labels": labels, "values": values, "cancel": cancel,
	})


func ask_hex(who: String, prompt: String, options: Array, cancel: String = "", extra: Dictionary = {}):
	var req := {
		"type": "pick_hex", "who": who, "prompt": prompt,
		"options": options, "cancel": cancel,
	}
	for k in extra:
		req[k] = extra[k]
	return await bridge.ask(req)


func ask_edge(who: String, prompt: String, options: Array, cancel: String = ""):
	return await bridge.ask({
		"type": "pick_edge", "who": who, "prompt": prompt,
		"options": options, "cancel": cancel,
	})


func living_players(faction: String = "") -> Array:
	var out: Array = []
	for p in players:
		if p.alive and (faction == "" or p.faction == faction):
			out.append(p)
	return out


func dead_players(faction: String = "") -> Array:
	var out: Array = []
	for p in players:
		if not p.alive and (faction == "" or p.faction == faction):
			out.append(p)
	return out


func players_at(pos: Vector2i) -> Array:
	var out: Array = []
	for p in players:
		if p.alive and p.pos == pos:
			out.append(p)
	return out


func cur_player():
	if cur_player_idx >= 0 and cur_player_idx < players.size():
		return players[cur_player_idx]
	return null


## 攻击距离：免疫细胞受墙壁影响（除非无视墙壁或洪水），返回 -1 表示不可及
func attack_dist(atk, tgt_pos: Vector2i, max_range: int) -> int:
	if atk.ignores_walls() or flag_walls_off:
		var dd := HexLib.distance(atk.pos, tgt_pos)
		return dd if dd <= max_range else -1
	return board.walk_distance(atk.pos, tgt_pos, false, max_range)


func win_threshold() -> int:
	return CWData.WIN_TISSUE_4P if num_players == 4 else CWData.WIN_TISSUE_6P


# ==================== 布置阶段 ====================

func run_setup() -> void:
	phase_text = "布置阶段：特殊事件"
	touch()
	await _setup_specials()
	phase_text = "布置阶段：癌组织"
	touch()
	await _setup_cancer_tissues()
	phase_text = "布置阶段：初始位置"
	touch()
	await _setup_positions()
	setup_done = true
	log_line("—— 布置完成，游戏开始！——")
	touch()


func _setup_specials() -> void:
	var mode = await ask_option("免疫阵营", "由免疫阵营决定特殊事件的位置",
		["使用官方地图布局（推荐）", "自定义布置"], ["official", "custom"])
	if mode == "official" or mode == null:
		for h in CWData.OFFICIAL_LAYOUT:
			board.place_special(h, CWData.OFFICIAL_LAYOUT[h])
		log_line("特殊事件采用官方地图布局。")
		touch()
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
			if not board.specials.has(h):
				free.append(h)
		var pick = await ask_hex("免疫阵营", "放置【%s】" % item[1], free)
		if pick == null:
			pick = free[0]
		board.place_special(pick, item[0])
		touch()
	log_line("特殊事件布置完成。")


func _setup_cancer_tissues() -> void:
	# 癌组织不能与特殊事件重合，也不能位于其周围
	var forbidden: Dictionary = {}
	for h in board.specials:
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
	var mode = await ask_option("癌细胞阵营", "由癌细胞阵营选择 7 块癌组织（不能在特殊事件及其周围）", labels, values)
	if mode == "official":
		for h in official:
			board.tissue[h] = CWData.Tissue.CANCER
		log_line("癌组织采用官方示例布局（中心花型）。")
		touch()
		return
	for i in range(CWData.CANCER_TISSUE_START):
		var valid: Array = []
		for h in HexLib.all_cells():
			if not forbidden.has(h) and board.tissue_at(h) == CWData.Tissue.NORMAL:
				valid.append(h)
		var pick = await ask_hex("癌细胞阵营", "选择第 %d/7 块癌组织" % (i + 1), valid)
		if pick == null:
			pick = valid[0]
		board.tissue[pick] = CWData.Tissue.CANCER
		touch()
	log_line("癌组织选择完成。")


func _setup_positions() -> void:
	for p in players:
		var valid: Array = []
		if p.is_cancer():
			for h in board.cancer_tissues():
				valid.append(h)
		else:
			for h in HexLib.all_cells():
				if board.tissue_at(h) == CWData.Tissue.NORMAL:
					valid.append(h)
		var tip := "癌组织" if p.is_cancer() else "正常组织"
		var pick = await ask_hex(p.pname, "%s 选择初始位置（%s）" % [p.pname, tip], valid, "", {"tag": "setup_pos"})
		if pick == null:
			pick = valid[0]
		p.pos = pick
		log_line("%s 初始位置已就位。" % p.pname)
		touch()


# ==================== 主流程 ====================

func run_game() -> void:
	for r in range(1, CWData.TOTAL_ROUNDS + 1):
		round_num = r
		await _world_round_start()
		if game_over:
			return
		for i in range(players.size()):
			cur_player_idx = i
			await _player_turn(players[i])
			if game_over:
				return
		cur_player_idx = -1
	_final_scoring()


func _world_round_start() -> void:
	var stage := "前期" if round_num <= 10 else "后期"
	log_line("")
	log_line("━━━━━ 世界回合 %d / %d（%s） ━━━━━" % [round_num, CWData.TOTAL_ROUNDS, stage])
	phase_text = "世界回合 %d / %d" % [round_num, CWData.TOTAL_ROUNDS]
	# 清除上一世界回合的标记
	flag_all_crit = false
	flag_walls_off = false
	flag_immune_atk = 0
	flag_immune_rage = false
	flag_move_bonus_immune = 0
	flag_move_bonus_cancer = 0
	flag_no_attack = false
	flag_rest = false
	for p in players:
		p.skip_this_round = false
	# 固化计数衰减：无癌细胞驻守的普通癌组织，计数 -1
	var decayed: Array = []
	for h in board.solid_count.keys():
		var occupied := false
		for p in living_players(CWData.FACTION_CANCER):
			if p.pos == h:
				occupied = true
		if not occupied:
			var n: int = board.solid_count[h] - 1
			if n <= 0:
				board.solid_count.erase(h)
			else:
				board.solid_count[h] = n
			decayed.append(h)
	if not decayed.is_empty():
		log_line("固化计数衰减：%d 处无癌细胞驻守的固化计数 -1。" % decayed.size())
	# 第 10 回合开始时：进化
	if round_num == 10:
		await _evolution_draft()
	# 卡池激活 + 世界事件：前期第 3/6/9 回合；后期偶数回合
	var trigger := false
	if round_num <= 10:
		trigger = round_num in [3, 6, 9]
	else:
		trigger = round_num % 2 == 0
	if trigger:
		board.activate_all_pools()
		log_line("🃏 棋盘上的所有【卡池】变为激活状态！")
		await _trigger_world_event()
	touch()


func _evolution_draft() -> void:
	log_line("🧬 第 10 回合：所有玩家按行动顺序进行【进化】！")
	for p in players:
		var table = CWData.EVOS_IMMUNE if p.is_immune() else CWData.EVOS_CANCER
		var taken: Array = []
		for q in players:
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
		var pick = await ask_option(p.pname, "%s 选择进化能力（不可与队友重复）" % p.pname, labels, values)
		if pick == null:
			pick = values[0]
		p.evo = pick
		log_line("🧬 %s 进化为【%s】" % [p.pname, CWData.evo_def(p.faction, pick)["name"]])
		touch()


func _trigger_world_event() -> void:
	var pool: Array = []
	for e in CWData.WORLD_EVENTS:
		if e["limited"] and used_limited.has(e["id"]):
			continue
		pool.append(e)
	var ev: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	if ev["limited"]:
		used_limited.append(ev["id"])
	var side_cn := "共同事件"
	if ev["side"] == "immune":
		side_cn = "免疫事件"
	elif ev["side"] == "cancer":
		side_cn = "癌症事件"
	last_event_text = "【%s】%s" % [ev["name"], ev["text"]]
	log_line("🌍 世界事件（%s）——【%s】：%s" % [side_cn, ev["name"], ev["text"]])
	touch()
	await _apply_event(ev["id"])
	touch()


# ==================== 世界事件 ====================

func _apply_event(ev_id: String) -> void:
	match ev_id:
		"miracle":
			await _event_revive_faction(CWData.FACTION_IMMUNE)
		"revive_cancer":
			await _event_revive_faction(CWData.FACTION_CANCER)
		"second_chance":
			await _event_revive_faction(CWData.FACTION_IMMUNE)
			await _event_revive_faction(CWData.FACTION_CANCER)
		"precision_med":
			await _event_set_biomass_one(CWData.FACTION_IMMUNE, CWData.FACTION_CANCER)
		"malpractice":
			await _event_set_biomass_one(CWData.FACTION_CANCER, CWData.FACTION_IMMUNE)
		"radiotherapy":
			for p in living_players(CWData.FACTION_IMMUNE):
				var targets := board.tissues_of_type(CWData.Tissue.CANCER)
				if targets.is_empty() or p.biomass < 2:
					continue
				var yes = await ask_option(p.pname, "%s：是否失去 1 点生物质，净化任一普通癌组织？" % p.pname,
					["是（生物质-1）", "否"], [true, false])
				if yes == true:
					p.lose_biomass(1)
					var t = await ask_hex(p.pname, "选择要净化的普通癌组织", targets)
					if t != null:
						board.purify(t)
						log_line("☀️ %s 失去 1 点生物质，净化了一块癌组织。" % p.pname)
					touch()
		"battle_frenzy":
			flag_all_crit = true
		"flood":
			flag_walls_off = true
		"great_flood":
			board.clear_walls()
			log_line("🌊 棋盘上所有墙壁消失！")
		"immune_boost":
			for p in living_players(CWData.FACTION_IMMUNE):
				await draw_card(p)
		"cancer_boost":
			for p in living_players(CWData.FACTION_CANCER):
				await draw_card(p)
		"cytokine_storm":
			flag_immune_atk = 1
		"immune_rage":
			flag_immune_rage = true
		"immune_patrol":
			flag_move_bonus_immune = 1
		"cancer_infiltrate":
			flag_move_bonus_cancer = 1
		"deterioration":
			for p in living_players(CWData.FACTION_CANCER):
				var opts: Array = []
				if board.tissue_at(p.pos) == CWData.Tissue.NORMAL:
					opts.append(p.pos)
				for n in HexLib.neighbors(p.pos):
					if HexLib.in_board(n) and board.tissue_at(n) == CWData.Tissue.NORMAL:
						opts.append(n)
				if opts.is_empty():
					continue
				var t = await ask_hex(p.pname, "%s：选择当前或周围一块组织进行感染（可跳过）" % p.pname, opts, "跳过")
				if t != null:
					board.infect(t)
					log_line("🦠 %s 感染了一块组织。" % p.pname)
				touch()
		"hell_factory":
			perm_wall_bonus += 1
			log_line("🏭 此后在墙壁工厂获得的墙壁数量 +1（永久）。")
		"fibrosis":
			for p in living_players(CWData.FACTION_CANCER):
				var edges := board.buildable_edges(p.pos)
				if edges.is_empty():
					continue
				var e = await ask_edge(p.pname, "%s：选择当前组织的一面生成墙壁（可跳过）" % p.pname, edges, "跳过")
				if e != null:
					var cells := HexLib.edge_cells(e)
					board.add_wall(cells[0], cells[1])
					log_line("🧱 %s 生成了一面墙壁。" % p.pname)
				touch()
		"metastasis_ev":
			for p in living_players(CWData.FACTION_CANCER):
				var targets := board.tissues_of_type(CWData.Tissue.NORMAL)
				if targets.is_empty() or p.biomass < 2:
					continue
				var yes = await ask_option(p.pname, "%s：是否失去 1 点生物质，感染任一正常组织？" % p.pname,
					["是（生物质-1）", "否"], [true, false])
				if yes == true:
					p.lose_biomass(1)
					var t = await ask_hex(p.pname, "选择要感染的正常组织", targets)
					if t != null:
						board.infect(t)
						log_line("🦠 %s 失去 1 点生物质，感染了一块组织。" % p.pname)
					touch()
		"immune_escape":
			flag_no_attack = true
		"sweet_rain":
			for p in living_players():
				p.gain_biomass(1)
			log_line("💧 所有细胞生物质 +1。")
		"chemotherapy":
			for p in living_players():
				if p.biomass > 1:
					p.lose_biomass(1)
			log_line("💊 所有生物质大于 1 的细胞生物质 -1。")
		"life_or_death":
			for p in living_players():
				p.biomass = 1
			log_line("⚠️ 所有细胞的生物质降为 1！")
		"heaven_factory":
			perm_bio_bonus += 1
			log_line("🏭 此后生物质工厂的回复量 +1（永久）。")
		"raid":
			for p in players:
				if not p.alive or game_over:
					continue
				log_line("⚡ 突袭：%s 移动 3 步。" % p.pname)
				await _interactive_move(p, 3)
				if p.is_immune() and p.alive:
					await _attack_check(p)
				if game_over:
					return
		"weakening":
			await _event_weakening(CWData.FACTION_IMMUNE)
			await _event_weakening(CWData.FACTION_CANCER)
		"recuperate":
			flag_rest = true
		_:
			pass


func _event_revive_faction(faction: String) -> void:
	for p in dead_players(faction):
		var valid: Array = []
		if faction == CWData.FACTION_CANCER:
			for h in board.cancer_tissues():
				valid.append(h)
		else:
			for h in HexLib.all_cells():
				if board.tissue_at(h) == CWData.Tissue.NORMAL:
					valid.append(h)
		if valid.is_empty():
			log_line("%s 没有可复活的组织，无法复活。" % p.pname)
			continue
		var t = await ask_hex(p.pname, "%s 选择复活位置" % p.pname, valid)
		if t == null:
			t = valid[0]
		p.revive(t, 1)
		p.skip_this_round = true
		log_line("✨ %s 以 1 点生物质复活（本世界回合无法行动）。" % p.pname)
		await _offer_evo_swap(p)
		touch()


func _event_set_biomass_one(chooser_faction: String, target_faction: String) -> void:
	var targets := living_players(target_faction)
	if targets.is_empty():
		log_line("对方阵营无存活细胞，事件无效。")
		return
	var labels: Array = []
	for t in targets:
		labels.append("%s（生物质 %d）" % [t.pname, t.biomass])
	var pick = await ask_option(CWData.faction_cn(chooser_faction) + "阵营",
		"选择一名对方细胞，将其生物质降为 1", labels, targets)
	if pick == null:
		pick = targets[0]
	pick.biomass = 1
	log_line("🎯 %s 的生物质被降为 1！" % pick.pname)


func _event_weakening(chooser_faction: String) -> void:
	var enemy := CWData.FACTION_CANCER if chooser_faction == CWData.FACTION_IMMUNE else CWData.FACTION_IMMUNE
	var candidates: Array = []
	for p in players:
		if p.faction == enemy and not p.abilities.is_empty():
			candidates.append(p)
	if candidates.is_empty():
		log_line("%s阵营：对方没有能力牌可消除。" % CWData.faction_cn(chooser_faction))
		return
	var labels: Array = []
	for c in candidates:
		var names: Array = []
		for aid in c.abilities:
			names.append(CWData.card_def(c.faction, aid)["name"])
		labels.append("%s（%s）" % [c.pname, "、".join(names)])
	var target = await ask_option(CWData.faction_cn(chooser_faction) + "阵营",
		"选择一名对方角色消除其一张能力牌", labels, candidates)
	if target == null:
		target = candidates[0]
	var alabels: Array = []
	for aid in target.abilities:
		var cd := CWData.card_def(target.faction, aid)
		alabels.append("%s：%s" % [cd["name"], cd["text"]])
	var aid_pick = await ask_option(CWData.faction_cn(chooser_faction) + "阵营",
		"选择要消除的能力牌", alabels, target.abilities.duplicate())
	if aid_pick == null:
		aid_pick = target.abilities[0]
	target.abilities.erase(aid_pick)
	decks[target.faction].discard(aid_pick)
	log_line("🗑️ %s 的能力牌【%s】被消除。" % [target.pname, CWData.card_def(target.faction, aid_pick)["name"]])


# ==================== 玩家回合 ====================

func _player_turn(p) -> void:
	p.reset_turn_flags()
	extra_moves = 0
	log_line("")
	log_line("▶ %s 的回合（生物质 %d）" % [p.pname, p.biomass])
	phase_text = "回合 %d/%d · %s 的回合" % [round_num, CWData.TOTAL_ROUNDS, p.pname]
	touch()
	if p.skip_this_round:
		log_line("%s 本世界回合无法行动（复活休整）。" % p.pname)
		return
	if p.stunned:
		p.stunned = false
		log_line("💫 %s 处于眩晕状态，跳过本回合。" % p.pname)
		touch()
		return
	# 判定 1：复活
	if not p.alive:
		await _try_revive(p)
		if not p.alive:
			log_line("%s 处于死亡状态，跳过回合。" % p.pname)
			return
	# 判定 2：血管
	if board.special_kind(p.pos) == CWData.SP_VESSEL:
		var other := board.other_vessel(p.pos)
		if other != p.pos:
			p.pos = other
			log_line("🚇 %s 通过血管传送到另一端。" % p.pname)
			touch()
	# 判定 2：抽卡（激活卡池）
	if board.is_pool_active(p.pos):
		await _pool_draw_judgment(p)
	# 判定 3：墙壁工厂
	if p.is_cancer() and board.special_kind(p.pos) == CWData.SP_WALL:
		var gain := CWData.WALL_FACTORY_BASE + perm_wall_bonus
		if p.has_ability("heavy_worker"):
			gain += 1
		p.walls_stock += gain
		log_line("🧱 %s 在墙壁工厂获得 %d 枚墙壁（现有 %d）。" % [p.pname, gain, p.walls_stock])
		touch()
	if game_over:
		return
	# 行动 1：自由抽卡
	await _free_draw_phase(p)
	if game_over or not p.alive:
		return
	# 行动 2：移动与攻击
	await _move_phase(p)
	if game_over:
		return
	# 行动 3：特殊行动（转移癌失去特殊行动能力）
	if p.alive and p.evo != "meta":
		await _special_phase(p)
	if game_over:
		return
	# 休养生息
	if flag_rest and p.alive:
		var healed := 0
		if not p.moved_this_turn:
			healed += p.gain_biomass(1)
		if not p.used_special_this_turn:
			healed += p.gain_biomass(1)
		if healed > 0:
			log_line("🛌 %s 休养生息，回复 %d 点生物质。" % [p.pname, healed])
	# 回复判定：生物质工厂
	if p.alive and board.special_kind(p.pos) == CWData.SP_BIO:
		var got: int = p.gain_biomass(CWData.BIO_FACTORY_BASE + perm_bio_bonus)
		if got > 0:
			log_line("🏭 %s 在生物质工厂回复 %d 点生物质。" % [p.pname, got])
	# Doom 能力：回合结束时感染当前及周围一圈组织
	if p.alive and p.has_ability("doom"):
		var n_infected := 0
		if board.infect(p.pos):
			n_infected += 1
		for nb in HexLib.neighbors(p.pos):
			if HexLib.in_board(nb) and board.infect(nb):
				n_infected += 1
		if n_infected > 0:
			log_line("☢️ Doom：%s 感染了周围 %d 块组织！" % [p.pname, n_infected])
	_check_immediate_win()
	touch()


func _try_revive(p) -> void:
	if p.is_immune():
		return
	var labels: Array = []
	var values: Array = []
	var solids := board.solid_tissues()
	if not solids.is_empty():
		labels.append("在固化癌组织上复活（该组织变回普通癌组织）")
		values.append("solid")
	if p.evo == "stem":
		var donors: Array = []
		for q in living_players(CWData.FACTION_CANCER):
			if q != p and q.biomass >= 2:
				donors.append(q)
		if not donors.is_empty() and not board.cancer_tissues().is_empty():
			labels.append("癌症干细胞：消耗队友 1 点生物质，在任意癌组织复活")
			values.append("stem")
	if values.is_empty():
		return
	labels.append("放弃复活")
	values.append("skip")
	var mode = await ask_option(p.pname, "%s 已死亡，是否复活？" % p.pname, labels, values)
	if mode == "solid":
		var t = await ask_hex(p.pname, "选择复活的固化癌组织", solids)
		if t == null:
			t = solids[0]
		board.unsolidify(t)
		p.revive(t, 1)
		log_line("✨ %s 在固化癌组织上以 1 点生物质复活（该组织变回普通癌组织），本回合可以行动。" % p.pname)
		await _offer_evo_swap(p)
		touch()
	elif mode == "stem":
		var donors: Array = []
		var dlabels: Array = []
		for q in living_players(CWData.FACTION_CANCER):
			if q != p and q.biomass >= 2:
				donors.append(q)
				dlabels.append("%s（生物质 %d）" % [q.pname, q.biomass])
		if donors.is_empty():
			return
		var donor = await ask_option(p.pname, "选择消耗哪名队友的 1 点生物质", dlabels, donors)
		if donor == null:
			donor = donors[0]
		donor.lose_biomass(1)
		var tissues := board.cancer_tissues()
		var t = await ask_hex(p.pname, "选择复活的癌组织", tissues)
		if t == null:
			t = tissues[0]
		p.revive(t, 1)
		log_line("✨ 癌症干细胞：%s 消耗 %s 的 1 点生物质，以 1 点生物质复活，本回合可以行动。" % [p.pname, donor.pname])
		await _offer_evo_swap(p)
		touch()


func _offer_evo_swap(p) -> void:
	# 死亡的癌细胞复活之后可以更换一个未被选择的能力
	if not p.is_cancer() or p.evo == "":
		return
	var taken: Array = []
	for q in players:
		if q.faction == p.faction and q.evo != "":
			taken.append(q.evo)
	var labels: Array = ["保持当前能力【%s】" % CWData.evo_def(p.faction, p.evo)["name"]]
	var values: Array = ["keep"]
	for e in CWData.EVOS_CANCER:
		if not taken.has(e["id"]):
			labels.append("更换为【%s】：%s" % [e["name"], e["text"]])
			values.append(e["id"])
	if values.size() <= 1:
		return
	var pick = await ask_option(p.pname, "%s 复活后可更换一个未被选择的进化能力" % p.pname, labels, values)
	if pick != null and pick != "keep":
		p.evo = pick
		log_line("🧬 %s 更换进化能力为【%s】。" % [p.pname, CWData.evo_def(p.faction, pick)["name"]])


func _pool_draw_judgment(p) -> void:
	var here := players_at(p.pos)
	var enemies: Array = []
	for q in here:
		if q.faction != p.faction:
			enemies.append(q)
	var drawer = p
	if not enemies.is_empty():
		log_line("⚔️ 不同阵营玩家位于同一激活卡池，掷骰决定抽卡资格！")
		var contenders := here.duplicate()
		while contenders.size() > 1:
			var best := 0
			var rolls: Dictionary = {}
			for q in contenders:
				var v: int = await d6("%s 争夺卡池" % q.pname)
				rolls[q] = v
				if v > best:
					best = v
			var top: Array = []
			for q in contenders:
				if rolls[q] == best:
					top.append(q)
			if top.size() == 1:
				contenders = top
			else:
				log_line("平局，重新掷骰！")
				contenders = top
		drawer = contenders[0]
		log_line("🏆 %s 获得抽卡资格！" % drawer.pname)
	elif here.size() > 1:
		var labels: Array = []
		for q in here:
			labels.append(q.pname)
		var pick = await ask_option(p.pname, "同阵营玩家位于同一卡池，商议由谁抽卡", labels, here)
		if pick != null:
			drawer = pick
	await draw_card(drawer)
	board.deactivate_pool(p.pos)
	log_line("该卡池变为未激活状态。")
	touch()


# ==================== 行动 1：自由抽卡 ====================

func _free_draw_phase(p) -> void:
	phase_text = "回合 %d/%d · %s · 抽卡阶段" % [round_num, CWData.TOTAL_ROUNDS, p.pname]
	touch()
	while p.alive and not game_over:
		var labels: Array = []
		var values: Array = []
		if p.biomass >= 3:
			labels.append("燃烧抽卡：燃烧 2 点生物质，抽一张卡")
			values.append("burn")
		if p.is_cancer() and p.biomass >= 2:
			labels.append("突变抽卡：失去 1 点生物质，掷骰 4-6 才能抽卡")
			values.append("mutate")
		if values.is_empty():
			return
		labels.append("结束抽卡阶段")
		values.append("done")
		var pick = await ask_option(p.pname, "%s：自由抽卡（生物质 %d）" % [p.pname, p.biomass], labels, values)
		if pick == null or pick == "done":
			return
		if pick == "burn":
			p.lose_biomass(2)
			log_line("🔥 %s 燃烧 2 点生物质抽卡。" % p.pname)
			await draw_card(p)
		elif pick == "mutate":
			p.lose_biomass(1)
			var v: int = await d6("%s 突变抽卡" % p.pname)
			if v >= 4:
				await draw_card(p)
			else:
				log_line("突变失败，无事发生。")
		touch()


# ==================== 行动 2：移动与攻击 ====================

func _die_steps(v: int) -> int:
	if v <= 3:
		return 1
	elif v <= 5:
		return 2
	return 3


func _move_bonus(p) -> int:
	var b := 0
	if p.is_immune():
		b += flag_move_bonus_immune
	else:
		b += flag_move_bonus_cancer
	if p.evo == "blood":
		b += 1
	return b


func _move_phase(p) -> void:
	phase_text = "回合 %d/%d · %s · 移动阶段" % [round_num, CWData.TOTAL_ROUNDS, p.pname]
	touch()
	# 能力卡：移动阶段开始前可移动 1 步
	if p.has_ability("chemotaxis") or p.has_ability("metastasis"):
		await _pre_move_step(p)
	if not p.alive:
		return
	if p.evo == "meta":
		# 转移癌：固定移动 1 步，自动感染接触到的组织
		await _interactive_move(p, 1)
		while extra_moves > 0 and p.alive and not game_over:
			extra_moves -= 1
			var use = await ask_option(p.pname, "使用额外移动机会？（转移癌固定 1 步）",
				["移动 1 步", "放弃"], [true, false])
			if use != true:
				break
			await _interactive_move(p, 1)
		return
	var pick = await ask_option(p.pname, "%s：移动阶段" % p.pname,
		["掷骰移动", "跳过移动"], ["roll", "skip"])
	if pick == "roll":
		var v: int = await d6("%s 移动" % p.pname)
		var steps := _die_steps(v) + _move_bonus(p)
		log_line("%s 可移动 %d 步。" % [p.pname, steps])
		await _interactive_move(p, steps)
		if p.is_immune() and p.alive and not game_over:
			await _attack_check(p)
	# 额外移动机会
	while extra_moves > 0 and p.alive and not game_over:
		extra_moves -= 1
		var use = await ask_option(p.pname, "%s：使用额外移动机会？（重新掷骰移动）" % p.pname,
			["掷骰移动", "放弃"], [true, false])
		if use != true:
			break
		var v2: int = await d6("%s 额外移动" % p.pname)
		var steps2 := _die_steps(v2) + _move_bonus(p)
		log_line("%s 可移动 %d 步。" % [p.pname, steps2])
		await _interactive_move(p, steps2)
		if p.is_immune() and p.alive and not game_over:
			await _attack_check(p)


func _pre_move_step(p) -> void:
	var legal: Array = []
	for n in HexLib.neighbors(p.pos):
		if board.can_step(p.pos, n, p.ignores_walls() or flag_walls_off):
			legal.append(n)
	if legal.is_empty():
		return
	var aname := "Chemotaxis" if p.is_immune() else "Metastasis"
	var t = await ask_hex(p.pname, "%s：能力【%s】可在移动阶段前移动 1 步（可跳过）" % [p.pname, aname], legal, "跳过",
		{"tag": "move_step", "actor": p})
	if t == null:
		return
	_do_step(p, t)
	touch()


## 执行一步移动（更新方向、转移癌感染、血液癌血管传送、树突标记）
func _do_step(p, to: Vector2i) -> void:
	p.last_dir = HexLib.dir_index(to - p.pos)
	p.pos = to
	p.moved_this_turn = true
	if p.evo == "meta":
		if board.infect(p.pos):
			log_line("🦠 转移癌：%s 感染了脚下的组织。" % p.pname)
	if p.evo == "blood" and board.special_kind(p.pos) == CWData.SP_VESSEL:
		var other := board.other_vessel(p.pos)
		if other != p.pos:
			p.pos = other
			log_line("🚇 血液癌：%s 经过血管，立即传送！" % p.pname)
	if p.evo == "dendritic":
		_mark_dendritic(p)


func _mark_dendritic(p) -> void:
	for c in living_players(CWData.FACTION_CANCER):
		if c.vulnerable:
			continue
		if attack_dist(p, c.pos, p.attack_range()) >= 0:
			c.vulnerable = true
			log_line("🔖 树突状细胞：%s 被添加【易伤】标记！" % c.pname)


func _interactive_move(p, steps: int) -> void:
	var remaining := steps
	while remaining > 0 and p.alive:
		var legal: Array = []
		for n in HexLib.neighbors(p.pos):
			if board.can_step(p.pos, n, p.ignores_walls() or flag_walls_off):
				legal.append(n)
		if legal.is_empty():
			log_line("%s 无路可走，移动结束。" % p.pname)
			return
		var t = await ask_hex(p.pname, "%s：选择移动方向（剩余 %d 步）" % [p.pname, remaining], legal, "结束移动",
			{"tag": "move_step", "actor": p})
		if t == null:
			return
		_do_step(p, t)
		remaining -= 1
		touch()
	if p.evo == "dendritic":
		_mark_dendritic(p)


# ==================== 攻击 ====================

func _attack_check(p) -> void:
	if flag_no_attack:
		return
	if p.evo == "dendritic":
		_mark_dendritic(p)
		return
	var rng_range: int = p.attack_range()
	var targets: Array = []
	for c in living_players(CWData.FACTION_CANCER):
		if attack_dist(p, c.pos, rng_range) >= 0:
			targets.append(c)
	if targets.is_empty():
		return
	var target = targets[0]
	if targets.size() > 1:
		var opts: Array = []
		for c in targets:
			opts.append(c.pos)
		var pos_pick = await ask_hex(p.pname, "%s：选择攻击目标" % p.pname, opts, "", {"tag": "attack_target", "actor": p})
		if pos_pick != null:
			for c in targets:
				if c.pos == pos_pick:
					target = c
					break
	var dir: int = p.last_dir
	if dir < 0:
		var dpick = await ask_option(p.pname, "%s：本回合未移动，选择攻击/击退方向" % p.pname,
			HexLib.DIR_NAMES.duplicate(), [0, 1, 2, 3, 4, 5])
		dir = 0 if dpick == null else dpick
	await _perform_attack(p, target, dir, false)


func _perform_attack(atk, tgt, dir: int, is_double: bool) -> void:
	if flag_no_attack or game_over:
		return
	log_line("⚔️ %s 攻击 %s！" % [atk.pname, tgt.pname])
	# Dodge：逃逸下一次攻击
	if tgt.dodge_next:
		tgt.dodge_next = false
		_consume_attack_buffs(atk)
		log_line("💨 %s 使用 Dodge 逃逸了这次攻击！" % tgt.pname)
		touch()
		return
	var was_vulnerable: bool = tgt.vulnerable
	tgt.vulnerable = false
	# 攻击力快照（含回合增益）
	var raged: bool = flag_immune_rage and atk.biomass > 1
	var power: int = atk.attack_power() + flag_immune_atk
	if raged:
		power += 1
	var sure: bool = atk.next_atk_sure
	_consume_attack_buffs(atk)
	# 判定档位：0 失败 / 1 成功 / 2 大成功
	var tier := 0
	if flag_all_crit or atk.evo == "nk":
		tier = 2
		log_line("💥 攻击必然大成功！")
	else:
		var v: int = await d6("%s 攻击判定" % atk.pname)
		if v <= 1:
			tier = 0
		elif v <= 3:
			tier = 1
		else:
			tier = 2
		if tier == 0 and (sure or was_vulnerable):
			tier = 1
			log_line("🎯 攻击必然成功（%s）！" % ("必中" if sure else "易伤"))
	if tier == 0:
		log_line("❌ 攻击失败！")
		if not is_double:
			_retreat(atk, (dir + 3) % 6)
	elif tier == 1:
		log_line("✅ 攻击成功，%s 被击退 1 步。" % tgt.pname)
		await _knockback(tgt, dir, 1, atk)
	else:
		var dmg: int = power
		if was_vulnerable:
			dmg += 1
		if tgt.evo == "solid_evo":
			dmg -= 1
		dmg = maxi(dmg, 0)
		if tgt.keratin_next:
			tgt.keratin_next = false
			dmg = 0
			log_line("🛡️ Keratinization：%s 免疫了本次攻击的生物质伤害！" % tgt.pname)
		var attacked_tile: Vector2i = tgt.pos
		var lost: int = tgt.lose_biomass(dmg)
		log_line("💥 大成功！%s 失去 %d 点生物质（剩余 %d）。" % [tgt.pname, lost, tgt.biomass])
		if atk.evo == "macro" and lost > 0:
			var healed: int = atk.gain_biomass(lost)
			if healed > 0:
				log_line("🍽️ 巨噬细胞：%s 回复 %d 点生物质。" % [atk.pname, healed])
		if raged:
			atk.lose_biomass(1)
			log_line("🔥 免疫暴走：%s 大成功后失去 1 点生物质（剩余 %d）。" % [atk.pname, atk.biomass])
			if atk.biomass <= 0:
				_kill(atk, null)
		if tgt.biomass <= 0:
			_kill(tgt, atk)
		else:
			await _knockback(tgt, dir, power, atk)
		if board.tissue_at(attacked_tile) == CWData.Tissue.CANCER:
			board.purify(attacked_tile)
			log_line("☀️ 被攻击处的普通癌组织被净化！")
	touch()


func _consume_attack_buffs(atk) -> void:
	atk.next_atk_power = 0
	atk.next_atk_range = 0
	atk.next_atk_sure = false


func _retreat(p, dir: int) -> void:
	var to: Vector2i = p.pos + HexLib.DIRS[dir]
	if not HexLib.in_board(to):
		log_line("%s 已在棋盘边缘，无法后退。" % p.pname)
		return
	if not (p.ignores_walls() or flag_walls_off) and board.has_wall(p.pos, to):
		log_line("%s 被墙壁挡住，无法后退。" % p.pname)
		return
	p.pos = to
	log_line("↩️ %s 后退 1 步。" % p.pname)


func _knockback(tgt, dir: int, n: int, from_attacker) -> void:
	if tgt.infdiv_next:
		tgt.infdiv_next = false
		log_line("🧬 Infinite division：%s 不会被击退！" % tgt.pname)
		return
	var steps := n
	var moved := 0
	while steps > 0:
		var next: Vector2i = tgt.pos + HexLib.DIRS[dir]
		if not HexLib.in_board(next):
			tgt.stunned = true
			log_line("💫 %s 被击退出棋盘边缘，停留在边缘并眩晕（跳过下一回合）！" % tgt.pname)
			break
		tgt.pos = next
		moved += 1
		steps -= 1
	if moved > 0:
		log_line("%s 被击退 %d 步。" % [tgt.pname, moved])
	touch()
	if not tgt.alive or game_over:
		return
	# 双重打击：击退后的位置位于其他免疫细胞攻击范围内
	var candidates: Array = []
	for q in living_players(CWData.FACTION_IMMUNE):
		if q == from_attacker or q.evo == "dendritic":
			continue
		if attack_dist(q, tgt.pos, q.attack_range()) >= 0:
			candidates.append(q)
	if candidates.is_empty():
		return
	var striker = candidates[0]
	if candidates.size() > 1:
		var labels: Array = []
		for q in candidates:
			labels.append(q.pname)
		var pick = await ask_option("免疫阵营", "双重打击！选择由哪名免疫细胞追击 %s" % tgt.pname, labels, candidates)
		if pick != null:
			striker = pick
	log_line("⚡ 双重打击！%s 追击 %s！" % [striker.pname, tgt.pname])
	await _perform_attack(striker, tgt, dir, true)


func _kill(p, killer) -> void:
	p.die()
	log_line("☠️ %s 死亡！" % p.pname)
	if killer != null and killer.is_immune() and p.is_cancer():
		killer.kills += 1
		if killer.evo == "mem_b":
			log_line("🧠 记忆B细胞：%s 攻击距离提升（击杀数 %d）。" % [killer.pname, killer.kills])
		elif killer.evo == "mem_t":
			log_line("🧠 记忆T细胞：%s 攻击力提升（击杀数 %d）。" % [killer.pname, killer.kills])
	_check_immediate_win()
	touch()


# ==================== 行动 3：特殊行动 ====================

func _special_phase(p) -> void:
	phase_text = "回合 %d/%d · %s · 特殊行动" % [round_num, CWData.TOTAL_ROUNDS, p.pname]
	touch()
	var labels: Array = []
	var values: Array = []
	if p.is_immune():
		if board.tissue_at(p.pos) == CWData.Tissue.CANCER:
			labels.append("净化：将当前普通癌组织转变为正常组织")
			values.append("purify")
		if not board.walls_adjacent_to(p.pos).is_empty():
			labels.append("拆除：拆除相邻的一面墙壁及与其连通的所有墙壁")
			values.append("demolish")
	else:
		if board.tissue_at(p.pos) == CWData.Tissue.NORMAL:
			labels.append("感染：将当前正常组织转变为普通癌组织")
			values.append("infect")
		if board.tissue_at(p.pos) == CWData.Tissue.CANCER:
			var cnt: int = board.solid_count.get(p.pos, 0)
			labels.append("固化：当前癌组织固化计数 +1（现 %d/3）" % cnt)
			values.append("solidify")
		if p.walls_stock > 0 and not board.buildable_edges(p.pos).is_empty():
			labels.append("建造：在当前组织周围建造墙壁（持有 %d 枚）" % p.walls_stock)
			values.append("build")
	if values.is_empty():
		return
	labels.append("跳过特殊行动")
	values.append("skip")
	var pick = await ask_option(p.pname, "%s：选择特殊行动（每回合一种）" % p.pname, labels, values)
	if pick == null or pick == "skip":
		return
	match pick:
		"purify":
			board.purify(p.pos)
			p.used_special_this_turn = true
			log_line("☀️ %s 净化了当前组织。" % p.pname)
		"demolish":
			var adj := board.walls_adjacent_to(p.pos)
			var e = adj[0]
			if adj.size() > 1:
				var epick = await ask_edge(p.pname, "选择要拆除的墙壁（连通的墙壁将一并拆除）", adj)
				if epick != null:
					e = epick
			var connected := board.connected_walls(e)
			for k in connected:
				board.remove_wall_key(k)
			p.used_special_this_turn = true
			log_line("🔨 %s 拆除了 %d 面连通的墙壁！" % [p.pname, connected.size()])
		"infect":
			board.infect(p.pos)
			p.used_special_this_turn = true
			log_line("🦠 %s 感染了当前组织。" % p.pname)
		"solidify":
			var n := board.add_solid_count(p.pos)
			p.used_special_this_turn = true
			if n >= 3:
				log_line("🪨 %s 固化计数达到 3，当前组织变为【固化癌组织】！" % p.pname)
			else:
				log_line("🪨 %s 固化当前组织（计数 %d/3）。" % [p.pname, n])
		"build":
			var built := 0
			while p.walls_stock > 0:
				var edges := board.buildable_edges(p.pos)
				if edges.is_empty():
					break
				var epick2 = await ask_edge(p.pname, "选择建造墙壁的位置（持有 %d 枚）" % p.walls_stock, edges, "完成建造")
				if epick2 == null:
					break
				var cells := HexLib.edge_cells(epick2)
				board.add_wall(cells[0], cells[1])
				p.walls_stock -= 1
				built += 1
				touch()
			if built > 0:
				p.used_special_this_turn = true
				log_line("🧱 %s 建造了 %d 面墙壁。" % [p.pname, built])
	touch()


# ==================== 抽卡与卡牌效果 ====================

func draw_card(p) -> void:
	if not p.alive:
		return
	var deck: CWDeck = decks[p.faction]
	var cid: String = deck.draw()
	if cid == "":
		log_line("%s 的卡池与弃牌堆已空，无法抽卡。" % CWData.faction_cn(p.faction))
		return
	var def := CWData.card_def(p.faction, cid)
	log_line("🃏 %s 抽到【%s】（%s）：%s" % [p.pname, def["name"],
		"能力" if def["kind"] == "ability" else "即时", def["text"]])
	touch()
	if def["kind"] == "ability":
		p.abilities.append(cid)
	else:
		await _apply_card(p, cid)
		deck.discard(cid)
	touch()


func _apply_card(p, cid: String) -> void:
	match cid:
		"diapedesis", "invasion":
			var steps := 3
			if p.evo == "blood":
				steps += 1
			await _interactive_move(p, steps)
			if p.is_immune() and p.alive and not game_over:
				await _attack_check(p)
		"glucose":
			p.gain_biomass(1)
		"maltose":
			p.gain_biomass(2)
		"balanced_diet":
			for q in living_players(CWData.FACTION_IMMUNE):
				q.gain_biomass(1)
			log_line("所有免疫细胞生物质 +1。")
		"starvation":
			for q in living_players(CWData.FACTION_CANCER):
				q.gain_biomass(1)
			log_line("所有癌细胞生物质 +1。")
		"teleporting":
			var opts: Array = []
			if p.is_cancer():
				for h in board.cancer_tissues():
					opts.append(h)
			else:
				for h in HexLib.all_cells():
					if board.tissue_at(h) == CWData.Tissue.NORMAL:
						opts.append(h)
			if opts.is_empty():
				return
			var t = await ask_hex(p.pname, "Teleporting：选择传送目的地（己方阵营组织）", opts)
			if t != null:
				p.pos = t
				log_line("🌀 %s 传送完成。" % p.pname)
		"translocation":
			var mates: Array = []
			var labels: Array = []
			for q in living_players(p.faction):
				if q != p:
					mates.append(q)
					labels.append(q.pname)
			if mates.is_empty():
				log_line("没有存活的队友，卡牌无效。")
				return
			var mate = await ask_option(p.pname, "Translocation：选择交换位置的队友", labels, mates)
			if mate == null:
				mate = mates[0]
			var tmp: Vector2i = p.pos
			p.pos = mate.pos
			mate.pos = tmp
			log_line("🔁 %s 与 %s 交换了位置。" % [p.pname, mate.pname])
		"good_drug", "bad_drug":
			await draw_card(p)
			await draw_card(p)
		"evolution", "mutation":
			if p.biomass > 1:
				await draw_card(p)
				await draw_card(p)
				await draw_card(p)
				p.lose_biomass(1)
				log_line("%s 失去 1 点生物质。" % p.pname)
			else:
				log_line("生物质不足（需大于 1），卡牌无效。")
		"good_day":
			var targets := board.tissues_of_type(CWData.Tissue.CANCER)
			if targets.is_empty():
				log_line("棋盘上没有普通癌组织，卡牌无效。")
				return
			var t = await ask_hex(p.pname, "Good day：选择一块普通癌组织转变为正常组织", targets)
			if t != null:
				board.purify(t)
				log_line("☀️ 一块癌组织被转变为正常组织。")
		"bad_day":
			var targets := board.tissues_of_type(CWData.Tissue.NORMAL)
			if targets.is_empty():
				return
			var t = await ask_hex(p.pname, "Bad day：选择一块正常组织转变为普通癌组织", targets)
			if t != null:
				board.infect(t)
				log_line("🦠 一块正常组织被转变为癌组织。")
		"vegf":
			var vessels := board.special_positions(CWData.SP_VESSEL)
			if vessels.is_empty():
				return
			var v = await ask_hex(p.pname, "VEGF：选择要移动的血管", vessels)
			if v == null:
				v = vessels[0]
			var dests: Array = []
			for h in HexLib.all_cells():
				if board.specials.has(h):
					continue
				var d := HexLib.distance(v, h)
				if d >= 1 and d <= 3:
					dests.append(h)
			if dests.is_empty():
				return
			var dest = await ask_hex(p.pname, "VEGF：选择血管的新位置（1-3 步内，不与其他特殊事件重合）", dests)
			if dest != null:
				board.move_special(v, dest)
				log_line("🩸 血管被移动了。")
		"info_detect", "infiltration":
			if cur_player() == p:
				extra_moves += 1
				log_line("👟 %s 本回合获得 1 次额外移动机会。" % p.pname)
			else:
				log_line("（非自己回合抽到，额外移动机会无效。）")
		"complement":
			p.next_atk_range += 1
		"cytokine":
			p.next_atk_power += 1
		"precise":
			p.next_atk_sure = true
		"inf_division":
			p.infdiv_next = true
		"keratin":
			p.keratin_next = true
		"dodge":
			p.dodge_next = true
		"excalibur":
			var axis = await ask_option(p.pname, "Excalibur：选择净化的直线方向（以自己为中心）",
				["东 — 西", "东北 — 西南", "西北 — 东南"], [0, 1, 2])
			if axis == null:
				axis = 0
			var line: Array = [p.pos]
			for h in HexLib.ray(p.pos, axis):
				line.append(h)
			for h in HexLib.ray(p.pos, axis + 3):
				line.append(h)
			var n := 0
			for h in line:
				if board.purify(h):
					n += 1
			log_line("🗡️ Excalibur！一条直线上的 %d 块普通癌组织被净化！" % n)
		"nuclear":
			var targets := board.tissues_of_type(CWData.Tissue.CANCER)
			if targets.is_empty():
				log_line("棋盘上没有普通癌组织，卡牌无效。")
				return
			var t = await ask_hex(p.pname, "Nuclear radiation：选择一块普通癌组织直接固化", targets)
			if t != null:
				board.solidify_full(t)
				log_line("🪨 一块普通癌组织被直接固化！")
		_:
			pass


# ==================== 胜负判定 ====================

func _check_immediate_win() -> void:
	if game_over:
		return
	# 所有癌细胞死亡且无法复活 → 免疫细胞阵营胜利
	if not living_players(CWData.FACTION_CANCER).is_empty():
		return
	# 可复活途径：固化癌组织复活（判定1）；干细胞需要存活的队友（已无）
	if board.solid_tissues().is_empty():
		game_over = true
		winner = CWData.FACTION_IMMUNE
		win_reason = "所有癌细胞死亡且无法复活，免疫细胞阵营胜利！"
		log_line("")
		log_line("🏁 %s" % win_reason)
		touch()


func _final_scoring() -> void:
	var count := board.cancer_tissue_count()
	var threshold := win_threshold()
	game_over = true
	if count >= threshold:
		winner = CWData.FACTION_CANCER
		win_reason = "20 个世界回合结束：癌组织 %d 块 ≥ %d，癌细胞阵营胜利！" % [count, threshold]
	else:
		winner = CWData.FACTION_IMMUNE
		win_reason = "20 个世界回合结束：癌组织 %d 块 < %d，免疫细胞阵营胜利！" % [count, threshold]
	log_line("")
	log_line("🏁 %s" % win_reason)
	touch()
