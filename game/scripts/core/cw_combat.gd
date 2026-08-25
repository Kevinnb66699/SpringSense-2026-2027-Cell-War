class_name CWCombat
extends RefCounted
## 战斗结算：攻击目标选择、三档攻击判定（失败/成功/大成功）、
## 击退与双重打击、击杀。

var game: CWGame


func _init(p_game: CWGame) -> void:
	game = p_game


func attack_check(p) -> void:
	if game.flag_no_attack:
		return
	if p.evo == "dendritic":
		game.movement.mark_dendritic(p)
		return
	var rng_range: int = p.attack_range()
	var targets: Array = []
	for c in game.living_players(CWData.FACTION_CANCER):
		if game.attack_dist(p, c.pos, rng_range) >= 0:
			targets.append(c)
	if targets.is_empty():
		return
	var target = targets[0]
	if targets.size() > 1:
		var opts: Array = []
		for c in targets:
			opts.append(c.pos)
		var pos_pick = await game.ask_hex(p.pname, "%s：选择攻击目标" % p.pname, opts, "", {"tag": "attack_target", "actor": p})
		if pos_pick != null:
			for c in targets:
				if c.pos == pos_pick:
					target = c
					break
	var dir: int = p.last_dir
	if dir < 0:
		var dpick = await game.ask_option(p.pname, "%s：本回合未移动，选择攻击/击退方向" % p.pname,
			HexLib.DIR_NAMES.duplicate(), [0, 1, 2, 3, 4, 5])
		dir = 0 if dpick == null else dpick
	await _perform_attack(p, target, dir, false)


func _perform_attack(atk, tgt, dir: int, is_double: bool) -> void:
	if game.flag_no_attack or game.game_over:
		return
	game.log_line("⚔️ %s 攻击 %s！" % [atk.pname, tgt.pname])
	# Dodge：逃逸下一次攻击
	if tgt.dodge_next:
		tgt.dodge_next = false
		_consume_attack_buffs(atk)
		game.log_line("💨 %s 使用 Dodge 逃逸了这次攻击！" % tgt.pname)
		game.touch()
		return
	var was_vulnerable: bool = tgt.vulnerable
	tgt.vulnerable = false
	# 攻击力快照（含回合增益）
	var raged: bool = game.flag_immune_rage and atk.biomass > 1
	var power: int = atk.attack_power() + game.flag_immune_atk
	if raged:
		power += 1
	var sure: bool = atk.next_atk_sure
	_consume_attack_buffs(atk)
	# 判定档位：0 失败 / 1 成功 / 2 大成功
	var tier := 0
	if game.flag_all_crit or atk.evo == "nk":
		tier = 2
		game.log_line("💥 攻击必然大成功！")
	else:
		var v: int = await game.d6("%s 攻击判定" % atk.pname)
		if v <= 1:
			tier = 0
		elif v <= 3:
			tier = 1
		else:
			tier = 2
		if tier == 0 and (sure or was_vulnerable):
			tier = 1
			game.log_line("🎯 攻击必然成功（%s）！" % ("必中" if sure else "易伤"))
	if tier == 0:
		game.log_line("❌ 攻击失败！")
		if not is_double:
			_retreat(atk, (dir + 3) % 6)
	elif tier == 1:
		game.log_line("✅ 攻击成功，%s 被击退 1 步。" % tgt.pname)
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
			game.log_line("🛡️ Keratinization：%s 免疫了本次攻击的生物质伤害！" % tgt.pname)
		var attacked_tile: Vector2i = tgt.pos
		var lost: int = tgt.lose_biomass(dmg)
		game.log_line("💥 大成功！%s 失去 %d 点生物质（剩余 %d）。" % [tgt.pname, lost, tgt.biomass])
		if atk.evo == "macro" and lost > 0:
			var healed: int = atk.gain_biomass(lost)
			if healed > 0:
				game.log_line("🍽️ 巨噬细胞：%s 回复 %d 点生物质。" % [atk.pname, healed])
		if raged:
			atk.lose_biomass(1)
			game.log_line("🔥 免疫暴走：%s 大成功后失去 1 点生物质（剩余 %d）。" % [atk.pname, atk.biomass])
			if atk.biomass <= 0:
				_kill(atk, null)
		if tgt.biomass <= 0:
			_kill(tgt, atk)
		else:
			await _knockback(tgt, dir, power, atk)
		if game.board.tissue_at(attacked_tile) == CWData.Tissue.CANCER:
			game.board.purify(attacked_tile)
			game.log_line("☀️ 被攻击处的普通癌组织被净化！")
	game.touch()


func _consume_attack_buffs(atk) -> void:
	atk.next_atk_power = 0
	atk.next_atk_range = 0
	atk.next_atk_sure = false


func _retreat(p, dir: int) -> void:
	var to: Vector2i = p.pos + HexLib.DIRS[dir]
	if not HexLib.in_board(to):
		game.log_line("%s 已在棋盘边缘，无法后退。" % p.pname)
		return
	if not (p.ignores_walls() or game.flag_walls_off) and game.board.has_wall(p.pos, to):
		game.log_line("%s 被墙壁挡住，无法后退。" % p.pname)
		return
	p.pos = to
	game.log_line("↩️ %s 后退 1 步。" % p.pname)


func _knockback(tgt, dir: int, n: int, from_attacker) -> void:
	if tgt.infdiv_next:
		tgt.infdiv_next = false
		game.log_line("🧬 Infinite division：%s 不会被击退！" % tgt.pname)
		return
	var steps := n
	var moved := 0
	while steps > 0:
		var next: Vector2i = tgt.pos + HexLib.DIRS[dir]
		if not HexLib.in_board(next):
			tgt.stunned = true
			game.log_line("💫 %s 被击退出棋盘边缘，停留在边缘并眩晕（跳过下一回合）！" % tgt.pname)
			break
		tgt.pos = next
		moved += 1
		steps -= 1
	if moved > 0:
		game.log_line("%s 被击退 %d 步。" % [tgt.pname, moved])
	game.touch()
	if not tgt.alive or game.game_over:
		return
	# 双重打击：击退后的位置位于其他免疫细胞攻击范围内
	var candidates: Array = []
	for q in game.living_players(CWData.FACTION_IMMUNE):
		if q == from_attacker or q.evo == "dendritic":
			continue
		if game.attack_dist(q, tgt.pos, q.attack_range()) >= 0:
			candidates.append(q)
	if candidates.is_empty():
		return
	var striker = candidates[0]
	if candidates.size() > 1:
		var labels: Array = []
		for q in candidates:
			labels.append(q.pname)
		var pick = await game.ask_option("免疫阵营", "双重打击！选择由哪名免疫细胞追击 %s" % tgt.pname, labels, candidates)
		if pick != null:
			striker = pick
	game.log_line("⚡ 双重打击！%s 追击 %s！" % [striker.pname, tgt.pname])
	await _perform_attack(striker, tgt, dir, true)


func _kill(p, killer) -> void:
	p.die()
	game.log_line("☠️ %s 死亡！" % p.pname)
	if killer != null and killer.is_immune() and p.is_cancer():
		killer.kills += 1
		if killer.evo == "mem_b":
			game.log_line("🧠 记忆B细胞：%s 攻击距离提升（击杀数 %d）。" % [killer.pname, killer.kills])
		elif killer.evo == "mem_t":
			game.log_line("🧠 记忆T细胞：%s 攻击力提升（击杀数 %d）。" % [killer.pname, killer.kills])
	game.check_immediate_win()
	game.touch()
