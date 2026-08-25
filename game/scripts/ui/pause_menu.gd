class_name PauseMenu
extends Control
## Esc 暂停菜单。布局在 scenes/PauseMenu.tscn（编辑器里改），本脚本只做接线。
## 根节点 process_mode = ALWAYS：树暂停后本菜单仍能响应输入（否则关不掉）。
## 暂停 = get_tree().paused：桥的 AI 延迟与骰子动画计时器都以"尊重暂停"方式创建，
## 因此观战/AI 行动会真正停住；人类回合本来就在等点击，盖上遮罩即等效暂停。

## 按下 Esc 且菜单未开时发出；是否真的打开由 main 决定（主菜单界面下不开）
signal open_requested
## 点了"放弃对局，返回主菜单"（发出前已恢复运行）
signal menu_requested


func _ready() -> void:
	%BtnResume.pressed.connect(close)
	%BtnFullscreen.pressed.connect(_toggle_fullscreen)
	%BtnMenu.pressed.connect(_on_menu_pressed)
	%BtnQuit.pressed.connect(func(): get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close()
		else:
			open_requested.emit()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	get_tree().paused = false
	visible = false


func _toggle_fullscreen() -> void:
	var w := DisplayServer.window_get_mode()
	if w == DisplayServer.WINDOW_MODE_FULLSCREEN or w == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_menu_pressed() -> void:
	close()
	menu_requested.emit()
