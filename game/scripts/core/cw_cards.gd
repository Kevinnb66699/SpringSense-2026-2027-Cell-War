class_name CWCards
extends RefCounted
## 抽卡入口与 28 种卡牌效果。卡牌名称/文案/张数定义在 cw_data.gd 的
## CARDS_IMMUNE / CARDS_CANCER；想改某张卡的效果直接改 _apply_card()。

var game: CWGame


func _init(p_game: CWGame) -> void:
	game = p_game


func draw_card(p) -> void:
	if not p.alive:
		return
	var deck: CWDeck = game.decks[p.faction]
	var cid: String = deck.draw()
	if cid == "":
		game.log_line("%s 的卡池与弃牌堆已空，无法抽卡。" % CWData.faction_cn(p.faction))
		return
	var def := CWData.card_def(p.faction, cid)
	game.log_line("🃏 %s 抽到【%s】（%s）：%s" % [p.pname, def["name"],
		"能力" if def["kind"] == "ability" else "即时", def["text"]])
	game.touch()
	if def["kind"] == "ability":
		p.abilities.append(cid)
	else:
		await _apply_card(p, cid)
		deck.discard(cid)
	game.touch()


func _apply_card(p, cid: String) -> void:
	match cid:
		"diapedesis", "invasion":
			var steps := 3
			if p.evo == "blood":
				steps += 1
			await game.movement.interactive_move(p, steps)
			if p.is_immune() and p.alive and not game.game_over:
				await game.combat.attack_check(p)
		"glucose":
			p.gain_biomass(1)
		"maltose":
			p.gain_biomass(2)
		"balanced_diet":
			for q in game.living_players(CWData.FACTION_IMMUNE):
				q.gain_biomass(1)
			game.log_line("所有免疫细胞生物质 +1。")
		"starvation":
			for q in game.living_players(CWData.FACTION_CANCER):
				q.gain_biomass(1)
			game.log_line("所有癌细胞生物质 +1。")
		"teleporting":
			var opts: Array = []
			if p.is_cancer():
				for h in game.board.cancer_tissues():
					opts.append(h)
			else:
				for h in HexLib.all_cells():
					if game.board.tissue_at(h) == CWData.Tissue.NORMAL:
						opts.append(h)
			if opts.is_empty():
				return
			var t = await game.ask_hex(p, "Teleporting：选择传送目的地（己方阵营组织）", opts)
			if t != null:
				p.pos = t
				game.log_line("🌀 %s 传送完成。" % p.pname)
		"translocation":
			var mates: Array = []
			var labels: Array = []
			for q in game.living_players(p.faction):
				if q != p:
					mates.append(q)
					labels.append(q.pname)
			if mates.is_empty():
				game.log_line("没有存活的队友，卡牌无效。")
				return
			var mate = await game.ask_option(p, "Translocation：选择交换位置的队友", labels, mates)
			if mate == null:
				mate = mates[0]
			var tmp: Vector2i = p.pos
			p.pos = mate.pos
			mate.pos = tmp
			game.log_line("🔁 %s 与 %s 交换了位置。" % [p.pname, mate.pname])
		"good_drug", "bad_drug":
			await draw_card(p)
			await draw_card(p)
		"evolution", "mutation":
			if p.biomass > 1:
				await draw_card(p)
				await draw_card(p)
				await draw_card(p)
				p.lose_biomass(1)
				game.log_line("%s 失去 1 点生物质。" % p.pname)
			else:
				game.log_line("生物质不足（需大于 1），卡牌无效。")
		"good_day":
			var targets := game.board.tissues_of_type(CWData.Tissue.CANCER)
			if targets.is_empty():
				game.log_line("棋盘上没有普通癌组织，卡牌无效。")
				return
			var t = await game.ask_hex(p, "Good day：选择一块普通癌组织转变为正常组织", targets)
			if t != null:
				game.board.purify(t)
				game.log_line("☀️ 一块癌组织被转变为正常组织。")
		"bad_day":
			var targets := game.board.tissues_of_type(CWData.Tissue.NORMAL)
			if targets.is_empty():
				return
			var t = await game.ask_hex(p, "Bad day：选择一块正常组织转变为普通癌组织", targets)
			if t != null:
				game.board.infect(t)
				game.log_line("🦠 一块正常组织被转变为癌组织。")
		"vegf":
			var vessels := game.board.special_positions(CWData.SP_VESSEL)
			if vessels.is_empty():
				return
			var v = await game.ask_hex(p, "VEGF：选择要移动的血管", vessels)
			if v == null:
				v = vessels[0]
			var dests: Array = []
			for h in HexLib.all_cells():
				if game.board.specials.has(h):
					continue
				var d := HexLib.distance(v, h)
				if d >= 1 and d <= 3:
					dests.append(h)
			if dests.is_empty():
				return
			var dest = await game.ask_hex(p, "VEGF：选择血管的新位置（1-3 步内，不与其他特殊事件重合）", dests)
			if dest != null:
				game.board.move_special(v, dest)
				game.log_line("🩸 血管被移动了。")
		"info_detect", "infiltration":
			if game.cur_player() == p:
				game.extra_moves += 1
				game.log_line("👟 %s 本回合获得 1 次额外移动机会。" % p.pname)
			else:
				game.log_line("（非自己回合抽到，额外移动机会无效。）")
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
			var axis = await game.ask_option(p, "Excalibur：选择净化的直线方向（以自己为中心）",
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
				if game.board.purify(h):
					n += 1
			game.log_line("🗡️ Excalibur！一条直线上的 %d 块普通癌组织被净化！" % n)
		"nuclear":
			var targets := game.board.tissues_of_type(CWData.Tissue.CANCER)
			if targets.is_empty():
				game.log_line("棋盘上没有普通癌组织，卡牌无效。")
				return
			var t = await game.ask_hex(p, "Nuclear radiation：选择一块普通癌组织直接固化", targets)
			if t != null:
				game.board.solidify_full(t)
				game.log_line("🪨 一块普通癌组织被直接固化！")
		_:
			pass
