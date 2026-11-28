extends Control
## HUD 独立预览场景，只用于开发期自测，不随游戏一起打包。
##
## 战斗场景还没做出来时，用它验证 HUD 的信号通路：
##   1 → 发 fee_changed(100)      2 → 发 tokens_changed(12)
##   3 → 发 wave_started(0)       4 → 发 base_lost(0)
##
## 注意：基地点数由 P2 写入，预览里按 4 只会走一遍刷新逻辑，
## 数值仍是 0，这是预期，不是 bug。

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			SignalBus.fee_changed.emit(100)
		KEY_2:
			SignalBus.tokens_changed.emit(12)
		KEY_3:
			SignalBus.wave_started.emit(0)
		KEY_4:
			SignalBus.base_lost.emit(0)
