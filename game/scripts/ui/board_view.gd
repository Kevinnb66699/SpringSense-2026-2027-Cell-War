class_name BoardView
extends Control
## 棋盘绘制与点击交互。视觉风格参照官方比赛地图：
## 深色背景、暗绿组织、红色癌组织、紫色卡池、青色血管、绿色生物质工厂、灰色墙壁工厂。

signal hex_clicked(h: Vector2i)
signal edge_clicked(k: String)

var game = null          # CWGame
var hex_size := 40.0
var origin := Vector2.ZERO

# 选择状态
var pick_mode := ""              # "" / "hex" / "edge"
var hex_options: Array = []      # Vector2i
var edge_options: Array = []     # edge_key
var hover_hex := Vector2i(99, 99)

# ---- 配色（参照官方地图）----
const COL_BG := Color("#0d1418")
const COL_NORMAL := Color("#2e4a41")
const COL_NORMAL_BORDER := Color("#1c2f29")
const COL_CANCER := Color("#b04a5a")
const COL_CANCER_BORDER := Color("#7c3140")
const COL_SOLID := Color("#6e2836")
const COL_SOLID_BORDER := Color("#e0a4ae")
const COL_POOL := Color("#7c4fa0")
const COL_POOL_ACTIVE := Color("#b07fe0")
const COL_VESSEL := Color("#3fa7b8")
const COL_BIO := Color("#3f9d5f")
const COL_WALLFAC := Color("#8a8f98")
const COL_WALL := Color("#d9a441")
const COL_WALL_DARK := Color("#5c451a")
const COL_HL := Color("#ffd75e")
const COL_IMMUNE := Color("#4fc3f7")
const COL_CANCER_P := Color("#ef5350")

var _cells: Array[Vector2i] = []


func _ready() -> void:
	_cells = HexLib.all_cells()
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_pick_hex(options: Array) -> void:
	pick_mode = "hex"
	hex_options = options
	edge_options = []
	queue_redraw()


func set_pick_edge(options: Array) -> void:
	pick_mode = "edge"
	edge_options = options
	hex_options = []
	queue_redraw()


func clear_pick() -> void:
	pick_mode = ""
	hex_options = []
	edge_options = []
	queue_redraw()


func _center_of(h: Vector2i) -> Vector2:
	return origin + HexLib.hex_to_pixel(h, hex_size)


## 一条墙（边）的两个绘制端点
func _edge_segment(k: String) -> Array:
	var cells := HexLib.edge_cells(k)
	var ca := _center_of(cells[0])
	var cb := _center_of(cells[1])
	var mid := (ca + cb) / 2.0
	var perp := (cb - ca).normalized().orthogonal()
	var half := hex_size * 0.5
	return [mid - perp * half, mid + perp * half]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := HexLib.pixel_to_hex(event.position - origin, hex_size)
		if h != hover_hex:
			hover_hex = h
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if pick_mode == "hex":
				var h := HexLib.pixel_to_hex(event.position - origin, hex_size)
				if hex_options.has(h):
					hex_clicked.emit(h)
			elif pick_mode == "edge":
				var best_k := ""
				var best_d := hex_size * 0.55
				for k in edge_options:
					var seg := _edge_segment(k)
					var mid: Vector2 = (seg[0] + seg[1]) / 2.0
					var d: float = event.position.distance_to(mid)
					if d < best_d:
						best_d = d
						best_k = k
				if best_k != "":
					edge_clicked.emit(best_k)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if game == null:
		return
	hex_size = minf(size.x / 16.8, size.y / 15.2)
	origin = size / 2.0
	var font := get_theme_default_font()

	# ---- 组织 ----
	for h in _cells:
		var center := _center_of(h)
		var poly := HexLib.hex_polygon(center, hex_size * 0.93)
		var t: int = game.board.tissue_at(h)
		var fill := COL_NORMAL
		var border := COL_NORMAL_BORDER
		if t == CWData.Tissue.CANCER:
			fill = COL_CANCER
			border = COL_CANCER_BORDER
		elif t == CWData.Tissue.SOLID:
			fill = COL_SOLID
			border = COL_SOLID_BORDER
		draw_colored_polygon(poly, fill)
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, border, 2.0)
		# 固化癌组织：内圈加粗提示
		if t == CWData.Tissue.SOLID:
			var inner := HexLib.hex_polygon(center, hex_size * 0.72)
			var inner_line := inner.duplicate()
			inner_line.append(inner[0])
			draw_polyline(inner_line, COL_SOLID_BORDER, 2.0)
		# 固化计数点
		var sc: int = game.board.solid_count.get(h, 0)
		if sc > 0:
			for i in range(sc):
				var dotpos := center + Vector2((float(i) - float(sc - 1) / 2.0) * hex_size * 0.22, hex_size * 0.55)
				draw_circle(dotpos, hex_size * 0.08, COL_SOLID_BORDER)

	# ---- 特殊事件 ----
	for h in game.board.specials.keys():
		var center := _center_of(h)
		var sp: Dictionary = game.board.specials[h]
		var kind: String = sp["kind"]
		var col := COL_POOL
		var letter := "C"
		var label := "卡池"
		if kind == CWData.SP_VESSEL:
			col = COL_VESSEL
			letter = "V"
			label = "血管"
		elif kind == CWData.SP_BIO:
			col = COL_BIO
			letter = "+"
			label = "生物质工厂"
		elif kind == CWData.SP_WALL:
			col = COL_WALLFAC
			letter = "W"
			label = "墙壁工厂"
		elif sp["active"]:
			col = COL_POOL_ACTIVE
		var poly2 := HexLib.hex_polygon(center, hex_size * 0.93)
		var tint := Color(col.r, col.g, col.b, 0.38)
		draw_colored_polygon(poly2, tint)
		var oline := poly2.duplicate()
		oline.append(poly2[0])
		var border_w := 3.5 if (kind == CWData.SP_POOL and sp["active"]) else 2.0
		var border_c := COL_HL if (kind == CWData.SP_POOL and sp["active"]) else col
		draw_polyline(oline, border_c, border_w)
		if font != null:
			var fs := int(hex_size * 0.52)
			draw_string(font, center + Vector2(-hex_size, hex_size * 0.18), letter,
				HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, fs, Color(1, 1, 1, 0.92))
			var fs2 := maxi(int(hex_size * 0.27), 10)
			draw_string(font, center + Vector2(-hex_size, hex_size * 0.62), label,
				HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, fs2, Color(col.lightened(0.4), 0.95))

	# ---- 墙壁 ----
	for k in game.board.walls.keys():
		var seg := _edge_segment(k)
		draw_line(seg[0], seg[1], COL_WALL_DARK, hex_size * 0.24)
		draw_line(seg[0], seg[1], COL_WALL, hex_size * 0.14)

	# ---- 可选高亮 ----
	if pick_mode == "hex":
		for h in hex_options:
			var center := _center_of(h)
			var poly3 := HexLib.hex_polygon(center, hex_size * 0.86)
			draw_colored_polygon(poly3, Color(COL_HL.r, COL_HL.g, COL_HL.b, 0.16))
			var oline3 := poly3.duplicate()
			oline3.append(poly3[0])
			var w := 3.5 if h == hover_hex else 2.0
			draw_polyline(oline3, COL_HL, w)
	elif pick_mode == "edge":
		for k in edge_options:
			var seg := _edge_segment(k)
			draw_line(seg[0], seg[1], Color(COL_HL.r, COL_HL.g, COL_HL.b, 0.85), hex_size * 0.12)

	# ---- 玩家棋子 ----
	var groups: Dictionary = {}
	for p in game.players:
		if not p.alive:
			continue
		if not groups.has(p.pos):
			groups[p.pos] = []
		groups[p.pos].append(p)
	for pos in groups.keys():
		var plist: Array = groups[pos]
		var center := _center_of(pos)
		var n := plist.size()
		for i in range(n):
			var p = plist[i]
			var offset := Vector2.ZERO
			if n == 2:
				offset = Vector2((float(i) * 2.0 - 1.0) * hex_size * 0.3, 0)
			elif n >= 3:
				var ang := TAU * float(i) / float(n) - PI / 2.0
				offset = Vector2(cos(ang), sin(ang)) * hex_size * 0.33
			var ppos := center + offset
			var rad := hex_size * 0.30 if n == 1 else hex_size * 0.24
			var ring := COL_IMMUNE if p.is_immune() else COL_CANCER_P
			# 当前行动玩家：金色外圈
			var cur = game.cur_player()
			if cur != null and cur == p:
				draw_circle(ppos, rad * 1.45, Color(COL_HL.r, COL_HL.g, COL_HL.b, 0.55))
			draw_circle(ppos, rad * 1.18, ring)
			draw_circle(ppos, rad, Color("#f4fbfd"))
			if font != null:
				var letter2: String = p.pname.substr(p.pname.length() - 1, 1)
				var fs3 := int(rad * 1.2)
				var tcol := Color("#1b6b8a") if p.is_immune() else Color("#a33540")
				draw_string(font, ppos + Vector2(-rad, rad * 0.45), letter2,
					HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, fs3, tcol)
			# 易伤标记
			if p.vulnerable:
				draw_circle(ppos + Vector2(0, -rad * 1.5), rad * 0.28, Color("#ff9d3b"))
			# 眩晕标记
			if p.stunned:
				draw_circle(ppos + Vector2(rad * 1.2, -rad * 1.2), rad * 0.26, Color("#c9b3ff"))
