extends Control
## 商店卡面预览场景（开发期自测用，不随游戏一起打包）。
##
## 4 张卡摆一排，覆盖 set_state 的五种状态里的四种，
## 用来确认：卡面高度一致、长标题会换行且不撑破、价格与按钮两种颜色都对。
##
## 为什么预览里手搓数据而不是读 data/cards/：
## 那两个目录还是 .gitkeep，字段结构归 P2 且尚未起草。
## 预览只验「控件长相」，喂假数据就够了；等 P2 定了 schema，
## 由商店场景调 setup(...) 喂真数据，本控件不用改。

const TOWERS_PATH := "res://data/towers/towers.json"

## 五种状态各来一张，第五张循环回 buy 以便看清按钮换文案。
const STATES := ["buy", "short", "sold", "owned", "locked"]


func _ready() -> void:
	var row: HBoxContainer = %CardsRow
	var towers := _read_towers()
	var i := 0
	for state in STATES:
		var card: PanelContainer = load("res://scenes/ui/shop/shop_card.tscn").instantiate()
		row.add_child(card)
		# 数据用 towers.json 里的真值，这样标题长度和真实形状一致；
		# 塔不够 5 种就循环取，反正只验外观。
		var tower: Dictionary = towers[i % towers.size()] if not towers.is_empty() else {}
		card.call(
			"setup",
			String(tower.get("name", "塔 %d" % i)),
			_subtitle_of(tower),
			int(tower.get("cost", 100)),
			state != "short",
		)
		card.call("set_card_id", StringName(tower.get("id", "X%d" % i)))
		card.call("set_state", state)
		(card.get_node("%BuyButton") as Button).pressed.connect(
			func() -> void: print("PREVIEW: 点了 %s 的购买（state=%s）" % [String(tower.get("id", "?")), state])
		)
		i += 1


## 把 towers.json 的一条数据压成一行摘要，模拟真实卡面的副标题。
## 范围类型在 JSON 里是 ray/cell/box 这类 schema 值，界面上不能直接露出来，
## 否则玩家看到的是英文键名。这里做一次显示层的中文映射。
const RANGE_NAMES := {
	"ray": "沿朝向射线",
	"cell": "自身一格",
	"box": "3×3 方阵",
}


func _subtitle_of(tower: Dictionary) -> String:
	if tower.is_empty():
		return "—"
	var attack := int(tower.get("attack", 0))
	var interval := float(tower.get("attack_interval", 0.0))
	var range_type := String((tower.get("range", {}) as Dictionary).get("type", "?"))
	var range_text: String = RANGE_NAMES.get(range_type, range_type)
	return "攻 %d / 间隔 %.1fs\n%s" % [attack, interval, range_text]


func _read_towers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(TOWERS_PATH):
		push_error("ShopCardPreview: 找不到 %s" % TOWERS_PATH)
		return out
	var f := FileAccess.open(TOWERS_PATH, FileAccess.READ)
	if f == null:
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var raw: Variant = (data as Dictionary).get("towers")
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in (raw as Array):
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item as Dictionary)
	return out
