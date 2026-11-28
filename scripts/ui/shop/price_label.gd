extends Label
## 价格标签（共享控件）：显示一张卡/一个服务的价格，并区分「买得起」「买不起」。
##
## 只做显示，不做任何「买不买得起」的业务判断——判断结果由调用方传进来。
## 为什么：商店的折扣、涨价曲线、升级档位都是 P2 的规则，界面自己再算一遍
## 迟早会和 P2 的结算对不上，到时候玩家看到「能买」点了却报错，比不显示更糟。
##
## 用量：node.set_price(150, true)

## 买得起时的字色（浅绿偏白，深色面板上够亮又不刺眼）。
const COLOR_OK := Color(0.83, 0.90, 0.84, 1.0)
## 买不起时的字色（偏灰红，明确但不惊悚）。
const COLOR_SHORT := Color(0.87, 0.55, 0.52, 1.0)
## 前缀符号。代币是关间货币，用图形符号区分于战斗内的「费用」。
const CURRENCY_MARK := "◈"


## 设置价格。
## affordable 必须由调用方按 P2 的规则算好传进来（通常是 tokens >= price）。
func set_price(price: int, affordable: bool) -> void:
	text = "%s %d" % [CURRENCY_MARK, price]
	add_theme_color_override("font_color", COLOR_OK if affordable else COLOR_SHORT)


## 价格位置留空（例如技能牌已在战斗中、不需要再标价时）。
func clear_price() -> void:
	text = ""
