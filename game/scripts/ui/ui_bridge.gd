class_name UIBridge
extends CWBridge
## 真人玩家问答桥：把规则引擎的请求转交给 Main 界面，等待玩家点击后返回答案。

var main = null   # Main 节点

signal answered(value)


func ask(req: Dictionary):
	main.show_request(req)
	var v = await answered
	main.clear_request()
	return v


func answer(v) -> void:
	answered.emit(v)
