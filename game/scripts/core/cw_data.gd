class_name CWData
## 游戏静态数据：常量、官方地图布局、卡牌表、世界事件表、进化表

# ---------------- 阵营 ----------------
const FACTION_IMMUNE := "immune"
const FACTION_CANCER := "cancer"

# ---------------- 组织类型 ----------------
enum Tissue { NORMAL, CANCER, SOLID } # 正常组织 / 普通癌组织 / 固化癌组织

# ---------------- 特殊事件类型 ----------------
const SP_POOL := "pool"      # 卡池
const SP_VESSEL := "vessel"  # 血管
const SP_BIO := "bio"        # 生物质工厂
const SP_WALL := "wall"      # 墙壁工厂

# ---------------- 数值常量 ----------------
const MAX_BIOMASS := 5
const START_BIOMASS := 5
const TOTAL_ROUNDS := 20
const CANCER_TISSUE_START := 7
const WIN_TISSUE_4P := 21
const WIN_TISSUE_6P := 31
const WALL_FACTORY_BASE := 2   # 墙壁工厂每次获得墙壁数
const BIO_FACTORY_BASE := 1    # 生物质工厂每次回复量
const BASE_ATK_POWER := 1
const BASE_ATK_RANGE := 0

## 官方地图（比赛地图）特殊事件布局，中心对称
const OFFICIAL_LAYOUT := {
	Vector2i(3, -4): SP_POOL,
	Vector2i(-3, -1): SP_POOL,
	Vector2i(3, 1): SP_POOL,
	Vector2i(-3, 4): SP_POOL,
	Vector2i(-4, 0): SP_VESSEL,
	Vector2i(4, 0): SP_VESSEL,
	Vector2i(0, -3): SP_BIO,
	Vector2i(0, 3): SP_WALL,
}

## 官方地图示例的癌组织布局（中心花型：中心格 + 周围一圈）
static func official_cancer_layout() -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i.ZERO]
	out.append_array(HexLib.neighbors(Vector2i.ZERO))
	return out


# ---------------- 进化能力 ----------------
const EVOS_CANCER := [
	{"id": "blood", "name": "血液癌", "text": "移动距离始终+1，在移动过程中遇到血管立即传送。"},
	{"id": "solid_evo", "name": "实体癌", "text": "受到的生物质伤害-1。"},
	{"id": "meta", "name": "转移癌", "text": "失去特殊行动能力。每回合固定移动1步，自动感染你接触到的组织。"},
	{"id": "stem", "name": "癌症干细胞", "text": "死亡之后，下一个自己的回合可消耗其他癌细胞的1点生物质在任意癌组织上以1点生物质复活。"},
]

const EVOS_IMMUNE := [
	{"id": "b_cell", "name": "B细胞", "text": "攻击距离+1"},
	{"id": "t_cell", "name": "T细胞", "text": "攻击力+1"},
	{"id": "mem_b", "name": "记忆B细胞", "text": "每次击杀癌细胞后攻击距离+1"},
	{"id": "mem_t", "name": "记忆T细胞", "text": "每次击杀癌细胞后攻击力+1"},
	{"id": "nk", "name": "自然杀伤细胞", "text": "攻击必然大成功"},
	{"id": "macro", "name": "巨噬细胞", "text": "对癌细胞造成的伤害回复为自己的生物质"},
	{"id": "neutro", "name": "中性粒细胞", "text": "无视墙壁"},
	{"id": "dendritic", "name": "树突状细胞", "text": "失去攻击能力，移动阶段对进入攻击范围的癌细胞添加【易伤】标记。"},
]


# ---------------- 卡牌表 ----------------
# kind: "instant" 即时 / "ability" 能力
const CARDS_IMMUNE := [
	{"id": "diapedesis", "name": "Diapedesis", "kind": "instant", "count": 2, "text": "移动3步"},
	{"id": "glucose", "name": "Glucose", "kind": "instant", "count": 2, "text": "生物质+1"},
	{"id": "maltose", "name": "Maltose", "kind": "instant", "count": 2, "text": "生物质+2"},
	{"id": "balanced_diet", "name": "Balanced diet", "kind": "instant", "count": 2, "text": "所有免疫细胞生物质+1"},
	{"id": "teleporting", "name": "Teleporting", "kind": "instant", "count": 2, "text": "传送到棋盘上任意己方阵营的组织上"},
	{"id": "translocation", "name": "Translocation", "kind": "instant", "count": 2, "text": "和己方阵营的任意队友交换位置"},
	{"id": "good_drug", "name": "Good drug", "kind": "instant", "count": 1, "text": "抽两张卡"},
	{"id": "evolution", "name": "Evolution", "kind": "instant", "count": 1, "text": "若生物质大于1，则抽三张卡，失去1点生物质"},
	{"id": "good_day", "name": "Good day", "kind": "instant", "count": 1, "text": "将棋盘上任一普通癌组织转变为正常组织"},
	{"id": "vegf", "name": "VEGF", "kind": "instant", "count": 1, "text": "将一血管移动1-3步，不能和其他特殊事件重合"},
	{"id": "info_detect", "name": "Information detection", "kind": "instant", "count": 2, "text": "本回合获得1次额外移动机会"},
	{"id": "complement", "name": "Complement activation", "kind": "instant", "count": 2, "text": "下一次的攻击范围+1"},
	{"id": "cytokine", "name": "Cytokine", "kind": "instant", "count": 2, "text": "下一次攻击的攻击力+1"},
	{"id": "precise", "name": "Precise recognition", "kind": "instant", "count": 2, "text": "下一次攻击一定成功"},
	{"id": "chemotaxis", "name": "Chemotaxis", "kind": "ability", "count": 1, "text": "每回合的移动阶段开始前可以移动1步"},
	{"id": "humoral", "name": "Humoral immunity", "kind": "ability", "count": 1, "text": "攻击范围+1"},
	{"id": "cell_mediated", "name": "Cell-mediated immunity", "kind": "ability", "count": 1, "text": "攻击力+1"},
	{"id": "excalibur", "name": "Excalibur", "kind": "instant", "count": 1, "text": "以自己为中心，净化一条直线上的所有普通癌组织"},
]

const CARDS_CANCER := [
	{"id": "invasion", "name": "Invasion", "kind": "instant", "count": 2, "text": "移动3步"},
	{"id": "glucose", "name": "Glucose", "kind": "instant", "count": 2, "text": "生物质+1"},
	{"id": "maltose", "name": "Maltose", "kind": "instant", "count": 2, "text": "生物质+2"},
	{"id": "starvation", "name": "Starvation", "kind": "instant", "count": 2, "text": "所有癌细胞生物质+1"},
	{"id": "teleporting", "name": "Teleporting", "kind": "instant", "count": 2, "text": "传送到棋盘上任意己方阵营的组织上"},
	{"id": "translocation", "name": "Translocation", "kind": "instant", "count": 2, "text": "和己方阵营的任意队友交换位置"},
	{"id": "bad_drug", "name": "Bad drug", "kind": "instant", "count": 1, "text": "抽两张卡"},
	{"id": "mutation", "name": "Mutation", "kind": "instant", "count": 1, "text": "若生物质大于1，则抽三张卡，失去1点生物质"},
	{"id": "bad_day", "name": "Bad day", "kind": "instant", "count": 1, "text": "将棋盘上任一正常组织转变为普通癌组织"},
	{"id": "vegf", "name": "VEGF", "kind": "instant", "count": 1, "text": "将一血管移动1-3步，不能和其他特殊事件重合"},
	{"id": "infiltration", "name": "Infiltration", "kind": "instant", "count": 2, "text": "本回合获得1次额外移动机会"},
	{"id": "inf_division", "name": "Infinite division", "kind": "instant", "count": 2, "text": "下一次受到攻击不会被击退"},
	{"id": "keratin", "name": "Keratinization", "kind": "instant", "count": 2, "text": "免疫下一次攻击受到的生物质伤害"},
	{"id": "dodge", "name": "Dodge", "kind": "instant", "count": 2, "text": "逃逸下一次攻击"},
	{"id": "metastasis", "name": "Metastasis", "kind": "ability", "count": 1, "text": "每回合的移动阶段开始前可以移动1步"},
	{"id": "heavy_worker", "name": "Heavy worker", "kind": "ability", "count": 1, "text": "从墙壁工厂获得的墙壁数量+1"},
	{"id": "doom", "name": "Doom", "kind": "ability", "count": 1, "text": "以自己为中心，感染周围一圈组织，包括当前组织"},
	{"id": "nuclear", "name": "Nuclear radiation", "kind": "instant", "count": 1, "text": "选择任一普通癌组织，固化该普通癌组织"},
]


# ---------------- 世界事件表 ----------------
# side: immune / cancer / common；limited: 一局仅一次
const WORLD_EVENTS := [
	# ---- 免疫事件 ----
	{"id": "miracle", "side": "immune", "name": "医学奇迹", "limited": false,
		"text": "死亡的免疫细胞全部以1点生物质在任意正常组织复活，该世界回合内无法采取行动。"},
	{"id": "precision_med", "side": "immune", "name": "精准医疗", "limited": false,
		"text": "免疫细胞阵营任意选择一名癌细胞，将其生物质降为1。"},
	{"id": "radiotherapy", "side": "immune", "name": "放疗", "limited": false,
		"text": "所有免疫细胞可以分别选择失去1点生物质，净化棋盘上任一普通癌组织。"},
	{"id": "battle_frenzy", "side": "immune", "name": "战斗狂潮", "limited": false,
		"text": "本世界回合触发的攻击必定大成功。"},
	{"id": "flood", "side": "immune", "name": "洪水", "limited": false,
		"text": "本世界回合内所有墙壁无效。"},
	{"id": "great_flood", "side": "immune", "name": "大洪水", "limited": false,
		"text": "棋盘上所有墙壁消失。"},
	{"id": "immune_boost", "side": "immune", "name": "免疫强化", "limited": false,
		"text": "所有免疫细胞抽一张卡。"},
	{"id": "cytokine_storm", "side": "immune", "name": "炎症风暴", "limited": false,
		"text": "本世界回合内所有免疫细胞的攻击力+1。"},
	{"id": "immune_rage", "side": "immune", "name": "免疫暴走", "limited": false,
		"text": "本世界回合内所有生物质大于1的免疫细胞攻击力+1，攻击大成功之后失去1点生物质。"},
	{"id": "immune_patrol", "side": "immune", "name": "免疫巡逻", "limited": false,
		"text": "本世界回合所有免疫细胞行动距离+1。"},
	# ---- 癌症事件 ----
	{"id": "revive_cancer", "side": "cancer", "name": "死灰复燃", "limited": false,
		"text": "死亡的癌细胞全部以1点生物质在任意癌组织复活，该世界回合内无法采取行动。"},
	{"id": "malpractice", "side": "cancer", "name": "医疗事故", "limited": false,
		"text": "癌细胞阵营任意选择一名免疫细胞，将其生物质降为1。"},
	{"id": "deterioration", "side": "cancer", "name": "恶化", "limited": false,
		"text": "所有癌细胞可以选择当前组织或周围的组织其中一枚进行感染。"},
	{"id": "hell_factory", "side": "cancer", "name": "地狱制造", "limited": true,
		"text": "在墙壁工厂获得的墙壁数量+1【限定】。"},
	{"id": "fibrosis", "side": "cancer", "name": "纤维化", "limited": false,
		"text": "所有癌细胞可以选择当前组织的一面生成墙壁。"},
	{"id": "metastasis_ev", "side": "cancer", "name": "转移", "limited": false,
		"text": "所有癌细胞可以分别选择失去1点生物质，感染棋盘上任一正常组织。"},
	{"id": "cancer_boost", "side": "cancer", "name": "癌症强化", "limited": false,
		"text": "所有癌细胞抽一张卡。"},
	{"id": "immune_escape", "side": "cancer", "name": "免疫逃逸", "limited": false,
		"text": "本世界回合癌细胞不会受到攻击。"},
	{"id": "cancer_infiltrate", "side": "cancer", "name": "癌症渗透", "limited": false,
		"text": "本世界回合所有癌细胞行动距离+1。"},
	# ---- 共同事件 ----
	{"id": "second_chance", "side": "common", "name": "二次机会", "limited": false,
		"text": "死亡的所有细胞全部以1点生物质在任意己方阵营的组织复活，该回合内无法采取行动。"},
	{"id": "sweet_rain", "side": "common", "name": "天降甘霖", "limited": false,
		"text": "所有细胞获得1点生物质。"},
	{"id": "chemotherapy", "side": "common", "name": "化疗", "limited": false,
		"text": "所有生物质大于1的细胞失去1点生物质。"},
	{"id": "life_or_death", "side": "common", "name": "生死关头", "limited": false,
		"text": "所有细胞的生物质降为1。"},
	{"id": "heaven_factory", "side": "common", "name": "天堂制造", "limited": true,
		"text": "生物质工厂的回复量+1【限定】。"},
	{"id": "raid", "side": "common", "name": "突袭", "limited": false,
		"text": "所有细胞按照行动顺序依次移动3步。"},
	{"id": "weakening", "side": "common", "name": "衰弱", "limited": false,
		"text": "双方阵营分别选择对方阵营其中一名角色具有的其中一张能力牌消除。"},
	{"id": "recuperate", "side": "common", "name": "休养生息", "limited": false,
		"text": "本回合可以选择放弃移动和特殊行动，分别可以回复1点生物质。"},
]


static func card_def(faction: String, card_id: String) -> Dictionary:
	var table = CARDS_IMMUNE if faction == FACTION_IMMUNE else CARDS_CANCER
	for c in table:
		if c["id"] == card_id:
			return c
	return {}


static func evo_def(faction: String, evo_id: String) -> Dictionary:
	var table = EVOS_IMMUNE if faction == FACTION_IMMUNE else EVOS_CANCER
	for e in table:
		if e["id"] == evo_id:
			return e
	return {}


static func event_def(ev_id: String) -> Dictionary:
	for e in WORLD_EVENTS:
		if e["id"] == ev_id:
			return e
	return {}


static func faction_cn(faction: String) -> String:
	return "免疫细胞" if faction == FACTION_IMMUNE else "癌细胞"
