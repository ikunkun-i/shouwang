extends PanelContainer
## 商店卡面（共享控件）：塔牌与技能牌共用一张卡。
##
## 为什么把塔牌和技能牌做成同一个控件：两者在商店里长得一样（标题 + 说明 + 价格 + 购买），
## 差别只在数据来源。做成两个控件会有两份布局要同步改，8 天里必然走形。
##
## 重要：这个控件**不读任何 JSON**。
## data/cards/ 和 data/shop/ 现在还是 .gitkeep，字段结构归 P2，尚未起草。
## 先按 P2 的字段名写加载逻辑，等于我替 P2 定了 schema，后面一定要返工。
## 所以这里只提供 setup(...) 这个「喂数据」的入口，字段名由调用方（P2 的商店场景）决定。
##
## 用量：
##   card.setup("直线输出", "攻 100 / 间隔 1s / 射程 1 格", 100, true)
##   card.set_tower_id(&"A")
##   card.buy_pressed.connect(_on_buy)

## 玩家点了购买。tower_id 或 card_id 由调用方通过 set_tower_id/set_card_id 先塞进来。
signal buy_pressed(id: StringName)

## 这张卡当前的 id。塔牌用 towers.json 的 id（A/B/C），技能牌用 cards 的 id。
var _id: StringName = &""

## 卡面标题（塔名或技能名）。
@onready var _title_label: Label = %TitleLabel
## 卡面副标题（数值摘要，一两行）。
@onready var _subtitle_label: Label = %SubtitleLabel
## 价格标签，复用共享控件 PriceLabel。
@onready var _price_label: Label = %PriceLabel
## 购买按钮。
@onready var _buy_button: Button = %BuyButton


func _ready() -> void:
	_buy_button.pressed.connect(_on_buy_button_pressed)


## 一次性填好卡面。四个参数都是调用方算好的「显示值」。
## price 传 -1 表示这张卡不标价（例如已在战斗中生效的技能牌）。
func setup(title: String, subtitle: String, price: int, affordable: bool) -> void:
	_title_label.text = title
	_subtitle_label.text = subtitle
	if price < 0:
		_price_label.clear_price()
	else:
		_price_label.set_price(price, affordable)


## 设置这张卡的 id，点击购买时原样发回来。
func set_card_id(id: StringName) -> void:
	_id = id


## 切换卡面状态。只改外观，不改业务数据。
## state 取值与含义：
##   "buy"      可购买（默认）
##   "short"    代币不足：按钮仍可点，点击后由调用方给提示
##   "sold"     已售出：按钮禁用
##   "owned"    已拥有：按钮禁用
##   "locked"   未解锁（例如还没到第二大关）：按钮禁用
func set_state(state: String) -> void:
	match state:
		"buy":
			_buy_button.disabled = false
			_buy_button.text = "购买"
			modulate = Color(1, 1, 1, 1)
		"short":
			# 不禁用：点了要能弹「代币不足」，禁用则连点击事件都没有，
			# 玩家只会觉得点了没反应。
			_buy_button.disabled = false
			_buy_button.text = "代币不足"
			modulate = Color(0.72, 0.72, 0.76, 1)
		"sold":
			_buy_button.disabled = true
			_buy_button.text = "已售出"
			modulate = Color(0.55, 0.55, 0.58, 1)
		"owned":
			_buy_button.disabled = true
			_buy_button.text = "已拥有"
			modulate = Color(0.60, 0.66, 0.60, 1)
		"locked":
			_buy_button.disabled = true
			_buy_button.text = "未解锁"
			modulate = Color(0.50, 0.50, 0.54, 1)
		_:
			push_error("ShopCard.set_state: 未知状态 %s，保持原样" % state)


## 让卡面拿焦点，手柄/键盘操作时用。
func grab_card_focus() -> void:
	_buy_button.grab_focus()


func _on_buy_button_pressed() -> void:
	buy_pressed.emit(_id)
