class_name CWPlayer
extends RefCounted
## 一名玩家（一枚细胞棋子）的状态

var id: int = 0
var pname: String = ""            # 显示名：免疫A / 癌症B ...
var faction: String = ""          # CWData.FACTION_IMMUNE / FACTION_CANCER
var pos: Vector2i = Vector2i.ZERO
var alive: bool = true
var biomass: int = CWData.START_BIOMASS

var evo: String = ""              # 进化能力 id（第 10 回合选择）
var abilities: Array[String] = [] # 持有的【能力】卡 id
var walls_stock: int = 0          # 持有的墙壁数量（癌细胞）
var kills: int = 0                # 击杀数（记忆B/记忆T）

# ---- 状态标记 ----
var stunned: bool = false           # 眩晕：跳过下一个自己的回合
var skip_this_round: bool = false   # 事件复活：本世界回合无法行动
var vulnerable: bool = false        # 易伤标记（树突状细胞施加，受击时消耗）
var dodge_next: bool = false        # Dodge：逃逸下一次攻击
var keratin_next: bool = false      # Keratinization：下一次受击不掉生物质
var infdiv_next: bool = false       # Infinite division：下一次受击不被击退
var next_atk_power: int = 0         # Cytokine 叠加：下一次攻击攻击力+N
var next_atk_range: int = 0         # Complement activation 叠加：下一次攻击范围+N
var next_atk_sure: bool = false     # Precise recognition：下一次攻击一定成功

var last_dir: int = -1              # 最后一次移动方向（0-5，-1 表示本回合未移动）
var moved_this_turn: bool = false   # 本回合是否移动过（休养生息判定）
var used_special_this_turn: bool = false


func is_immune() -> bool:
	return faction == CWData.FACTION_IMMUNE


func is_cancer() -> bool:
	return faction == CWData.FACTION_CANCER


func has_ability(aid: String) -> bool:
	return abilities.has(aid)


## 攻击力（含进化、能力卡、临时增益；世界回合增益由 CWGame 叠加）
func attack_power() -> int:
	var p := CWData.BASE_ATK_POWER
	if evo == "t_cell":
		p += 1
	if evo == "mem_t":
		p += kills
	if has_ability("cell_mediated"):
		p += 1
	p += next_atk_power
	return p


## 攻击范围（含进化、能力卡、临时增益）
func attack_range() -> int:
	var r := CWData.BASE_ATK_RANGE
	if evo == "b_cell":
		r += 1
	if evo == "mem_b":
		r += kills
	if has_ability("humoral"):
		r += 1
	r += next_atk_range
	return r


func ignores_walls() -> bool:
	## 癌细胞不受墙壁影响；中性粒细胞无视墙壁
	return is_cancer() or evo == "neutro"


func gain_biomass(n: int) -> int:
	## 返回实际增加量
	var before := biomass
	biomass = clampi(biomass + n, 0, CWData.MAX_BIOMASS)
	return biomass - before


func lose_biomass(n: int) -> int:
	## 返回实际减少量；不在此处判死（由 CWGame 统一处理）
	var before := biomass
	biomass = maxi(biomass - n, 0)
	return before - biomass


func die() -> void:
	alive = false
	biomass = 0
	vulnerable = false
	dodge_next = false
	keratin_next = false
	infdiv_next = false


func revive(at: Vector2i, bm: int = 1) -> void:
	alive = true
	pos = at
	biomass = bm
	stunned = false


func reset_turn_flags() -> void:
	last_dir = -1
	moved_this_turn = false
	used_special_this_turn = false


func status_tags() -> Array[String]:
	## 面板显示用的状态标签
	var tags: Array[String] = []
	if not alive:
		tags.append("死亡")
	if stunned:
		tags.append("眩晕")
	if skip_this_round:
		tags.append("休整")
	if vulnerable:
		tags.append("易伤")
	if dodge_next:
		tags.append("闪避")
	if keratin_next:
		tags.append("角质")
	if infdiv_next:
		tags.append("无限分裂")
	if next_atk_sure:
		tags.append("必中")
	if next_atk_power > 0:
		tags.append("攻+%d" % next_atk_power)
	if next_atk_range > 0:
		tags.append("程+%d" % next_atk_range)
	return tags
