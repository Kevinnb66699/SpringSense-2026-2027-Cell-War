class_name PauseMenu
extends Control
## Esc 暂停菜单。布局在 scenes/PauseMenu.tscn（编辑器里改），本脚本只做接线。
##
## 两个容易踩的坑，这里的写法都是刻意的：
## 1. 根节点必须**常显**（隐藏的 CanvasItem 收不到 _input 等输入回调），
##    开/关切换的是内容层 %Body；根与 Body 的 mouse_filter = IGNORE，不挡棋盘点击。
## 2. 监听放在 _input（最先派发）而不是 _unhandled_input：
##    ui_cancel 会被持有焦点的控件在 GUI 阶段当作"释放焦点"吞掉，轮不到 unhandled。
## 根节点 process_mode = ALWAYS（在 _ready 里用具名常量设置，不写在 tscn 里——
## 手写枚举数字踩过坑：4 是 DISABLED 不是 ALWAYS）：树暂停后仍能响应输入，否则关不掉。
## 暂停 = get_tree().paused：桥的 AI 延迟与骰子动画计时器都以"尊重暂停"方式创建
## （tree.create_timer(t, false)），因此观战/AI 行动会真正停住。

## 按下 Esc 且菜单未开时发出；是否真的打开由 main 决定（主菜单界面下不开）
signal open_requested
## 点了"放弃对局，返回主菜单"（发出前已恢复运行）
signal menu_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%BtnResume.pressed.connect(close)
	%BtnFullscreen.pressed.connect(_toggle_fullscreen)
	%BtnMenu.pressed.connect(_on_menu_pressed)
	%BtnQuit.pressed.connect(func(): get_tree().quit())


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if %Body.visible:
		close()
	else:
		open_requested.emit()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return %Body.visible


## in_game=true：对局中的暂停菜单（继续/全屏/放弃/退出）；
## in_game=false：主菜单下的精简菜单（返回/全屏/退出，没有对局可暂停或放弃）
func open(in_game: bool) -> void:
	%Title.text = "已暂停" if in_game else "菜单"
	%BtnResume.text = "继续游戏（Esc）" if in_game else "返回（Esc）"
	%BtnMenu.visible = in_game
	%Hint.visible = in_game
	%Body.visible = true
	get_tree().paused = true


func close() -> void:
	get_tree().paused = false
	%Body.visible = false


func _toggle_fullscreen() -> void:
	var w := DisplayServer.window_get_mode()
	if w == DisplayServer.WINDOW_MODE_FULLSCREEN or w == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_menu_pressed() -> void:
	close()
	menu_requested.emit()
