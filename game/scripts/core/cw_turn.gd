class_name CWTurn
extends RefCounted
## 单个玩家回合的完整时序：跳过/眩晕 → 判定1 复活 → 判定2 血管/卡池 →
## 判定3 墙壁工厂 → 自由抽卡 → 移动与攻击（cw_movement/cw_combat）→
## 特殊行动 → 休养生息/生物质工厂/Doom → 胜负检查。

var game: CWGame


func _init(p_game: CWGame) -> void:
	game = p_game


func run(p) -> void:
	p.reset_turn_flags()
	game.extra_moves = 0
	game.log_line("")
	game.log_line("▶ %s 的回合（生物质 %d）" % [p.pname, p.biomass])
	game.phase_text = "回合 %d/%d · %s 的回合" % [game.round_num, CWData.TOTAL_ROUNDS, p.pname]
	game.touch()
	if p.skip_this_round:
		game.log_line("%s 本世界回合无法行动（复活休整）。" % p.pname)
		return
	if p.stunned:
		p.stunned = false
		game.log_line("💫 %s 处于眩晕状态，跳过本回合。" % p.pname)
		game.touch()
		return
	# 判定 1：复活
	if not p.alive:
		await _try_revive(p)
		if not p.alive:
			game.log_line("%s 处于死亡状态，跳过回合。" % p.pname)
			return
	# 判定 2：血管
	if game.board.special_kind(p.pos) == CWData.SP_VESSEL:
		var other := game.board.other_vessel(p.pos)
		if other != p.pos:
			p.pos = other
			game.log_line("🚇 %s 通过血管传送到另一端。" % p.pname)
			game.touch()
	# 判定 2：抽卡（激活卡池）
	if game.board.is_pool_active(p.pos):
		await _pool_draw_judgment(p)
	# 判定 3：墙壁工厂
	if p.is_cancer() and game.board.special_kind(p.pos) == CWData.SP_WALL:
		var gain := CWData.WALL_FACTORY_BASE + game.perm_wall_bonus
		if p.has_ability("heavy_worker"):
			gain += 1
		p.walls_stock += gain
		game.log_line("🧱 %s 在墙壁工厂获得 %d 枚墙壁（现有 %d）。" % [p.pname, gain, p.walls_stock])
		game.touch()
	if game.game_over:
		return
	# 行动 1：自由抽卡
	await _free_draw_phase(p)
	if game.game_over or not p.alive:
		return
	# 行动 2：移动与攻击
	await game.movement.move_phase(p)
	if game.game_over:
		return
	# 行动 3：特殊行动（转移癌失去特殊行动能力）
	if p.alive and p.evo != "meta":
		await _special_phase(p)
	if game.game_over:
		return
	# 休养生息
	if game.flag_rest and p.alive:
		var healed := 0
		if not p.moved_this_turn:
			healed += p.gain_biomass(1)
		if not p.used_special_this_turn:
			healed += p.gain_biomass(1)
		if healed > 0:
			game.log_line("🛌 %s 休养生息，回复 %d 点生物质。" % [p.pname, healed])
	# 回复判定：生物质工厂
	if p.alive and game.board.special_kind(p.pos) == CWData.SP_BIO:
		var got: int = p.gain_biomass(CWData.BIO_FACTORY_BASE + game.perm_bio_bonus)
		if got > 0:
			game.log_line("🏭 %s 在生物质工厂回复 %d 点生物质。" % [p.pname, got])
	# Doom 能力：回合结束时感染当前及周围一圈组织
	if p.alive and p.has_ability("doom"):
		var n_infected := 0
		if game.board.infect(p.pos):
			n_infected += 1
		for nb in HexLib.neighbors(p.pos):
			if HexLib.in_board(nb) and game.board.infect(nb):
				n_infected += 1
		if n_infected > 0:
			game.log_line("☢️ Doom：%s 感染了周围 %d 块组织！" % [p.pname, n_infected])
	game.check_immediate_win()
	game.touch()


func _try_revive(p) -> void:
	if p.is_immune():
		return
	var labels: Array = []
	var values: Array = []
	var solids := game.board.solid_tissues()
	if not solids.is_empty():
		labels.append("在固化癌组织上复活（该组织变回普通癌组织）")
		values.append("solid")
	if p.evo == "stem":
		var donors: Array = []
		for q in game.living_players(CWData.FACTION_CANCER):
			if q != p and q.biomass >= 2:
				donors.append(q)
		if not donors.is_empty() and not game.board.cancer_tissues().is_empty():
			labels.append("癌症干细胞：消耗队友 1 点生物质，在任意癌组织复活")
			values.append("stem")
	if values.is_empty():
		return
	labels.append("放弃复活")
	values.append("skip")
	var mode = await game.ask_option(p.pname, "%s 已死亡，是否复活？" % p.pname, labels, values)
	if mode == "solid":
		var t = await game.ask_hex(p.pname, "选择复活的固化癌组织", solids)
		if t == null:
			t = solids[0]
		game.board.unsolidify(t)
		p.revive(t, 1)
		game.log_line("✨ %s 在固化癌组织上以 1 点生物质复活（该组织变回普通癌组织），本回合可以行动。" % p.pname)
		await offer_evo_swap(p)
		game.touch()
	elif mode == "stem":
		var donors: Array = []
		var dlabels: Array = []
		for q in game.living_players(CWData.FACTION_CANCER):
			if q != p and q.biomass >= 2:
				donors.append(q)
				dlabels.append("%s（生物质 %d）" % [q.pname, q.biomass])
		if donors.is_empty():
			return
		var donor = await game.ask_option(p.pname, "选择消耗哪名队友的 1 点生物质", dlabels, donors)
		if donor == null:
			donor = donors[0]
		donor.lose_biomass(1)
		var tissues := game.board.cancer_tissues()
		var t = await game.ask_hex(p.pname, "选择复活的癌组织", tissues)
		if t == null:
			t = tissues[0]
		p.revive(t, 1)
		game.log_line("✨ 癌症干细胞：%s 消耗 %s 的 1 点生物质，以 1 点生物质复活，本回合可以行动。" % [p.pname, donor.pname])
		await offer_evo_swap(p)
		game.touch()


## 死亡的癌细胞复活之后可以更换一个未被选择的能力（世界事件复活也会调用）
func offer_evo_swap(p) -> void:
	if not p.is_cancer() or p.evo == "":
		return
	var taken: Array = []
	for q in game.players:
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
	var pick = await game.ask_option(p.pname, "%s 复活后可更换一个未被选择的进化能力" % p.pname, labels, values)
	if pick != null and pick != "keep":
		p.evo = pick
		game.log_line("🧬 %s 更换进化能力为【%s】。" % [p.pname, CWData.evo_def(p.faction, pick)["name"]])


func _pool_draw_judgment(p) -> void:
	var here := game.players_at(p.pos)
	var enemies: Array = []
	for q in here:
		if q.faction != p.faction:
			enemies.append(q)
	var drawer = p
	if not enemies.is_empty():
		game.log_line("⚔️ 不同阵营玩家位于同一激活卡池，掷骰决定抽卡资格！")
		var contenders := here.duplicate()
		while contenders.size() > 1:
			var best := 0
			var rolls: Dictionary = {}
			for q in contenders:
				var v: int = await game.d6("%s 争夺卡池" % q.pname)
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
				game.log_line("平局，重新掷骰！")
				contenders = top
		drawer = contenders[0]
		game.log_line("🏆 %s 获得抽卡资格！" % drawer.pname)
	elif here.size() > 1:
		var labels: Array = []
		for q in here:
			labels.append(q.pname)
		var pick = await game.ask_option(p.pname, "同阵营玩家位于同一卡池，商议由谁抽卡", labels, here)
		if pick != null:
			drawer = pick
	await game.cards.draw_card(drawer)
	game.board.deactivate_pool(p.pos)
	game.log_line("该卡池变为未激活状态。")
	game.touch()


func _free_draw_phase(p) -> void:
	game.phase_text = "回合 %d/%d · %s · 抽卡阶段" % [game.round_num, CWData.TOTAL_ROUNDS, p.pname]
	game.touch()
	while p.alive and not game.game_over:
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
		var pick = await game.ask_option(p.pname, "%s：自由抽卡（生物质 %d）" % [p.pname, p.biomass], labels, values)
		if pick == null or pick == "done":
			return
		if pick == "burn":
			p.lose_biomass(2)
			game.log_line("🔥 %s 燃烧 2 点生物质抽卡。" % p.pname)
			await game.cards.draw_card(p)
		elif pick == "mutate":
			p.lose_biomass(1)
			var v: int = await game.d6("%s 突变抽卡" % p.pname)
			if v >= 4:
				await game.cards.draw_card(p)
			else:
				game.log_line("突变失败，无事发生。")
		game.touch()


func _special_phase(p) -> void:
	game.phase_text = "回合 %d/%d · %s · 特殊行动" % [game.round_num, CWData.TOTAL_ROUNDS, p.pname]
	game.touch()
	var labels: Array = []
	var values: Array = []
	if p.is_immune():
		if game.board.tissue_at(p.pos) == CWData.Tissue.CANCER:
			labels.append("净化：将当前普通癌组织转变为正常组织")
			values.append("purify")
		if not game.board.walls_adjacent_to(p.pos).is_empty():
			labels.append("拆除：拆除相邻的一面墙壁及与其连通的所有墙壁")
			values.append("demolish")
	else:
		if game.board.tissue_at(p.pos) == CWData.Tissue.NORMAL:
			labels.append("感染：将当前正常组织转变为普通癌组织")
			values.append("infect")
		if game.board.tissue_at(p.pos) == CWData.Tissue.CANCER:
			var cnt: int = game.board.solid_count.get(p.pos, 0)
			labels.append("固化：当前癌组织固化计数 +1（现 %d/3）" % cnt)
			values.append("solidify")
		if p.walls_stock > 0 and not game.board.buildable_edges(p.pos).is_empty():
			labels.append("建造：在当前组织周围建造墙壁（持有 %d 枚）" % p.walls_stock)
			values.append("build")
	if values.is_empty():
		return
	labels.append("跳过特殊行动")
	values.append("skip")
	var pick = await game.ask_option(p.pname, "%s：选择特殊行动（每回合一种）" % p.pname, labels, values)
	if pick == null or pick == "skip":
		return
	match pick:
		"purify":
			game.board.purify(p.pos)
			p.used_special_this_turn = true
			game.log_line("☀️ %s 净化了当前组织。" % p.pname)
		"demolish":
			var adj := game.board.walls_adjacent_to(p.pos)
			var e = adj[0]
			if adj.size() > 1:
				var epick = await game.ask_edge(p.pname, "选择要拆除的墙壁（连通的墙壁将一并拆除）", adj)
				if epick != null:
					e = epick
			var connected := game.board.connected_walls(e)
			for k in connected:
				game.board.remove_wall_key(k)
			p.used_special_this_turn = true
			game.log_line("🔨 %s 拆除了 %d 面连通的墙壁！" % [p.pname, connected.size()])
		"infect":
			game.board.infect(p.pos)
			p.used_special_this_turn = true
			game.log_line("🦠 %s 感染了当前组织。" % p.pname)
		"solidify":
			var n := game.board.add_solid_count(p.pos)
			p.used_special_this_turn = true
			if n >= 3:
				game.log_line("🪨 %s 固化计数达到 3，当前组织变为【固化癌组织】！" % p.pname)
			else:
				game.log_line("🪨 %s 固化当前组织（计数 %d/3）。" % [p.pname, n])
		"build":
			var built := 0
			while p.walls_stock > 0:
				var edges := game.board.buildable_edges(p.pos)
				if edges.is_empty():
					break
				var epick2 = await game.ask_edge(p.pname, "选择建造墙壁的位置（持有 %d 枚）" % p.walls_stock, edges, "完成建造")
				if epick2 == null:
					break
				var cells := HexLib.edge_cells(epick2)
				game.board.add_wall(cells[0], cells[1])
				p.walls_stock -= 1
				built += 1
				game.touch()
			if built > 0:
				p.used_special_this_turn = true
				game.log_line("🧱 %s 建造了 %d 面墙壁。" % [p.pname, built])
	game.touch()
