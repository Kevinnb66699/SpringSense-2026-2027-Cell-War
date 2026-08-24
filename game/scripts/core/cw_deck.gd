class_name CWDeck
extends RefCounted
## 一个阵营的卡池：抽牌堆 + 弃牌堆，抽空后洗回

var faction: String = ""
var draw_pile: Array[String] = []   # card id 列表
var discard_pile: Array[String] = []
var _rng: RandomNumberGenerator


func _init(p_faction: String, rng: RandomNumberGenerator) -> void:
	faction = p_faction
	_rng = rng
	var table = CWData.CARDS_IMMUNE if faction == CWData.FACTION_IMMUNE else CWData.CARDS_CANCER
	for c in table:
		for i in range(c["count"]):
			draw_pile.append(c["id"])
	shuffle()


func shuffle() -> void:
	# 用游戏统一的 RNG 洗牌（可复现）
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: String = draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp


## 抽一张。卡池抽空时把弃牌堆洗回。两堆皆空（能力卡全部在场）返回 ""
func draw() -> String:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			return ""
		draw_pile = discard_pile.duplicate()
		discard_pile.clear()
		shuffle()
	return draw_pile.pop_back()


func discard(card_id: String) -> void:
	discard_pile.append(card_id)
