class_name DiceOverlay
extends Control
## 掷骰动画浮层：快速翻面 → 减速 → 定格结果。
## play() 为协程，动画播完才返回，调用方 await 以暂停游戏流程。

var reason_text := ""
var face := 1
var rolling := false

var _rng := RandomNumberGenerator.new()
var _panel_sb := StyleBoxFlat.new()
var _dice_sb := StyleBoxFlat.new()
var _dice_sb_final := StyleBoxFlat.new()

## 骰面点数布局（单位偏移）
const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(340, 214)
	_rng.randomize()
	_panel_sb.bg_color = Color(0.04, 0.08, 0.10, 0.93)
	_panel_sb.set_corner_radius_all(14)
	_panel_sb.border_color = Color("#24404c")
	_panel_sb.set_border_width_all(1)
	_dice_sb.bg_color = Color("#f4fbfd")
	_dice_sb.set_corner_radius_all(16)
	_dice_sb_final.bg_color = Color("#f4fbfd")
	_dice_sb_final.set_corner_radius_all(16)
	_dice_sb_final.border_color = Color("#ffd75e")
	_dice_sb_final.set_border_width_all(4)


## 播放一次掷骰动画。fast：AI 掷骰的加速版本
func play(reason: String, value: int, fast: bool) -> void:
	reason_text = reason
	visible = true
	var interval := 0.045
	var steps := 6 if fast else 10
	for i in range(steps):
		var nf := _rng.randi_range(1, 6)
		if nf == face:
			nf = nf % 6 + 1
		face = nf
		rolling = true
		queue_redraw()
		await get_tree().create_timer(interval).timeout
		interval *= 1.16
	face = value
	rolling = false
	queue_redraw()
	await get_tree().create_timer(0.35 if fast else 0.6).timeout
	visible = false


func _draw() -> void:
	_panel_sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	if font != null and reason_text != "":
		draw_string(font, Vector2(0, 32), "🎲 " + reason_text,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color("#ffe9a8"))
	# 骰子（滚动中带随机抖动）
	var ds := 96.0
	var dcenter := Vector2(size.x / 2.0, 52.0 + ds / 2.0)
	var angle := _rng.randf_range(-0.09, 0.09) if rolling else 0.0
	draw_set_transform(dcenter, angle, Vector2.ONE)
	var drect := Rect2(Vector2(-ds / 2.0, -ds / 2.0), Vector2(ds, ds))
	if rolling:
		_dice_sb.draw(get_canvas_item(), drect)
	else:
		_dice_sb_final.draw(get_canvas_item(), drect)
	for off in PIPS[face]:
		draw_circle(off * ds * 0.27, 9.0, Color("#16323e"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 结果
	if not rolling and font != null:
		draw_string(font, Vector2(0, size.y - 16), "掷出 %d" % face,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color("#ffd75e"))
