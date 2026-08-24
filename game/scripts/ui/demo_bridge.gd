class_name DemoBridge
extends CWBridge
## 随机演示桥：所有决策随机进行（带小延迟便于观看）。用于演示模式与冒烟测试。

var tree: SceneTree = null
var rng := RandomNumberGenerator.new()
var delay := 0.1


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value


## 演示模式统一用加速掷骰动画
func show_roll(reason: String, value: int) -> void:
	if main != null:
		await main.play_dice(reason, value, true)


func ask(req: Dictionary):
	if tree != null and delay > 0.0:
		await tree.create_timer(delay).timeout
	var t: String = req.get("type", "")
	var cancel: String = req.get("cancel", "")
	if t == "pick_option":
		var vals: Array = req.get("values", [])
		if vals.is_empty():
			return null
		if cancel != "" and rng.randf() < 0.2:
			return null
		return vals[rng.randi_range(0, vals.size() - 1)]
	elif t == "pick_hex":
		var opts: Array = req.get("options", [])
		if opts.is_empty():
			return null
		if cancel != "" and rng.randf() < 0.25:
			return null
		return opts[rng.randi_range(0, opts.size() - 1)]
	elif t == "pick_edge":
		var opts2: Array = req.get("options", [])
		if opts2.is_empty():
			return null
		if cancel != "" and rng.randf() < 0.3:
			return null
		return opts2[rng.randi_range(0, opts2.size() - 1)]
	return null
