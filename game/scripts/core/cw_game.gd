class_name CWGame
extends RefCounted
## 游戏总控：持有全部对局状态与通用工具，具体流程委托给各功能模块执行。
## 模块划分（都在 scripts/core/ 下，按功能查找与修改）：
##   cw_setup.gd     布置阶段（特殊事件 / 癌组织 / 初始位置）
##   cw_world.gd     世界回合开始（清标记 / 固化衰减 / 进化 / 事件触发）
##   cw_events.gd    27 个世界事件的效果
##   cw_turn.gd      玩家回合时序（复活 / 卡池 / 工厂 / 抽卡 / 特殊行动）
##   cw_movement.gd  移动阶段与逐步移动
##   cw_combat.gd    攻击 / 击退 / 双重打击 / 击杀
##   cw_cards.gd     抽卡与 28 种卡牌效果
## 所有需要玩家决策的地方通过 bridge.ask() 问答（UI 或自动测试提供答案）。

var board: CWBoard
var players: Array = []          # CWPlayer，按行动顺序
var decks: Dictionary = {}       # faction -> CWDeck
var bridge                        # CWBridge
var rng := RandomNumberGenerator.new()

# ---- 功能模块 ----
var setup: CWSetup
var world: CWWorld
var events: CWEvents
var turn: CWTurn
var movement: CWMovement
var combat: CWCombat
var cards: CWCards

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
	setup = CWSetup.new(self)
	world = CWWorld.new(self)
	events = CWEvents.new(self)
	turn = CWTurn.new(self)
	movement = CWMovement.new(self)
	combat = CWCombat.new(self)
	cards = CWCards.new(self)


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


## 对局结束后断开与功能模块/桥的循环引用（RefCounted 不做环回收，不断开会泄漏）
func dispose() -> void:
	bridge = null
	setup = null
	world = null
	events = null
	turn = null
	movement = null
	combat = null
	cards = null


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


## 决策归属字段（联机路由预留）。who 接受两种形式：
##   CWPlayer —— 个人决策，请求带 owner_id（玩家 id）与 owner_faction
##   阵营常量 CWData.FACTION_* —— 阵营级决策，owner_id 为 -1
## req.who 仍是显示用字符串，UI 不受影响。
func _who_fields(who) -> Dictionary:
	if who is CWPlayer:
		return {"who": who.pname, "owner_id": who.id, "owner_faction": who.faction}
	return {"who": CWData.faction_cn(who) + "阵营", "owner_id": -1, "owner_faction": who}


func ask_option(who, prompt: String, labels: Array, values: Array, cancel: String = ""):
	var req := _who_fields(who)
	req["type"] = "pick_option"
	req["prompt"] = prompt
	req["labels"] = labels
	req["values"] = values
	req["cancel"] = cancel
	return await bridge.ask(req)


func ask_hex(who, prompt: String, options: Array, cancel: String = "", extra: Dictionary = {}):
	var req := _who_fields(who)
	req["type"] = "pick_hex"
	req["prompt"] = prompt
	req["options"] = options
	req["cancel"] = cancel
	for k in extra:
		req[k] = extra[k]
	return await bridge.ask(req)


func ask_edge(who, prompt: String, options: Array, cancel: String = ""):
	var req := _who_fields(who)
	req["type"] = "pick_edge"
	req["prompt"] = prompt
	req["options"] = options
	req["cancel"] = cancel
	return await bridge.ask(req)


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


## 局面摘要哈希：确定性回归测试用；将来联机锁步时各端定期比对以检测失步。
## ⚠️ 引擎新增影响规则的状态时，记得把它加进这里。
func state_hash() -> int:
	var parts: Array = [round_num, cur_player_idx, game_over, winner, extra_moves,
		flag_all_crit, flag_walls_off, flag_immune_atk, flag_immune_rage,
		flag_move_bonus_immune, flag_move_bonus_cancer, flag_no_attack, flag_rest,
		perm_wall_bonus, perm_bio_bonus, used_limited]
	var hexes := board.tissue.keys()
	hexes.sort()
	for h in hexes:
		parts.append([h, board.tissue[h], board.solid_count.get(h, 0)])
	var sp_keys := board.specials.keys()
	sp_keys.sort()
	for h in sp_keys:
		parts.append([h, board.specials[h]["kind"], board.specials[h]["active"]])
	var wall_keys := board.walls.keys()
	wall_keys.sort()
	parts.append(wall_keys)
	for p in players:
		parts.append([p.pos, p.alive, p.biomass, p.evo, p.abilities,
			p.walls_stock, p.kills, p.stunned, p.skip_this_round, p.vulnerable,
			p.dodge_next, p.keratin_next, p.infdiv_next,
			p.next_atk_power, p.next_atk_range, p.next_atk_sure, p.last_dir])
	for f in [CWData.FACTION_IMMUNE, CWData.FACTION_CANCER]:
		var d: CWDeck = decks[f]
		parts.append([d.draw_pile, d.discard_pile])
	return hash(parts)


# ==================== 主流程 ====================

func run_setup() -> void:
	await setup.run()


func run_game() -> void:
	for r in range(1, CWData.TOTAL_ROUNDS + 1):
		round_num = r
		await world.round_start()
		if game_over:
			return
		for i in range(players.size()):
			cur_player_idx = i
			await turn.run(players[i])
			if game_over:
				return
		cur_player_idx = -1
	_final_scoring()


# ==================== 胜负判定 ====================

func check_immediate_win() -> void:
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
