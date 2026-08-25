class_name CWSnapshot
extends RefCounted
## 对局状态快照（内存 Dictionary 形式）：capture 拍下 CWGame 的全部规则状态，
## restore 在一个全新的 CWGame 上还原并继续运行。
## 用途：蒙特卡洛 AI 的推演克隆；将来可扩展为存档（var_to_str 落盘）与联机断线恢复。
##
## ⚠️ 引擎新增影响规则的状态时，这里和 CWGame.state_hash() 都要加上——
## 快照漏字段的症状是"克隆局与真实局走着走着分叉"，由无头测试的快照等价性检查兜底。


static func capture(g) -> Dictionary:
	var players_data: Array = []
	for p in g.players:
		players_data.append({
			"pos": p.pos, "alive": p.alive, "biomass": p.biomass,
			"evo": p.evo, "abilities": p.abilities.duplicate(),
			"walls_stock": p.walls_stock, "kills": p.kills,
			"stunned": p.stunned, "skip_this_round": p.skip_this_round,
			"vulnerable": p.vulnerable, "dodge_next": p.dodge_next,
			"keratin_next": p.keratin_next, "infdiv_next": p.infdiv_next,
			"next_atk_power": p.next_atk_power, "next_atk_range": p.next_atk_range,
			"next_atk_sure": p.next_atk_sure, "last_dir": p.last_dir,
			"moved_this_turn": p.moved_this_turn,
			"used_special_this_turn": p.used_special_this_turn,
		})
	var decks_data: Dictionary = {}
	for f in g.decks:
		var d = g.decks[f]
		decks_data[f] = {
			"draw_pile": d.draw_pile.duplicate(),
			"discard_pile": d.discard_pile.duplicate(),
		}
	var specials_data: Dictionary = {}
	for h in g.board.specials:
		specials_data[h] = g.board.specials[h].duplicate()
	return {
		"num_players": g.num_players,
		"round_num": g.round_num, "cur_player_idx": g.cur_player_idx,
		"game_over": g.game_over, "winner": g.winner, "win_reason": g.win_reason,
		"setup_done": g.setup_done,
		"flag_all_crit": g.flag_all_crit, "flag_walls_off": g.flag_walls_off,
		"flag_immune_atk": g.flag_immune_atk, "flag_immune_rage": g.flag_immune_rage,
		"flag_move_bonus_immune": g.flag_move_bonus_immune,
		"flag_move_bonus_cancer": g.flag_move_bonus_cancer,
		"flag_no_attack": g.flag_no_attack, "flag_rest": g.flag_rest,
		"perm_wall_bonus": g.perm_wall_bonus, "perm_bio_bonus": g.perm_bio_bonus,
		"used_limited": g.used_limited.duplicate(),
		"extra_moves": g.extra_moves,
		"phase_text": g.phase_text, "last_event_text": g.last_event_text,
		"rng_seed": g.rng.seed, "rng_state": g.rng.state,
		"tissue": g.board.tissue.duplicate(),
		"solid_count": g.board.solid_count.duplicate(),
		"specials": specials_data,
		"walls": g.board.walls.duplicate(),
		"players": players_data,
		"decks": decks_data,
	}


static func restore(snap: Dictionary, bridge):
	# 种子随便给个非 0 值避免 randomize()，随后用快照的 seed+state 精确覆盖
	var g = CWGame.new(bridge, snap["num_players"], 1)
	g.rng.seed = snap["rng_seed"]
	g.rng.state = snap["rng_state"]
	g.round_num = snap["round_num"]
	g.cur_player_idx = snap["cur_player_idx"]
	g.game_over = snap["game_over"]
	g.winner = snap["winner"]
	g.win_reason = snap["win_reason"]
	g.setup_done = snap["setup_done"]
	g.flag_all_crit = snap["flag_all_crit"]
	g.flag_walls_off = snap["flag_walls_off"]
	g.flag_immune_atk = snap["flag_immune_atk"]
	g.flag_immune_rage = snap["flag_immune_rage"]
	g.flag_move_bonus_immune = snap["flag_move_bonus_immune"]
	g.flag_move_bonus_cancer = snap["flag_move_bonus_cancer"]
	g.flag_no_attack = snap["flag_no_attack"]
	g.flag_rest = snap["flag_rest"]
	g.perm_wall_bonus = snap["perm_wall_bonus"]
	g.perm_bio_bonus = snap["perm_bio_bonus"]
	g.used_limited.assign(snap["used_limited"])
	g.extra_moves = snap["extra_moves"]
	g.phase_text = snap["phase_text"]
	g.last_event_text = snap["last_event_text"]
	g.board.tissue = snap["tissue"].duplicate()
	g.board.solid_count = snap["solid_count"].duplicate()
	g.board.walls = snap["walls"].duplicate()
	g.board.specials = {}
	for h in snap["specials"]:
		g.board.specials[h] = snap["specials"][h].duplicate()
	for i in range(g.players.size()):
		var p = g.players[i]
		var d: Dictionary = snap["players"][i]
		p.pos = d["pos"]
		p.alive = d["alive"]
		p.biomass = d["biomass"]
		p.evo = d["evo"]
		p.abilities.assign(d["abilities"])
		p.walls_stock = d["walls_stock"]
		p.kills = d["kills"]
		p.stunned = d["stunned"]
		p.skip_this_round = d["skip_this_round"]
		p.vulnerable = d["vulnerable"]
		p.dodge_next = d["dodge_next"]
		p.keratin_next = d["keratin_next"]
		p.infdiv_next = d["infdiv_next"]
		p.next_atk_power = d["next_atk_power"]
		p.next_atk_range = d["next_atk_range"]
		p.next_atk_sure = d["next_atk_sure"]
		p.last_dir = d["last_dir"]
		p.moved_this_turn = d["moved_this_turn"]
		p.used_special_this_turn = d["used_special_this_turn"]
	for f in g.decks:
		var deck = g.decks[f]
		var dd: Dictionary = snap["decks"][f]
		deck.draw_pile.assign(dd["draw_pile"])
		deck.discard_pile.assign(dd["discard_pile"])
	return g
