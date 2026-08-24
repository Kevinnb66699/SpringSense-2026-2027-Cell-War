class_name HexLib
## 六边形棋盘数学库（轴向坐标 axial: Vector2i(q, r)，尖顶朝上 pointy-top）。
## 棋盘为半径 4 的正六边形蜂窝，共 61 格。

## 六个方向（尖顶朝上）：东、东北、西北、西、西南、东南
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),   # 东
	Vector2i(1, -1),  # 东北
	Vector2i(0, -1),  # 西北
	Vector2i(-1, 0),  # 西
	Vector2i(-1, 1),  # 西南
	Vector2i(0, 1),   # 东南
]

const DIR_NAMES: Array[String] = ["东", "东北", "西北", "西", "西南", "东南"]

const BOARD_RADIUS := 4


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func neighbor(h: Vector2i, dir_idx: int) -> Vector2i:
	return h + DIRS[dir_idx]


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(h + d)
	return out


static func in_board(h: Vector2i) -> bool:
	return distance(h, Vector2i.ZERO) <= BOARD_RADIUS


## 全部 61 格坐标
static func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		for r in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
			var h := Vector2i(q, r)
			if in_board(h):
				out.append(h)
	return out


## 方向向量 -> 方向序号（-1 表示不是单位方向）
static func dir_index(v: Vector2i) -> int:
	for i in range(6):
		if DIRS[i] == v:
			return i
	return -1


## 从 pos 沿 dir_idx 方向出发直到棋盘边缘的所有格子（不含 pos）
static func ray(pos: Vector2i, dir_idx: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cur := pos + DIRS[dir_idx]
	while in_board(cur):
		out.append(cur)
		cur += DIRS[dir_idx]
	return out


# ---------------- 边（墙壁）与角 ----------------
# 边用其两端格子的规范化字符串表示："q1,r1|q2,r2"（按字典序排序）

static func _coord_key(h: Vector2i) -> String:
	return "%d,%d" % [h.x, h.y]


static func edge_key(a: Vector2i, b: Vector2i) -> String:
	var ka := _coord_key(a)
	var kb := _coord_key(b)
	if ka <= kb:
		return ka + "|" + kb
	return kb + "|" + ka


## 由 edge_key 还原两端格子
static func edge_cells(key: String) -> Array[Vector2i]:
	var parts := key.split("|")
	var out: Array[Vector2i] = []
	for p in parts:
		var xy := p.split(",")
		out.append(Vector2i(int(xy[0]), int(xy[1])))
	return out


## 一条边的两个端点（角）。角用相交的三个格子（含棋盘外虚拟格）规范化表示。
## 相邻格 A、B 之间的边，其两个角分别由 A+dir(d±1) 与 A、B 共同确定。
static func edge_corners(a: Vector2i, b: Vector2i) -> Array[String]:
	var d := dir_index(b - a)
	if d < 0:
		return []
	var c1 := a + DIRS[(d + 1) % 6]
	var c2 := a + DIRS[(d + 5) % 6]
	return [corner_key(a, b, c1), corner_key(a, b, c2)]


static func corner_key(a: Vector2i, b: Vector2i, c: Vector2i) -> String:
	var arr := [_coord_key(a), _coord_key(b), _coord_key(c)]
	arr.sort()
	return "%s;%s;%s" % [arr[0], arr[1], arr[2]]


# ---------------- 像素换算（绘制用，size 为六边形外接圆半径） ----------------

static func hex_to_pixel(h: Vector2i, size: float) -> Vector2:
	var x := size * sqrt(3.0) * (float(h.x) + float(h.y) / 2.0)
	var y := size * 1.5 * float(h.y)
	return Vector2(x, y)


static func pixel_to_hex(p: Vector2, size: float) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / size
	var r := (2.0 / 3.0 * p.y) / size
	return _axial_round(q, r)


static func _axial_round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## 六边形的 6 个顶点（绘制用）
static func hex_polygon(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := PI / 180.0 * (60.0 * float(i) - 30.0)
		pts.append(center + Vector2(size * cos(ang), size * sin(ang)))
	return pts
