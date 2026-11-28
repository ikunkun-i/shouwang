extends Control
## 战前情报面板的开发期预览场景（不参与正式流程）。
##
## 放在这里的原因：battle.tscn 还不存在，没有地方能挂这个面板；
## 而面板本身不该等到 P1 交付才能验。预览场景给一个假底座，
## 让面板的五种输入状态都能当场看一遍。
##
## 按 1：正常数据（第 2/5 站、基地 10 点、场上 3 座塔）
## 按 2：空数据（不传任何键，全部退到 GameState / 显示「—」）
## 按 3：缺 enemies.json 之外的降级（只传一半字段）
## 按 4：重复 open（验证敌人列表不会叠加）
## 按 5：关闭面板

const PANEL_SCENE := "res://scenes/ui/panels/pre_battle_panel.tscn"

var _panel: Control
var _open_count := 0

@onready var _hint: Label = %Hint


func _ready() -> void:
	_panel = load(PANEL_SCENE).instantiate()
	add_child(_panel)
	# 面板自己会 hide()，预览场景先开着，省一次按键。
	_open(1)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_open(1)
		KEY_2:
			_open(2)
		KEY_3:
			_open(3)
		KEY_4:
			_open(4)
		KEY_5:
			_panel.hide()
			_hint.text = "面板已关闭（按 1~4 重新打开）"


func _open(mode: int) -> void:
	_open_count += 1
	var brief := {}
	match mode:
		1:
			brief = {
				"station_index": 1,
				"total_stations": 5,
				"base_points": 10,
				"tower_count": 3,
			}
		2:
			brief = {}
		3:
			# 只给站号，其余都缺——验证「缺哪个就说缺哪个」而不是编值。
			brief = {"station_index": 0}
		4:
			# 连开两次，看敌人列表会不会叠成两份。
			brief = {"station_index": 2, "total_stations": 5, "base_points": 12, "tower_count": 0}
			_panel.open(brief)
			_panel.open(brief)
			_hint.text = "模式 4：连续 open 两次（第 %d 次调用），敌人列表应仍只有 3 条" % _open_count
			return
	_panel.open(brief)
	_hint.text = "模式 %d：第 %d 次打开" % [mode, _open_count]
