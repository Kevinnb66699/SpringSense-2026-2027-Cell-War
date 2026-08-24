class_name HybridBridge
extends CWBridge
## 人机对弈桥：人类阵营的决策交给界面等待点击，AI 阵营用启发式策略自动决策。
## 决策归属通过请求的 who 字段判断（"免疫×" / "癌×"，词表由 cw_game 控制）。
## human_faction 为空字符串时双方都由 AI 操作（用于测试）。

var game = null                  # CWGame（_start 后由 main 赋值，AI 决策需要读取局面）
var tree: SceneTree = null
var human_faction := ""          # CWData.FACTION_IMMUNE / FACTION_CANCER / ""(全AI)
var rng := RandomNumberGenerator.new()
var ai_delay := 0.3

signal answered(value)

## AI 进化偏好（靠前优先）。癌症以机动与坦度优先——转移癌固定 1 步对 AI 是死亡陷阱
const IMMUNE_EVO_PREF := ["nk", "t_cell", "mem_t", "b_cell", "macro", "neutro", "mem_b", "dendritic"]
const CANCER_EVO_PREF := ["blood", "solid_evo", "stem", "meta"]


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value


func ask(req: Dictionary):
	if _is_human(req):
		main.show_request(req)
		var v = await answered
		main.clear_request()
		return v
	if tree != null and ai_delay > 0.0:
		await tree.create_timer(ai_delay).timeout
	return _ai_decide(req)


func answer(v) -> void:
	answered.emit(v)


func _is_human(req: Dictionary) -> bool:
	var who: String = req.get("who", "")
	var f := ""
	if who.contains("免疫"):
		f = CWData.FACTION_IMMUNE
	elif who.contains("癌"):
		f = CWData.FACTION_CANCER
	else:
		return true   # 无法判断归属时交给人类，保证不吞决策
	return f == human_faction


# ==================== AI 决策 ====================

func _ai_decide(req: Dictionary):
	var t: String = req.get("type", "")
	if t == "pick_option":
		return _ai_option(req)
	elif t == "pick_hex":
		return _ai_hex(req)
	elif t == "pick_edge":
		return _ai_edge(req)
	return null


func _pick_random(arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]


func _ai_option(req: Dictionary):
	var values: Array = req.get("values", [])
	var prompt: String = req.get("prompt", "")
	if values.is_empty():
		return null
	# 布置：采用官方布局
	if values.has("official"):
		return "official"
	# 复活：能复活就复活（固化优先）
	if values.has("solid"):
		return "solid"
	if values.has("stem"):
		return "stem"
	# 复活后换能力：保持
	if values.has("keep"):
		return "keep"
	# 自由抽卡：生物质满 5 才燃烧；癌细胞受威胁时不燃烧（生物质就是命）
	if values.has("done") and (values.has("burn") or values.has("mutate")):
		var p = game.cur_player() if game != null else null
		if p != null and values.has("burn") and p.biomass >= 5:
			if p.is_cancer() and _nearest_immune_dist(p.pos) <= 3:
				return "done"
			return "burn"
		return "done"
	# 移动阶段：休养生息且生物质低时休息，否则掷骰
	if values.has("roll"):
		if game != null and game.flag_rest:
			var p2 = game.cur_player()
			if p2 != null and p2.biomass <= 3:
				return "skip"
		return "roll"
	# 特殊行动
	if values.has("purify"):
		return "purify"
	if values.has("demolish"):
		return "demolish"
	# 癌细胞被逼近且有存墙：先筑墙自保
	if values.has("build") and game != null:
		var pb = game.cur_player()
		if pb != null and _nearest_immune_dist(pb.pos) <= 2:
			return "build"
	if values.has("infect"):
		return "infect"
	if values.has("solidify"):
		if values.has("build") and rng.randf() < 0.35:
			return "build"
		return "solidify"
	if values.has("build"):
		return "build" if rng.randf() < 0.5 else "skip"
	# 进化选择（值为进化 id）
	for pid in CANCER_EVO_PREF:
		if values.has(pid):
			return pid
	for pid in IMMUNE_EVO_PREF:
		if values.has(pid):
			return pid
	# 是/否类：额外移动总是用；付费类（失去生物质）看运气
	if values.size() == 2 and typeof(values[0]) == TYPE_BOOL:
		if prompt.contains("额外移动"):
			return true
		if prompt.contains("失去 1 点生物质"):
			return true if rng.randf() < 0.7 else false
		return true
	# 选玩家（值为 CWPlayer 对象）：针对"对方"选生物质最高者，其余选第一个
	if values[0] is CWPlayer:
		if prompt.contains("对方"):
			var best = values[0]
			for v in values:
				if v.biomass > best.biomass:
					best = v
			return best
		return values[0]
	# 方向 / 直线等数字选项：随机
	if typeof(values[0]) == TYPE_INT:
		return _pick_random(values)
	return values[0]


func _ai_hex(req: Dictionary):
	var options: Array = req.get("options", [])
	if options.is_empty():
		return null
	var tag: String = req.get("tag", "")
	if tag == "move_step":
		return _ai_move_step(req)
	if tag == "setup_pos":
		# 初始位置：尽量靠近棋盘中心
		var best = options[0]
		var bd := 999
		for o in options:
			var d := HexLib.distance(o, Vector2i.ZERO)
			if d < bd:
				bd = d
				best = o
		return best
	if tag == "attack_target" and game != null:
		# 攻击目标：优先生物质最低（击杀潜力最大）
		var best2 = options[0]
		var bb := 99
		for o in options:
			for c in game.living_players(CWData.FACTION_CANCER):
				if c.pos == o and c.biomass < bb:
					bb = c.biomass
					best2 = o
		return best2
	return _pick_random(options)


## 移动一步：朝目标走；已到目标或无法接近时可能停下
func _ai_move_step(req: Dictionary):
	var options: Array = req.get("options", [])
	var actor = req.get("actor")
	if actor == null or game == null:
		return _pick_random(options)
	# 癌细胞的求生本能：免疫细胞在其最大移动力（3 格）内时优先逃离，
	# 逃跑路线倾向踩上正常组织（边逃边感染）
	if actor.is_cancer() and _nearest_immune_dist(actor.pos) <= 3:
		var best_opts: Array = []
		var best_score := -999
		for o in options:
			var s: int = _nearest_immune_dist(o) * 10
			if game.board.tissue_at(o) == CWData.Tissue.NORMAL:
				s += 3
			if s > best_score:
				best_score = s
				best_opts = [o]
			elif s == best_score:
				best_opts.append(o)
		return _pick_random(best_opts)
	var goal = _move_goal(actor)
	if goal == null:
		return null
	var gpos: Vector2i = goal
	if actor.pos == gpos:
		return null
	var curd := HexLib.distance(actor.pos, gpos)
	var best_opts: Array = []
	var best_d := 999
	for o in options:
		var d := HexLib.distance(o, gpos)
		if d < best_d:
			best_d = d
			best_opts = [o]
		elif d == best_d:
			best_opts.append(o)
	if best_d >= curd and rng.randf() < 0.5:
		return null   # 被墙挡住绕不过去，一半概率原地停下
	return _pick_random(best_opts)


## AI 的移动目标：癌细胞 → 最近的正常组织（去感染）；免疫 → 最近的癌细胞（去攻击），
## 没有存活癌细胞时 → 最近的癌组织（去净化）
func _move_goal(actor):
	if actor.is_cancer():
		if game.board.tissue_at(actor.pos) == CWData.Tissue.NORMAL:
			return actor.pos
		var best = null
		var bd := 999
		for h in HexLib.all_cells():
			if game.board.tissue_at(h) == CWData.Tissue.NORMAL:
				var d := HexLib.distance(actor.pos, h)
				if d < bd:
					bd = d
					best = h
		return best
	var best2 = null
	var bd2 := 999
	for c in game.living_players(CWData.FACTION_CANCER):
		var d2 := HexLib.distance(actor.pos, c.pos)
		if d2 < bd2:
			bd2 = d2
			best2 = c.pos
	if best2 != null:
		return best2
	for h in game.board.cancer_tissues():
		var d3 := HexLib.distance(actor.pos, h)
		if d3 < bd2:
			bd2 = d3
			best2 = h
	return best2


func _nearest_immune_dist(pos: Vector2i) -> int:
	var bd := 999
	if game == null:
		return bd
	for q in game.living_players(CWData.FACTION_IMMUNE):
		var d := HexLib.distance(pos, q.pos)
		if d < bd:
			bd = d
	return bd


func _ai_edge(req: Dictionary):
	var options: Array = req.get("options", [])
	if options.is_empty():
		return null
	# 癌细胞建墙：优先堵向最近免疫细胞的方向，且有墙就一直放
	if game != null:
		var p = game.cur_player()
		if p != null and p.is_cancer():
			var ipos = _nearest_immune_pos()
			if ipos != null:
				var target_pos: Vector2i = ipos
				var best = options[0]
				var bd := 999
				for k in options:
					var cells := HexLib.edge_cells(k)
					var other: Vector2i = cells[1] if cells[0] == p.pos else cells[0]
					var d := HexLib.distance(other, target_pos)
					if d < bd:
						bd = d
						best = k
				return best
	var cancel: String = req.get("cancel", "")
	if cancel != "" and rng.randf() < 0.5:
		return null
	return _pick_random(options)


func _nearest_immune_pos():
	if game == null or game.cur_player() == null:
		return null
	var from: Vector2i = game.cur_player().pos
	var best = null
	var bd := 999
	for q in game.living_players(CWData.FACTION_IMMUNE):
		var d := HexLib.distance(from, q.pos)
		if d < bd:
			bd = d
			best = q.pos
	return best
