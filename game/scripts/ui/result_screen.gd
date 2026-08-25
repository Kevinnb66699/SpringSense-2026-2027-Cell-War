class_name ResultScreen
extends Control
## 对局结束后的结算浮层：胜方 + 结束原因 + 关键数据，背后可看到最终棋盘。
## 点「返回主界面」才回主菜单（发 menu_requested，由 main.gd 收尾并释放对局）。
## 布局在 scenes/ResultScreen.tscn（编辑器里改），本脚本只做接线与文案填充。

signal menu_requested


func _ready() -> void:
	%BtnBackMenu.pressed.connect(_on_back_pressed)


func show_result(g) -> void:
	%WinnerLabel.text = "🏆 %s阵营胜利" % CWData.faction_cn(g.winner)
	%WinnerLabel.add_theme_color_override("font_color",
		BoardView.COL_IMMUNE if g.winner == CWData.FACTION_IMMUNE else BoardView.COL_CANCER_P)
	%ReasonLabel.text = g.win_reason
	%StatsLabel.text = "进行至第 %d 世界回合 · 癌组织 %d 块 / 胜利线 %d 块" % \
		[g.round_num, g.board.cancer_tissue_count(), g.win_threshold()]
	visible = true


func _on_back_pressed() -> void:
	visible = false
	menu_requested.emit()
