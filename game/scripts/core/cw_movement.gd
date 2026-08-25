class_name CWMovement
extends RefCounted
## 移动阶段：掷骰得步数、逐步交互移动、移动前能力（Chemotaxis/Metastasis）、
## 移动联动效果（转移癌感染 / 血液癌血管传送 / 树突状细胞标记）。

var game: CWGame


func _init(p_game: CWGame) -> void:
	game = p_game


## 骰点转步数：1-3 → 1 步，4-5 → 2 步，6 → 3 步
func _die_steps(v: int) -> int:
	if v <= 3:
		return 1
	elif v <= 5:
		return 2
	return 3


func _move_bonus(p) -> int:
	var b := 0
	if p.is_immune():
		b += game.flag_move_bonus_immune
	else:
		b += game.flag_move_bonus_cancer
	if p.evo == "blood":
		b += 1
	return b


func move_phase(p) -> void:
	game.phase_text = "回合 %d/%d · %s · 移动阶段" % [game.round_num, CWData.TOTAL_ROUNDS, p.pname]
	game.touch()
	# 能力卡：移动阶段开始前可移动 1 步
	if p.has_ability("chemotaxis") or p.has_ability("metastasis"):
		await _pre_move_step(p)
	if not p.alive:
		return
	if p.evo == "meta":
		# 转移癌：固定移动 1 步，自动感染接触到的组织
		await interactive_move(p, 1)
		while game.extra_moves > 0 and p.alive and not game.game_over:
			game.extra_moves -= 1
			var use = await game.ask_option(p.pname, "使用额外移动机会？（转移癌固定 1 步）",
				["移动 1 步", "放弃"], [true, false])
			if use != true:
				break
			await interactive_move(p, 1)
		return
	var pick = await game.ask_option(p.pname, "%s：移动阶段" % p.pname,
		["掷骰移动", "跳过移动"], ["roll", "skip"])
	if pick == "roll":
		var v: int = await game.d6("%s 移动" % p.pname)
		var steps := _die_steps(v) + _move_bonus(p)
		game.log_line("%s 可移动 %d 步。" % [p.pname, steps])
		await interactive_move(p, steps)
		if p.is_immune() and p.alive and not game.game_over:
			await game.combat.attack_check(p)
	# 额外移动机会
	while game.extra_moves > 0 and p.alive and not game.game_over:
		game.extra_moves -= 1
		var use = await game.ask_option(p.pname, "%s：使用额外移动机会？（重新掷骰移动）" % p.pname,
			["掷骰移动", "放弃"], [true, false])
		if use != true:
			break
		var v2: int = await game.d6("%s 额外移动" % p.pname)
		var steps2 := _die_steps(v2) + _move_bonus(p)
		game.log_line("%s 可移动 %d 步。" % [p.pname, steps2])
		await interactive_move(p, steps2)
		if p.is_immune() and p.alive and not game.game_over:
			await game.combat.attack_check(p)


func _pre_move_step(p) -> void:
	var legal: Array = []
	for n in HexLib.neighbors(p.pos):
		if game.board.can_step(p.pos, n, p.ignores_walls() or game.flag_walls_off):
			legal.append(n)
	if legal.is_empty():
		return
	var aname := "Chemotaxis" if p.is_immune() else "Metastasis"
	var t = await game.ask_hex(p.pname, "%s：能力【%s】可在移动阶段前移动 1 步（可跳过）" % [p.pname, aname], legal, "跳过",
		{"tag": "move_step", "actor": p})
	if t == null:
		return
	_do_step(p, t)
	game.touch()


## 执行一步移动（更新方向、转移癌感染、血液癌血管传送、树突标记）
func _do_step(p, to: Vector2i) -> void:
	p.last_dir = HexLib.dir_index(to - p.pos)
	p.pos = to
	p.moved_this_turn = true
	if p.evo == "meta":
		if game.board.infect(p.pos):
			game.log_line("🦠 转移癌：%s 感染了脚下的组织。" % p.pname)
	if p.evo == "blood" and game.board.special_kind(p.pos) == CWData.SP_VESSEL:
		var other := game.board.other_vessel(p.pos)
		if other != p.pos:
			p.pos = other
			game.log_line("🚇 血液癌：%s 经过血管，立即传送！" % p.pname)
	if p.evo == "dendritic":
		mark_dendritic(p)


## 树突状细胞：给攻击范围内的癌细胞添加【易伤】标记（cw_combat 也会调用）
func mark_dendritic(p) -> void:
	for c in game.living_players(CWData.FACTION_CANCER):
		if c.vulnerable:
			continue
		if game.attack_dist(p, c.pos, p.attack_range()) >= 0:
			c.vulnerable = true
			game.log_line("🔖 树突状细胞：%s 被添加【易伤】标记！" % c.pname)


func interactive_move(p, steps: int) -> void:
	var remaining := steps
	while remaining > 0 and p.alive:
		var legal: Array = []
		for n in HexLib.neighbors(p.pos):
			if game.board.can_step(p.pos, n, p.ignores_walls() or game.flag_walls_off):
				legal.append(n)
		if legal.is_empty():
			game.log_line("%s 无路可走，移动结束。" % p.pname)
			return
		var t = await game.ask_hex(p.pname, "%s：选择移动方向（剩余 %d 步）" % [p.pname, remaining], legal, "结束移动",
			{"tag": "move_step", "actor": p})
		if t == null:
			return
		_do_step(p, t)
		remaining -= 1
		game.touch()
	if p.evo == "dendritic":
		mark_dendritic(p)
