extends Node
## 流程推进器（autoload 名：Flow）。
##
## 职责只有一条：决定「此刻该显示哪个界面」，并在界面之间切换。
## 不读费用/代币的具体数值，也不判断胜负——胜负由 P1 发
## SignalBus.station_cleared / station_failed 通知，本脚本收到后换界面。
## 这样胜负规则永远只有一处（P1），界面不会自己算出另一个结果。

## 界面枚举。加一个界面 = 这里加一行 + SCENES 里加一行，两处必须同步。
enum Screen { MAIN_MENU, DECK_SELECT, BATTLE, RESULT, SHOP }

## 界面 → 场景路径。全项目所有跨目录路径集中在这张表里：
## 别人的场景改了文件名，只改这里一行，不用满仓库找。
## 注意：BATTLE / SHOP 指向 P1、P2 的场景，路径待他们确认。
const SCENES := {
	Screen.MAIN_MENU: "res://scenes/boot/main_menu.tscn",
	Screen.DECK_SELECT: "res://scenes/boot/deck_select.tscn",
	Screen.BATTLE: "res://scenes/battle/battle.tscn",
	Screen.RESULT: "res://scenes/ui/panels/result_panel.tscn",
	Screen.SHOP: "res://scenes/shop/shop.tscn",
}

## 当前界面。
var current: Screen = Screen.MAIN_MENU
## 上一关是赢是输。结算面板读它决定按钮是「进入商店」还是「重试」。
var last_result_clear: bool = false
## 本局选中的起始牌组 id，只暂存，不解析内容。
var pending_deck_id: StringName = &""


func _ready() -> void:
	# 只订阅「流程该拐弯了」的三个信号；其余信号归各自的 UI 自己听，
	# 流程层多听一个信号就多一处和界面抢着刷新的机会。
	SignalBus.station_cleared.connect(_on_station_cleared)
	SignalBus.station_failed.connect(_on_station_failed)
	SignalBus.shop_closed.connect(_on_shop_closed)


## 切到指定界面。所有跳转都必须走这里，不要在外面直接 change_scene。
func goto(screen: Screen) -> void:
	var path: String = SCENES[screen]
	# 队友的场景还没提交时不要硬切：change_scene 会留一个空树，
	# 看起来像「流程写错了」，实际只是文件没到。先探一下，缺文件就停在原地并说清缺哪个。
	if not ResourceLoader.exists(path):
		push_error("Flow: 场景缺失 %s（目标 %s），流程停在 %s" % [
			path, Screen.keys()[screen], Screen.keys()[current],
		])
		return
	current = screen
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Flow: 切换到 %s 失败，错误码 %d" % [path, err])


## 主菜单「开始游戏」：先去选牌组，不直接进战斗。
func start_new_run() -> void:
	goto(Screen.DECK_SELECT)


## 选牌组界面确认后调用：记下选择，清零本局，进战斗。
func start_run(deck_id: StringName) -> void:
	pending_deck_id = deck_id
	# 清零整局状态：新的一局必须从 0 费 0 币开始，否则上一局的余额会漏过来。
	# reset_run() 是 P2 提供的公开方法，调用它不算越权写状态。
	GameState.reset_run()
	# TODO(P2)：起始牌组装配入口。P2 提供函数后在这里调用，例如
	#   DeckManager.load_start_deck(deck_id)
	# 现在不写死 P2 的类名，避免接口未冻结时把名字焊死在这行里。
	goto(Screen.BATTLE)


## 失败后「重新开始」：按 plan v2.0「一次失败会结束本轮挑战」，
## 不是重开本关，而是整局清零、回到选牌组重新选一套。
## 为什么 reset 放在这里而不是放在结算面板里：清零是流程的职责，
## 面板只负责显示和转发按钮；谁都能调 reset，迟早有人漏调。
func restart_run() -> void:
	GameState.reset_run()
	goto(Screen.DECK_SELECT)


## 回到主菜单。注意这里不 reset：玩家可能只是回主菜单看一眼，
## 真正开新局时才在 start_run() 里 reset。
func go_to_main_menu() -> void:
	goto(Screen.MAIN_MENU)


func _on_station_cleared(_station_index: int) -> void:
	# 结算数值由 P2 在发信号前算好，这里一个数都不碰；
	# 结算面板自己去读 GameState。
	last_result_clear = true
	goto(Screen.RESULT)


func _on_station_failed(_station_index: int) -> void:
	last_result_clear = false
	goto(Screen.RESULT)


func _on_shop_closed() -> void:
	# 商店关门 = 玩家买完了，进下一关。
	# 注意：station_index 的 +1 不在这里做（GameState 只有 P2 能写）。
	goto(Screen.BATTLE)
