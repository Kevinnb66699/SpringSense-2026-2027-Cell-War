class_name CWBridge
extends RefCounted
## 规则引擎与界面之间的「问答桥」。
## 引擎在需要玩家决策时调用 await bridge.ask(req)，由 UI（或自动测试）给出答案。
##
## 请求格式（Dictionary）：
##   通用字段：
##       prompt: String, who: String（决策者显示名）, cancel: String（可空，取消按钮文字）
##       owner_id: int（决策玩家 id；阵营级决策为 -1）
##       owner_faction: String（CWData.FACTION_*；联机/AI 按此路由「该谁答」）
##   type = "pick_option"：从若干选项中选一个
##       labels: Array[String], values: Array
##       -> 返回 values 中的一个；按取消返回 null
##   type = "pick_hex"：在棋盘上选一个格子
##       options: Array[Vector2i] -> 返回 Vector2i；按取消返回 null
##   type = "pick_edge"：在棋盘上选一条边（墙壁）
##       options: Array[String]（edge_key） -> 返回 String；按取消返回 null
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


# ---- 联机预留：答案「线格式」编解码 ----
# 线格式是可直接网络序列化（var_to_str / RPC）的 Variant：
#   pick_option → 选项下标 int；pick_hex → Vector2i；pick_edge → String；取消一律 null。
# pick_option 的答案可能是对象引用（如 CWPlayer），必须转成下标才能上网络；
# 未来 NetBridge 只传线格式，收到后 decode 还原成引擎期待的答案值。
# 注意：同一 values 数组内不要混用 bool 和 int（Variant 相等判断会把 true==1）。

static func encode_answer(req: Dictionary, value) -> Variant:
	if value == null:
		return null
	if req.get("type", "") == "pick_option":
		var values: Array = req.get("values", [])
		return values.find(value)
	return value


static func decode_answer(req: Dictionary, wire) -> Variant:
	if wire == null:
		return null
	if req.get("type", "") == "pick_option":
		var values: Array = req.get("values", [])
		var idx := int(wire)
		if idx >= 0 and idx < values.size():
			return values[idx]
		return null
	return wire


## 展示一次掷骰（引擎在写日志前 await 此方法；UI 播放动画，无头时立即返回）
func show_roll(reason: String, value: int) -> void:
	if main != null:
		await main.play_dice(reason, value, false)


func log_line(text: String) -> void:
	log_added.emit(text)


func notify_changed() -> void:
	state_changed.emit()
