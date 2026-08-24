class_name CWBoard
extends RefCounted
## 棋盘状态：61 块组织的类型、固化计数、特殊事件、墙壁

var tissue: Dictionary = {}        # Vector2i -> CWData.Tissue
var solid_count: Dictionary = {}   # Vector2i -> int（固化计数，普通癌组织上累计）
var specials: Dictionary = {}      # Vector2i -> {"kind": String, "active": bool}
var walls: Dictionary = {}         # edge_key(String) -> true


func _init() -> void:
	for h in HexLib.all_cells():
		tissue[h] = CWData.Tissue.NORMAL


# ---------------- 组织 ----------------

func tissue_at(h: Vector2i) -> int:
	return tissue.get(h, CWData.Tissue.NORMAL)


func is_cancer_tissue(h: Vector2i) -> bool:
	var t := tissue_at(h)
	return t == CWData.Tissue.CANCER or t == CWData.Tissue.SOLID


func cancer_tissue_count() -> int:
	var n := 0
	for h in tissue:
		if is_cancer_tissue(h):
			n += 1
	return n


func infect(h: Vector2i) -> bool:
	## 正常组织 -> 普通癌组织
	if tissue_at(h) == CWData.Tissue.NORMAL:
		tissue[h] = CWData.Tissue.CANCER
		return true
	return false


func purify(h: Vector2i) -> bool:
	## 普通癌组织 -> 正常组织（固化癌组织无法被净化）
	if tissue_at(h) == CWData.Tissue.CANCER:
		tissue[h] = CWData.Tissue.NORMAL
		solid_count.erase(h)
		return true
	return false


func add_solid_count(h: Vector2i) -> int:
	## 固化一次，计数到 3 变为固化癌组织。返回当前计数（3 表示已固化）
	if tissue_at(h) != CWData.Tissue.CANCER:
		return 0
	var n: int = solid_count.get(h, 0) + 1
	if n >= 3:
		tissue[h] = CWData.Tissue.SOLID
		solid_count.erase(h)
		return 3
	solid_count[h] = n
	return n


func solidify_full(h: Vector2i) -> bool:
	## 直接固化（Nuclear radiation）
	if tissue_at(h) == CWData.Tissue.CANCER:
		tissue[h] = CWData.Tissue.SOLID
		solid_count.erase(h)
		return true
	return false


func unsolidify(h: Vector2i) -> void:
	## 固化癌组织 -> 普通癌组织（癌细胞复活消耗）
	if tissue_at(h) == CWData.Tissue.SOLID:
		tissue[h] = CWData.Tissue.CANCER


func tissues_of_type(t: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in tissue:
		if tissue[h] == t:
			out.append(h)
	return out


func cancer_tissues() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in tissue:
		if is_cancer_tissue(h):
			out.append(h)
	return out


func solid_tissues() -> Array[Vector2i]:
	return tissues_of_type(CWData.Tissue.SOLID)


# ---------------- 特殊事件 ----------------

func place_special(h: Vector2i, kind: String) -> void:
	specials[h] = {"kind": kind, "active": false}


func special_kind(h: Vector2i) -> String:
	if specials.has(h):
		return specials[h]["kind"]
	return ""


func is_pool_active(h: Vector2i) -> bool:
	return specials.has(h) and specials[h]["kind"] == CWData.SP_POOL and specials[h]["active"]


func activate_all_pools() -> void:
	for h in specials:
		if specials[h]["kind"] == CWData.SP_POOL:
			specials[h]["active"] = true


func deactivate_pool(h: Vector2i) -> void:
	if specials.has(h) and specials[h]["kind"] == CWData.SP_POOL:
		specials[h]["active"] = false


func other_vessel(h: Vector2i) -> Vector2i:
	## 另一处血管；找不到返回原位置
	for k in specials:
		if specials[k]["kind"] == CWData.SP_VESSEL and k != h:
			return k
	return h


func move_special(from: Vector2i, to: Vector2i) -> void:
	if specials.has(from) and not specials.has(to):
		specials[to] = specials[from]
		specials.erase(from)


func special_positions(kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in specials:
		if specials[h]["kind"] == kind:
			out.append(h)
	return out


# ---------------- 墙壁 ----------------

func has_wall(a: Vector2i, b: Vector2i) -> bool:
	return walls.has(HexLib.edge_key(a, b))


func add_wall(a: Vector2i, b: Vector2i) -> bool:
	var k := HexLib.edge_key(a, b)
	if walls.has(k):
		return false
	walls[k] = true
	return true


func remove_wall_key(k: String) -> void:
	walls.erase(k)


func clear_walls() -> void:
	walls.clear()


func wall_edges() -> Array[String]:
	var out: Array[String] = []
	for k in walls:
		out.append(k)
	return out


## 与格子 h 相邻的所有墙（六条边中已有墙的）
func walls_adjacent_to(h: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for n in HexLib.neighbors(h):
		if HexLib.in_board(n):
			var k := HexLib.edge_key(h, n)
			if walls.has(k):
				out.append(k)
	return out


## 格子 h 周围还能建墙的边（两端都在棋盘内且尚无墙）
func buildable_edges(h: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for n in HexLib.neighbors(h):
		if HexLib.in_board(n):
			var k := HexLib.edge_key(h, n)
			if not walls.has(k):
				out.append(k)
	return out


## 拆除：给定一面墙，返回与其连通（共享角点）的整片墙
func connected_walls(start_key: String) -> Array[String]:
	if not walls.has(start_key):
		return []
	# 建立 角点 -> 墙列表 索引
	var corner_map: Dictionary = {}
	for k in walls:
		var cells := HexLib.edge_cells(k)
		for ck in HexLib.edge_corners(cells[0], cells[1]):
			if not corner_map.has(ck):
				corner_map[ck] = []
			corner_map[ck].append(k)
	# BFS
	var visited: Dictionary = {start_key: true}
	var queue: Array[String] = [start_key]
	var out: Array[String] = []
	while not queue.is_empty():
		var k: String = queue.pop_back()
		out.append(k)
		var cells := HexLib.edge_cells(k)
		for ck in HexLib.edge_corners(cells[0], cells[1]):
			for other in corner_map.get(ck, []):
				if not visited.has(other):
					visited[other] = true
					queue.append(other)
	return out


# ---------------- 移动 / 距离（考虑墙壁） ----------------

## 一步移动是否可行。ignore_walls：癌细胞 / 中性粒细胞 / 洪水回合
func can_step(from: Vector2i, to: Vector2i, ignore_walls: bool) -> bool:
	if not HexLib.in_board(to):
		return false
	if HexLib.dir_index(to - from) < 0:
		return false
	if ignore_walls:
		return true
	return not has_wall(from, to)


## 考虑墙壁的步数距离（BFS）。返回 -1 表示不可达（限制搜索半径 max_steps）
func walk_distance(from: Vector2i, to: Vector2i, ignore_walls: bool, max_steps: int) -> int:
	if from == to:
		return 0
	if ignore_walls:
		var d := HexLib.distance(from, to)
		return d if d <= max_steps else -1
	var dist: Dictionary = {from: 0}
	var queue: Array[Vector2i] = [from]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		var cd: int = dist[cur]
		if cd >= max_steps:
			continue
		for n in HexLib.neighbors(cur):
			if not HexLib.in_board(n):
				continue
			if has_wall(cur, n):
				continue
			if not dist.has(n):
				dist[n] = cd + 1
				if n == to:
					return cd + 1
				queue.append(n)
	return -1
