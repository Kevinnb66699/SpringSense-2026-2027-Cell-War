class_name CWBridge
extends RefCounted
## 规则引擎与界面之间的「问答桥」。
## 引擎在需要玩家决策时调用 await bridge.ask(req)，由 UI（或自动测试）给出答案。
##
## 请求格式（Dictionary）：
##   type = "pick_option"：从若干选项中选一个
##       prompt: String, who: String（决策者名）,
##       labels: Array[String], values: Array, cancel: String（可空，取消按钮文字）
##       -> 返回 values 中的一个；按取消返回 null
##   type = "pick_hex"：在棋盘上选一个格子
##       prompt, who, options: Array[Vector2i], cancel
##       -> 返回 Vector2i；按取消返回 null
##   type = "pick_edge"：在棋盘上选一条边（墙壁）
##       prompt, who, options: Array[String]（edge_key）, cancel
##       -> 返回 String；按取消返回 null
##
## 基类实现为「自动应答」（总是选第一个选项），用于无头测试；
## UI 桥（UIBridge）重写 ask() 以等待玩家输入。

signal state_changed
signal log_added(text: String)

## UI 主控制器（Main 节点）。无头运行时为 null，掷骰展示等 UI 反馈自动跳过。
var main = null


func ask(req: Dictionary):
	var t: String = req.get("type", "")
	if t == "pick_option":
		var values: Array = req.get("values", [])
		if values.is_empty():
			return null
		return values[0]
	elif t == "pick_hex":
		var options: Array = req.get("options", [])
		if options.is_empty():
			return null
		return options[0]
	elif t == "pick_edge":
		var options: Array = req.get("options", [])
		if options.is_empty():
			return null
		return options[0]
	return null


## 展示一次掷骰（引擎在写日志前 await 此方法；UI 播放动画，无头时立即返回）
func show_roll(reason: String, value: int) -> void:
	if main != null:
		await main.play_dice(reason, value, false)


func log_line(text: String) -> void:
	log_added.emit(text)


func notify_changed() -> void:
	state_changed.emit()
