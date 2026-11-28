extends Control
## 塔牌栏独立预览场景（开发期自测用，不随游戏一起打包）。
##
## 战斗场景还跑不起来时，用它验证三件事：
##   1 → 发 fee_changed(1000)  三张卡都买得起
##   2 → 发 fee_changed(80)    A（100）买不起、B（75）买得起、C（150）买不起
##   3 → 打印当前 selected_tower_id，看点击有没有被记下来
##
## 为什么预览里自己发 fee_changed 而不是写 GameState.fee：
## GameState 只有 P2 能写，预览也必须守这条线，否则以后有人照抄这段代码就坏了规矩。

func _ready() -> void:
	var bar := %TowerCardBar
	bar.tower_card_selected.connect(func(id: StringName) -> void:
		print("PREVIEW: 选中 %s" % String(id))
	)
	bar.tower_card_cleared.connect(func() -> void:
		print("PREVIEW: 已取消选择")
	)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			SignalBus.fee_changed.emit(1000)
			print("PREVIEW: 费用 1000")
		KEY_2:
			SignalBus.fee_changed.emit(80)
			print("PREVIEW: 费用 80")
		KEY_3:
			# 用 get() 而不是直接点属性：%TowerCardBar 的静态类型是 Node，
			# 直接写 .selected_tower_id 编译期会报「找不到属性」。
			var id: StringName = %TowerCardBar.get("selected_tower_id")
			print("PREVIEW: selected_tower_id = %s" % String(id))
