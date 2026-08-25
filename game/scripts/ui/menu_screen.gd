class_name MenuScreen
extends CenterContainer
## 主菜单。布局与文案在 scenes/MenuScreen.tscn（编辑器里改），本脚本只做按钮接线：
## 点任意开局按钮 → 发 start_requested 信号，由 main.gd 接住开局。

signal start_requested(n_players: int, mode: String, human_faction: String)


func _ready() -> void:
	%BtnAiImmune4.pressed.connect(_pick.bind(4, "ai", CWData.FACTION_IMMUNE))
	%BtnAiCancer4.pressed.connect(_pick.bind(4, "ai", CWData.FACTION_CANCER))
	%BtnAiImmune6.pressed.connect(_pick.bind(6, "ai", CWData.FACTION_IMMUNE))
	%BtnAiCancer6.pressed.connect(_pick.bind(6, "ai", CWData.FACTION_CANCER))
	%BtnPvp4.pressed.connect(_pick.bind(4, "pvp", ""))
	%BtnPvp6.pressed.connect(_pick.bind(6, "pvp", ""))
	%BtnDemo4.pressed.connect(_pick.bind(4, "demo", ""))
	%BtnDemo6.pressed.connect(_pick.bind(6, "demo", ""))


func _pick(n_players: int, mode: String, human_faction: String) -> void:
	start_requested.emit(n_players, mode, human_faction)


## 显示菜单；result_text 非空时在标题下方展示上一局结果
func show_menu(result_text: String) -> void:
	%ResultLabel.text = result_text
	%ResultLabel.visible = result_text != ""
	visible = true
