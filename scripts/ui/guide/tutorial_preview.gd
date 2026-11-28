extends Control
## 首关引导的开发期预览场景（不参与正式流程）。
##
## 按 1：用默认五步开始
## 按 2：自定义三步，其中一步带 focus 高亮
## 按 3：传非法数据（空数组之外格式不对），验证报错而不是白屏
## 按 4：再次 start()，验证 should_show() 已变 false
##
## 背景画了几个假控件，用来让 focus 高亮有地方可指——
## 也顺便看看引导面板压在上面时遮挡关系对不对。

const OVERLAY_SCENE := "res://scenes/ui/guide/tutorial_overlay.tscn"

var _overlay: CanvasLayer

@onready var _hint: Label = %Hint


func _ready() -> void:
	_overlay = load(OVERLAY_SCENE).instantiate()
	add_child(_overlay)
	# 预览场景里每次都显示，否则第二次按 1 就什么都不出来。
	_start_default()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_start_default()
		KEY_2:
			_overlay.call("start", [
				{"text": "这里是顶部 HUD，费用和波次进度都在上面。", "focus": Rect2(0, 0, 1280, 48)},
				{"text": "这里是左下的塔牌栏，点一张选中它。", "focus": Rect2(16, 608, 484, 96)},
				{"text": "这一步没有 focus，高亮圈应该消失。"},
			])
			_hint.text = "模式 2：自定义三步（第 1、2 步有高亮圈，第 3 步没有）"
		KEY_3:
			_overlay.call("start", [{"wrong_key": 1}])
			_hint.text = "模式 3：非法数据，应看到 push_error 且不出面板（" + str(_overlay.call("step_count")) + " 步）"
		KEY_4:
			_hint.text = "模式 4：should_show() = " + str(_overlay.call("should_show")) + "（走过引导后应为 False）"


func _start_default() -> void:
	_overlay.call("start")
	_hint.text = "模式 1：默认五步（按 2 换成自定义三步）"
