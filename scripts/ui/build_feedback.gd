extends CanvasLayer
## 建造反馈层：塔位高亮、非法位置、费用不足三种提示。
##
## 分工文档把这一块归 P3，但判定逻辑全部在 P1：
## 「鼠标现在压在哪一格」「这一格能不能建」「这座塔该不该亮」都是 build_system 的事。
## 所以本控件**不做任何判定**，只提供三个入口给 P1 调用：
##
##   show_highlight(rect, state)   画一个格子高亮，state 决定颜色
##   clear_highlight()              去掉高亮（鼠标移出网格时调）
##   flash(text, color)             屏幕中部下方闪一条短提示
##
## 为什么用屏幕坐标 Rect2 而不是世界坐标 Vector2：
## 本节点挂在 CanvasLayer 下，`_draw` 的坐标系就是屏幕像素。
## P1 那边用 `get_viewport().get_canvas_transform() * world_pos` 换算一步即可；
## 若反过来让我去拿相机和视口变换，就等于我依赖了 P1 的场景结构。

## 高亮的三种状态。颜色分别对应：可建、不可建、已有塔（可选中查看）。
const STATE_LEGAL := "legal"
const STATE_ILLEGAL := "illegal"
const STATE_OCCUPIED := "occupied"

## 三种状态的描边色与填充色。填充都很淡，避免盖住航路本身。
const COLORS := {
	STATE_LEGAL: {"line": Color(0.45, 0.85, 0.55, 0.95), "fill": Color(0.45, 0.85, 0.55, 0.18)},
	STATE_ILLEGAL: {"line": Color(0.90, 0.38, 0.34, 0.95), "fill": Color(0.90, 0.38, 0.34, 0.16)},
	STATE_OCCUPIED: {"line": Color(0.55, 0.72, 0.95, 0.95), "fill": Color(0.55, 0.72, 0.95, 0.14)},
}

## 提示条停留时长（秒）。太短看不清，太长会挡住战场。
const FLASH_SECONDS := 1.6

## 提示条默认字色。
const FLASH_COLOR := Color(0.98, 0.86, 0.55, 1.0)

## 当前高亮的矩形，Rect2() 表示没有高亮。
var _highlight_rect := Rect2()
## 当前高亮的状态。
var _highlight_state: String = STATE_LEGAL

## 闪烁计时。用 Tween 而不是 _process 递减：
## 用户简报要求不写 _process 轮询，动画交给 Tween 也更省。
var _flash_tween: Tween = null

@onready var _grid: Control = %GridHighlight
@onready var _flash_label: Label = %FlashLabel


func _ready() -> void:
	# 建造反馈不属于「暂停时该冻结」的东西，但也不该在暂停时继续跑动画。
	# 保持默认的 PAUSABLE：暂停时提示条自然停住，跟整个游戏一致。
	_grid.draw.connect(_on_grid_draw)

	# 建造成功/拆除成功给一条轻提示。这两个信号在冻结版 v1 里就有，可以直接连。
	SignalBus.tower_built.connect(_on_tower_built)
	SignalBus.tower_sold.connect(_on_tower_sold)

	# 费用不足：P2 的 feat/p2-economy 分支新增了 fee_insufficient(required, current)，
	# 但那个分支还没合并到 main。这里用 has_signal 做一次运行期检测：
	# main 上跑不会报错（只是没有这条提示），P2 合并后自动接上，不需要我再改一次。
	# 没有这条信号时，P1 可以自己调 flash_insufficient_fee() 给出同样的提示。
	if SignalBus.has_signal(&"fee_insufficient"):
		SignalBus.fee_insufficient.connect(_on_fee_insufficient)

	_flash_label.modulate = Color(1, 1, 1, 0)


# ---------------------------------------------------------------- 给 P1 的接口


## 画一个格子的高亮。rect 是屏幕坐标，通常是一格 30×30 缩放后的像素大小。
## state 用 STATE_LEGAL / STATE_ILLEGAL / STATE_OCCUPIED。
func show_highlight(rect: Rect2, state: String) -> void:
	if not COLORS.has(state):
		push_error("BuildFeedback.show_highlight: 未知状态 %s" % state)
		return
	# 位置或状态没变就不重绘，避免鼠标微动时每帧重画（高亮层会闪）。
	if rect == _highlight_rect and state == _highlight_state:
		return
	_highlight_rect = rect
	_highlight_state = state
	_grid.queue_redraw()


## 去掉高亮。鼠标移出网格、或取消建造模式时调。
func clear_highlight() -> void:
	if _highlight_rect == Rect2():
		return
	_highlight_rect = Rect2()
	_grid.queue_redraw()


## 屏幕中部下方闪一条短提示。用于「这里不能建」「费用不足」这类即时反馈。
func flash(text: String, color: Color = FLASH_COLOR) -> void:
	if text.is_empty():
		return
	_flash_label.text = text
	_flash_label.add_theme_color_override("font_color", color)

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_label.modulate = Color(1, 1, 1, 0)
	_flash_tween = create_tween()
	# 先快速亮起，停一会儿，再淡出。全程无 _process。
	_flash_tween.tween_property(_flash_label, "modulate:a", 1.0, 0.12)
	_flash_tween.tween_interval(FLASH_SECONDS)
	_flash_tween.tween_property(_flash_label, "modulate:a", 0.0, 0.35)


## 费用不足提示的直连入口。
## 给 P1 用：P1 若在 build_system 里先判了一次「钱不够」，可以直接调这里，
## 不必等 P2 发信号。文案与信号触发的完全一致。
func flash_insufficient_fee(required: int, current: int) -> void:
	flash("费用不足：需要 %d，现有 %d" % [required, current], Color(0.94, 0.62, 0.55, 1.0))


# ---------------------------------------------------------------- 内部


func _on_grid_draw() -> void:
	if _highlight_rect == Rect2():
		return
	var palette: Dictionary = COLORS[_highlight_state]
	_grid.draw_rect(_highlight_rect, palette["fill"])
	# 描边用 draw_rect 的 filled=false 版本，线宽 2 像素，1280 基准下看得清。
	_grid.draw_rect(_highlight_rect, palette["line"], false, 2.0)


func _on_tower_built(_tower_id: int, _tower_type: StringName) -> void:
	# 建造成功给一条极短的确认，避免玩家不确定「到底建上了没有」。
	flash("已建造", Color(0.62, 0.88, 0.65, 1.0))


func _on_tower_sold(_tower_id: int, refund: int) -> void:
	flash("已拆除，返还 %d" % refund, Color(0.75, 0.80, 0.88, 1.0))


func _on_fee_insufficient(required: int, current: int) -> void:
	flash_insufficient_fee(required, current)
