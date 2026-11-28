extends CanvasLayer
## 首关引导层：一步一步告诉玩家这游戏怎么玩。
##
## 为什么做成独立层、不写进 battle.tscn：
## battle.tscn 还不存在，P1 也还没有推分支。把引导写进那个场景等于
## 我现在就要替 P1 决定战斗场景长什么样。做成独立 CanvasLayer 之后，
## P1 只要在自己的战斗场景里实例化一次、开打时调 start()，
## 不需要知道引导内部怎么排布；引导也不需要知道战斗场景怎么搭。
##
## 和 build_feedback 一样，本层**不做任何判定**：
## 该不该显示、显示几步、每步指着哪块界面，全由调用方给。
## 界面上再算一遍「玩家是不是第一次玩」迟早会和流程对不上。

## 引导结束。skipped=true 表示玩家点了「跳过」，不是走完的。
signal finished(skipped: bool)

## 步骤文字相对面板的显示位置，免得每次改文案都动场景。
const PANEL_MAX_WIDTH := 660

## 首关默认的五步。
##
## 内容按**当前真实存在的界面**写，不写还没做出来的东西：
## 顶部 HUD（费用/代币/波次/基地）、左下塔牌栏、ESC 暂停，这三样已经能跑；
## 塔位、建造、拆塔归 P1，这里只描述玩法，不承诺具体按键——
## 因为 P1 的建造操作还没定，写了具体按键就是编接口。
const DEFAULT_STEPS: Array[Dictionary] = [
	{
		"text": "欢迎来到《守望》。你要守住撤离点，让民众一批批撤出去。",
	},
	{
		"text": "屏幕上方是当前费用、代币和波次进度。费用只在战斗里用，代币只在关卡之间的商店里用，两者不能互换。",
	},
	{
		"text": "左下角是塔牌栏。点一张塔牌选中它，再点地图上的塔位就能建造。",
	},
	{
		"text": "费用会随时间自动恢复，每击杀一个敌人也会涨。建错了可以拆塔，返还一部分费用。",
	},
	{
		"text": "撑过全部波次就算守住这一关。按 ESC 随时可以暂停。祝你守得住。",
	},
]

## 已看过引导的标记。
##
## 用 static 而不是存盘：项目现在没有存档系统（启动说明里明确写了
## 「无存档，关掉从头开始」），做一份只为了引导的存档是过度设计。
## 进程内只显示一次；跨进程重开会再看一次，这在试玩阶段反而是好事。
static var _seen: bool = false

@onready var _step_label: Label = %StepLabel
@onready var _text_label: Label = %TextLabel
@onready var _focus_ring: ReferenceRect = %FocusRing
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _skip_button: Button = %SkipButton
@onready var _panel: PanelContainer = %Panel

var _steps: Array[Dictionary] = []
var _index: int = 0


func _ready() -> void:
	_next_button.pressed.connect(_on_next_pressed)
	_prev_button.pressed.connect(_on_prev_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	# 引导默认不显示，等调用方 start()。
	hide()


## 这个玩家这一局还要不要看引导。
##
## 调用方写法：
##   if guide.should_show():
##       guide.start()
static func should_show() -> bool:
	return not _seen


## 标记已看。走完或跳过都会标，避免同一局里每次进战斗都弹一遍。
static func mark_seen() -> void:
	_seen = true


## 开始引导。传空数组就用 DEFAULT_STEPS。
##
## steps 每项支持：
##   text:  String   必填，这一步要说什么
##   focus: Rect2    可选，屏幕像素矩形。给了就在那块区域画一圈高亮，
##                   用来指「说的就是这个控件」。不给就不画。
func start(steps: Array = []) -> void:
	_steps.clear()
	if steps.is_empty():
		for s in DEFAULT_STEPS:
			_steps.append(s)
	else:
		for s in steps:
			if typeof(s) == TYPE_DICTIONARY:
				_steps.append(s as Dictionary)

	if _steps.is_empty():
		# 传了非法数据却什么都不显示，玩家会以为引导坏了。直接报错停住。
		push_error("TutorialOverlay: steps 为空或格式不对，无法开始引导")
		return

	_index = 0
	show()
	_refresh()


## 当前是第几步（从 0 起）。给探针和调试用。
func current_index() -> int:
	return _index


## 一共几步。
func step_count() -> int:
	return _steps.size()


# ---------------------------------------------------------------- 内部


func _refresh() -> void:
	if _index < 0 or _index >= _steps.size():
		# 越界说明调用方逻辑有问题，别静默显示上一步的文字。
		push_error("TutorialOverlay: 步骤下标 %d 越界（共 %d 步）" % [_index, _steps.size()])
		return

	var step: Dictionary = _steps[_index]
	_step_label.text = "第 %d / %d 步" % [_index + 1, _steps.size()]
	_text_label.text = String(step.get("text", ""))
	_text_label.custom_minimum_size.x = PANEL_MAX_WIDTH

	# 第一步不能再往前；最后一步按钮改成「开始」，让玩家知道点完就开打。
	_prev_button.disabled = (_index == 0)
	if _index == _steps.size() - 1:
		_next_button.text = "开始"
	else:
		_next_button.text = "下一步"

	# 焦点圈：有 focus 就摆到那块区域，没有就藏起来。
	# 类型常量是 TYPE_RECT2（不是 TYPE_RECT）：Godot 4 里 Rect2 的类型枚举名带 2。
	# 写错的话是整段脚本 Parse Error，引导层完全加载不出来（踩过一次）。
	var focus: Variant = step.get("focus")
	if typeof(focus) == TYPE_RECT2:
		var rect: Rect2 = focus
		_focus_ring.position = rect.position
		_focus_ring.size = rect.size
		_focus_ring.show()
	else:
		_focus_ring.hide()

	_next_button.grab_focus()


func _on_next_pressed() -> void:
	if _index >= _steps.size() - 1:
		_finish(false)
		return
	_index += 1
	_refresh()


func _on_prev_pressed() -> void:
	if _index <= 0:
		return
	_index -= 1
	_refresh()


func _on_skip_pressed() -> void:
	_finish(true)


func _finish(skipped: bool) -> void:
	mark_seen()
	hide()
	finished.emit(skipped)
