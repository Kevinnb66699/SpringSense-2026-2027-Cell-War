class_name MCBridge
extends HybridBridge
## 蒙特卡洛搜索桥（第 5 座桥）：human 阵营走 UI；mc_faction 阵营用"模拟对局打分"决策，
## 其余 AI 阵营沿用启发式。原理（docs/AI设计.md）：
##   每名玩家回合开始时（on_turn_start）拍局面快照并记录此后所有答案（线格式）；
##   面对决策时，对每个候选答案：还原快照 → 回放答案 → 注入候选 → 重播种 rng →
##   用启发式策略把平行世界推演 horizon 个世界回合 → 评分。取 K 局平均分最高的候选。
## 确定性红线：推演只发生在克隆局上，绝不触碰真实对局的 game.rng。

## MC 决策的阵营；"" 表示所有非人类阵营都用 MC
var mc_faction := ""
## 每个候选答案的推演局数（难度旋钮：越大越强越慢）
var playouts := 10
## 推演视界：每次推演最多再跑几个世界回合
var horizon := 4
## 候选裁剪上限（选格/选边类请求的选项可能很多）
var max_candidates := 8
## 启发式先验加成：启发式会选的那个候选直接加这么多分。
## 推演分数在小样本下有 ±10 分左右的噪声，没有先验时搜索经常在挑噪声；
## 有了先验，只有分差明显超过噪声时才推翻启发式（穷人版 policy prior）
var prior_bonus := 8.0

var _snap = null            # 当前回合起点快照（CWSnapshot.capture）
var _turn_log: Array = []   # 快照之后的全部答案（线格式）

# 统计（基准测试/调参用）
var stat_searches := 0      # 走了 MC 搜索的决策数
var stat_playouts := 0      # 累计推演局数

## 回放对齐自检：开启后每次推演都校验"克隆局回放到决策点的 state_hash == 真实局当前值"。
## 不一致说明快照漏字段或回放机制有 bug（基准脚本开着跑，UI 里关掉省时间）
var validate_replay := false
var stat_replay_mismatch := 0
var debug_progress := false   # 每 20 次搜索打一行进度（临时排查用）


## 回放桥：按队列回放线格式答案（最后一个是注入的候选），耗尽后转由启发式代打。
## 消耗掉最后一个回放答案时给克隆局的 rng 重播种——让每次推演的未来骰运各不相同。
class ReplayBridge extends CWBridge:
	var queue: Array = []
	var policy = null        # HybridBridge（human_faction=""，全 AI）
	var reseed := 0
	var game = null          # 克隆局（重播种/自检用）
	var check_hash := 0      # 非 0 时在消耗最后一个回放答案处比对 state_hash
	var mismatch := false

	func ask(req: Dictionary):
		if not queue.is_empty():
			var wire = queue.pop_front()
			if queue.is_empty():
				if check_hash != 0 and game != null and game.state_hash() != check_hash:
					mismatch = true
				if reseed != 0 and game != null:
					game.rng.seed = reseed
			return CWBridge.decode_answer(req, wire)
		return policy.ai_decide(req)


func on_turn_start(g) -> void:
	game = g
	_snap = CWSnapshot.capture(g)
	_turn_log = []


func ask(req: Dictionary):
	var v
	if _is_human(req):
		main.show_request(req)
		v = await answered
		main.clear_request()
	elif _should_search(req):
		v = await _mc_decide(req)
	else:
		if tree != null and ai_delay > 0.0:
			await tree.create_timer(ai_delay).timeout
		v = _ai_decide(req)
	_turn_log.append(CWBridge.encode_answer(req, v))
	return v


func _should_search(req: Dictionary) -> bool:
	if _snap == null or game == null or not game.setup_done or game.game_over:
		return false
	if mc_faction != "" and req.get("owner_faction", "") != mc_faction:
		return false
	return true


# ==================== 搜索 ====================

func _mc_decide(req: Dictionary):
	var wires := _candidate_wires(req)
	if wires.size() < 2:
		return _ai_decide(req)
	stat_searches += 1
	var fac: String = req.get("owner_faction", "")
	# 配对比较：所有候选共用同一组推演种子（同样的未来骰运），
	# 分数差只来自候选本身，大幅降低小样本方差
	var seeds: Array[int] = []
	for k in range(playouts):
		seeds.append(int(rng.randi() >> 1) + 1)
	var live_hash: int = game.state_hash() if validate_replay else 0
	var h_wire = CWBridge.encode_answer(req, _ai_decide(req))
	var best_wire = wires[0]
	var best_score := -INF
	var scores: Array = []
	for w in wires:
		var total := 0.0
		for k in range(playouts):
			total += await _playout_score(w, fac, seeds[k], live_hash)
		if tree != null:
			await tree.process_frame   # 别把 UI 冻死
		var avg := total / float(playouts)
		if w == h_wire:
			avg += prior_bonus
		scores.append(avg)
		if avg > best_score:
			best_score = avg
			best_wire = w
	if debug_progress and best_wire != h_wire:
		print("  [分歧] 回合%d %s「%s」MC选 %s(%.0f) 启发式选 %s | 分数=%s" %
			[game.round_num, req.get("who", ""), req.get("prompt", "").left(18),
			str(best_wire), best_score, str(h_wire), str(scores)])
	return CWBridge.decode_answer(req, best_wire)


## 候选答案列表（线格式）。选项类全收；选格/选边类超限时启发式选择必进、其余随机补齐
func _candidate_wires(req: Dictionary) -> Array:
	var t: String = req.get("type", "")
	var wires: Array = []
	if t == "pick_option":
		for i in range(req.get("values", []).size()):
			wires.append(i)
	else:
		var opts: Array = req.get("options", [])
		if opts.size() <= max_candidates:
			# 逐个搬进无类型数组——opts 是 Array[Vector2i]/Array[String]，
			# duplicate() 会保留类型，后面就塞不进 null（取消候选）了
			for o in opts:
				wires.append(o)
		else:
			var h = _ai_decide(req)
			var pool := opts.duplicate()
			if h != null:
				wires.append(h)
				pool.erase(h)
			while wires.size() < max_candidates and not pool.is_empty():
				var j := rng.randi_range(0, pool.size() - 1)
				wires.append(pool[j])
				pool.remove_at(j)
	if req.get("cancel", "") != "":
		wires.append(null)
	return wires


## 跑一次推演：克隆 → 回放到决策点 → 注入候选 → 推演 → 评分（决策方阵营视角）
func _playout_score(candidate_wire, fac: String, pseed: int, live_hash: int = 0) -> float:
	stat_playouts += 1
	var pb := ReplayBridge.new()
	pb.queue = _turn_log.duplicate()
	pb.queue.append(candidate_wire)
	pb.reseed = pseed
	pb.check_hash = live_hash
	var policy := HybridBridge.new(pseed)
	policy.human_faction = ""
	pb.policy = policy
	var clone = CWSnapshot.restore(_snap, pb)
	pb.game = clone
	policy.game = clone
	await clone.resume_game(clone.cur_player_idx, horizon)
	if pb.mismatch:
		stat_replay_mismatch += 1
	var score := _eval(clone, fac)
	clone.dispose()
	pb.game = null
	policy.game = null
	return score


## 推演终局评分（fac 阵营视角，越大越好）。
## 分出胜负给 ±1000 再叠加局面分——"输得少"与"赢得稳"之间仍有梯度；
## 未到终局按癌组织对获胜线的进度 + 固化数 + 双方兵力材料打分。
## 癌细胞存活权重给高：活着的癌细胞才是后续感染的发动机。
func _eval(g, fac: String) -> float:
	var s := float(g.board.cancer_tissue_count() - g.win_threshold()) * 10.0
	s += float(g.board.solid_tissues().size()) * 5.0
	for p in g.players:
		if not p.alive:
			continue
		if p.is_cancer():
			# 存活权重给到约 2.5 块组织：活着的癌细胞是后续感染的发动机，
			# 否则搜索会为抢一两块组织把细胞送掉
			s += 25.0 + float(p.biomass) * 1.5
		else:
			s -= 8.0 + float(p.biomass)
	if g.game_over:
		# 终局奖励别给太大：±1000 会让个别提前分胜负的推演支配平均分（方差炸弹）
		s += 300.0 if g.winner == CWData.FACTION_CANCER else -300.0
	return s if fac == CWData.FACTION_CANCER else -s
