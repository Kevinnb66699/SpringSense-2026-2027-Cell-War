extends Control
## 顶层控制器：组装场景节点、给问答桥接线、驱动对局流程。
## 静态布局在 scenes/Main.tscn / SidePanel.tscn / MenuScreen.tscn，主题在 scenes/ui_theme.tres，
## 均可在 Godot 编辑器里可视化修改；本脚本只管逻辑，不再用代码建 UI 节点。
##
## 桥 → 界面的三个入口（UIBridge/HybridBridge/DemoBridge 都走这套，勿改签名）：
##   show_request(req) / clear_request() / play_dice(reason, value, fast)

var game = null      # CWGame
var bridge = null    # UIBridge / HybridBridge / DemoBridge
var pending_req: Dictionary = {}

@onready var board_view: BoardView = %BoardView
@onready var dice_overlay: DiceOverlay = %DiceOverlay
@onready var side_panel: SidePanel = %SidePanel
@onready var menu_screen: MenuScreen = %MenuScreen


func _ready() -> void:
	menu_screen.start_requested.connect(_start)
	side_panel.option_pressed.connect(_on_option_pressed)
	board_view.hex_clicked.connect(_on_board_hex)
	board_view.edge_clicked.connect(_on_board_edge)
	menu_screen.show_menu("")


func _process(_delta: float) -> void:
	if game != null:
		side_panel.refresh(game, bridge)
		board_view.queue_redraw()


# ==================== 开局 / 主循环 ====================

## 从主菜单开一局。mode: "ai"(人机) / "pvp"(热座) / "demo"(双 AI 演示)
func _start(n_players: int, mode: String, human_faction: String) -> void:
	menu_screen.visible = false
	side_panel.visible = true
	side_panel.clear_log()
	pending_req = {}
	if mode == "demo":
		bridge = DemoBridge.new()
		bridge.tree = get_tree()
		bridge.main = self
	elif mode == "ai":
		bridge = HybridBridge.new()
		bridge.main = self
		bridge.tree = get_tree()
		bridge.human_faction = human_faction
	elif mode == "mc" or mode == "mc_watch":
		# 蒙特卡洛搜索桥：免疫由推演搜索操控（mc 模式人执癌症；mc_watch 双方全 AI 观战）
		bridge = MCBridge.new()
		bridge.main = self
		bridge.tree = get_tree()
		bridge.human_faction = human_faction
		bridge.mc_faction = CWData.FACTION_IMMUNE
	else:
		bridge = UIBridge.new()
		bridge.main = self
	bridge.log_added.connect(_on_log)
	if game != null and game.game_over:
		game.dispose()
	game = CWGame.new(bridge, n_players)
	if bridge is MCBridge:
		bridge.game = game
		if human_faction != "":
			side_panel.add_log("蒙特卡洛对战：你执【%s】，免疫阵营由 MC 推演搜索操控。" % CWData.faction_cn(human_faction))
		else:
			side_panel.add_log("蒙特卡洛观战：免疫=MC 推演搜索，癌症=启发式 AI。")
	elif bridge is HybridBridge:
		bridge.game = game
		side_panel.add_log("人机对战：你执【%s】阵营，对方由 AI 操作。" % CWData.faction_cn(human_faction))
	board_view.game = game
	_run_async()


## 异步跑完一整局；若玩家中途重开（game 已被替换）则旧协程静默退出
func _run_async() -> void:
	var g = game
	await g.run_setup()
	if g != game:
		return
	await g.run_game()
	if g != game:
		return
	menu_screen.show_menu(game.win_reason)


# ==================== 问答桥入口 ====================

## 播放掷骰动画（引擎经桥调用；动画播完才返回，保证流程与画面同步）
func play_dice(reason: String, value: int, fast: bool) -> void:
	await dice_overlay.play(reason, value, fast)


## 展示一次决策请求：侧边面板出提示/按钮，棋盘亮可选格/边
func show_request(req: Dictionary) -> void:
	pending_req = req
	side_panel.show_request(req)
	var t: String = req.get("type", "")
	if t == "pick_hex":
		board_view.set_pick_hex(req.get("options", []))
	elif t == "pick_edge":
		board_view.set_pick_edge(req.get("options", []))


func clear_request() -> void:
	pending_req = {}
	side_panel.clear_request()
	board_view.clear_pick()


# ==================== 玩家输入 → 桥 ====================

func _on_option_pressed(value) -> void:
	if bridge != null and bridge.has_method("answer"):
		bridge.answer(value)


func _on_board_hex(h: Vector2i) -> void:
	if pending_req.get("type", "") == "pick_hex" and bridge != null and bridge.has_method("answer"):
		bridge.answer(h)


func _on_board_edge(k: String) -> void:
	if pending_req.get("type", "") == "pick_edge" and bridge != null and bridge.has_method("answer"):
		bridge.answer(k)


func _on_log(text: String) -> void:
	side_panel.add_log(text)
