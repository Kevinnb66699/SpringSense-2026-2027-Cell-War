class_name CWEvents
extends RefCounted
## 27 个世界事件的具体效果。事件的名称/文案/限定标记定义在 cw_data.gd 的
## WORLD_EVENTS，触发时机在 cw_world.gd；想改某个事件的效果直接改 apply()。

var game: CWGame


func _init(p_game: CWGame) -> void:
	game = p_game


func apply(ev_id: String) -> void:
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
			for p in game.living_players(CWData.FACTION_IMMUNE):
				var targets := game.board.tissues_of_type(CWData.Tissue.CANCER)
				if targets.is_empty() or p.biomass < 2:
					continue
				var yes = await game.ask_option(p, "%s：是否失去 1 点生物质，净化任一普通癌组织？" % p.pname,
					["是（生物质-1）", "否"], [true, false])
				if yes == true:
					p.lose_biomass(1)
					var t = await game.ask_hex(p, "选择要净化的普通癌组织", targets)
					if t != null:
						game.board.purify(t)
						game.log_line("☀️ %s 失去 1 点生物质，净化了一块癌组织。" % p.pname)
					game.touch()
		"battle_frenzy":
			game.flag_all_crit = true
		"flood":
			game.flag_walls_off = true
		"great_flood":
			game.board.clear_walls()
			game.log_line("🌊 棋盘上所有墙壁消失！")
		"immune_boost":
			for p in game.living_players(CWData.FACTION_IMMUNE):
				await game.cards.draw_card(p)
		"cancer_boost":
			for p in game.living_players(CWData.FACTION_CANCER):
				await game.cards.draw_card(p)
		"cytokine_storm":
			game.flag_immune_atk = 1
		"immune_rage":
			game.flag_immune_rage = true
		"immune_patrol":
			game.flag_move_bonus_immune = 1
		"cancer_infiltrate":
			game.flag_move_bonus_cancer = 1
		"deterioration":
			for p in game.living_players(CWData.FACTION_CANCER):
				var opts: Array = []
				if game.board.tissue_at(p.pos) == CWData.Tissue.NORMAL:
					opts.append(p.pos)
				for n in HexLib.neighbors(p.pos):
					if HexLib.in_board(n) and game.board.tissue_at(n) == CWData.Tissue.NORMAL:
						opts.append(n)
				if opts.is_empty():
					continue
				var t = await game.ask_hex(p, "%s：选择当前或周围一块组织进行感染（可跳过）" % p.pname, opts, "跳过")
				if t != null:
					game.board.infect(t)
					game.log_line("🦠 %s 感染了一块组织。" % p.pname)
				game.touch()
		"hell_factory":
			game.perm_wall_bonus += 1
			game.log_line("🏭 此后在墙壁工厂获得的墙壁数量 +1（永久）。")
		"fibrosis":
			for p in game.living_players(CWData.FACTION_CANCER):
				var edges := game.board.buildable_edges(p.pos)
				if edges.is_empty():
					continue
				var e = await game.ask_edge(p, "%s：选择当前组织的一面生成墙壁（可跳过）" % p.pname, edges, "跳过")
				if e != null:
					var cells := HexLib.edge_cells(e)
					game.board.add_wall(cells[0], cells[1])
					game.log_line("🧱 %s 生成了一面墙壁。" % p.pname)
				game.touch()
		"metastasis_ev":
			for p in game.living_players(CWData.FACTION_CANCER):
				var targets := game.board.tissues_of_type(CWData.Tissue.NORMAL)
				if targets.is_empty() or p.biomass < 2:
					continue
				var yes = await game.ask_option(p, "%s：是否失去 1 点生物质，感染任一正常组织？" % p.pname,
					["是（生物质-1）", "否"], [true, false])
				if yes == true:
					p.lose_biomass(1)
					var t = await game.ask_hex(p, "选择要感染的正常组织", targets)
					if t != null:
						game.board.infect(t)
						game.log_line("🦠 %s 失去 1 点生物质，感染了一块组织。" % p.pname)
					game.touch()
		"immune_escape":
			game.flag_no_attack = true
		"sweet_rain":
			for p in game.living_players():
				p.gain_biomass(1)
			game.log_line("💧 所有细胞生物质 +1。")
		"chemotherapy":
			for p in game.living_players():
				if p.biomass > 1:
					p.lose_biomass(1)
			game.log_line("💊 所有生物质大于 1 的细胞生物质 -1。")
		"life_or_death":
			for p in game.living_players():
				p.biomass = 1
			game.log_line("⚠️ 所有细胞的生物质降为 1！")
		"heaven_factory":
			game.perm_bio_bonus += 1
			game.log_line("🏭 此后生物质工厂的回复量 +1（永久）。")
		"raid":
			for p in game.players:
				if not p.alive or game.game_over:
					continue
				game.log_line("⚡ 突袭：%s 移动 3 步。" % p.pname)
				await game.movement.interactive_move(p, 3)
				if p.is_immune() and p.alive:
					await game.combat.attack_check(p)
				if game.game_over:
					return
		"weakening":
			await _event_weakening(CWData.FACTION_IMMUNE)
			await _event_weakening(CWData.FACTION_CANCER)
		"recuperate":
			game.flag_rest = true
		_:
			pass


func _event_revive_faction(faction: String) -> void:
	for p in game.dead_players(faction):
		var valid: Array = []
		if faction == CWData.FACTION_CANCER:
			for h in game.board.cancer_tissues():
				valid.append(h)
		else:
			for h in HexLib.all_cells():
				if game.board.tissue_at(h) == CWData.Tissue.NORMAL:
					valid.append(h)
		if valid.is_empty():
			game.log_line("%s 没有可复活的组织，无法复活。" % p.pname)
			continue
		var t = await game.ask_hex(p, "%s 选择复活位置" % p.pname, valid)
		if t == null:
			t = valid[0]
		p.revive(t, 1)
		p.skip_this_round = true
		game.log_line("✨ %s 以 1 点生物质复活（本世界回合无法行动）。" % p.pname)
		await game.turn.offer_evo_swap(p)
		game.touch()


func _event_set_biomass_one(chooser_faction: String, target_faction: String) -> void:
	var targets := game.living_players(target_faction)
	if targets.is_empty():
		game.log_line("对方阵营无存活细胞，事件无效。")
		return
	var labels: Array = []
	for t in targets:
		labels.append("%s（生物质 %d）" % [t.pname, t.biomass])
	var pick = await game.ask_option(chooser_faction,
		"选择一名对方细胞，将其生物质降为 1", labels, targets)
	if pick == null:
		pick = targets[0]
	pick.biomass = 1
	game.log_line("🎯 %s 的生物质被降为 1！" % pick.pname)


func _event_weakening(chooser_faction: String) -> void:
	var enemy := CWData.FACTION_CANCER if chooser_faction == CWData.FACTION_IMMUNE else CWData.FACTION_IMMUNE
	var candidates: Array = []
	for p in game.players:
		if p.faction == enemy and not p.abilities.is_empty():
			candidates.append(p)
	if candidates.is_empty():
		game.log_line("%s阵营：对方没有能力牌可消除。" % CWData.faction_cn(chooser_faction))
		return
	var labels: Array = []
	for c in candidates:
		var names: Array = []
		for aid in c.abilities:
			names.append(CWData.card_def(c.faction, aid)["name"])
		labels.append("%s（%s）" % [c.pname, "、".join(names)])
	var target = await game.ask_option(chooser_faction,
		"选择一名对方角色消除其一张能力牌", labels, candidates)
	if target == null:
		target = candidates[0]
	var alabels: Array = []
	for aid in target.abilities:
		var cd := CWData.card_def(target.faction, aid)
		alabels.append("%s：%s" % [cd["name"], cd["text"]])
	var aid_pick = await game.ask_option(chooser_faction,
		"选择要消除的能力牌", alabels, target.abilities.duplicate())
	if aid_pick == null:
		aid_pick = target.abilities[0]
	target.abilities.erase(aid_pick)
	game.decks[target.faction].discard(aid_pick)
	game.log_line("🗑️ %s 的能力牌【%s】被消除。" % [target.pname, CWData.card_def(target.faction, aid_pick)["name"]])
