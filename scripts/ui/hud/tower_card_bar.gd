extends Control
## 战斗内左下角的塔牌栏：显示三种塔，点一张进入「准备建造」状态。
##
## 三条设计约束：
## 1. 塔的数据从 data/towers/towers.json 读，不写死在脚本里。
##    数值归 P2，写死一份就等于在两个地方各有一份造价，改一处必然对不上。
## 2. 能不能买得起，用 GameState.fee 判断；费用变了靠 SignalBus.fee_changed 刷新，
##    不在 _process 里轮询。
## 3. 「选中了哪种塔」这件事必须传出去，但 SignalBus 的 10 个信号里没有它，
##    且已冻结。所以这里发的是**本控件自己的信号**（只在本 UI 内部用），
##    由 P1 的 build_system 主动连接或读 selected_tower_id。
##    这不是新增跨域接口，但仍需要 P1 接一下——已列入交付说明的「需要配合的接口」。

## 玩家选中了一张塔牌。tower_id 是 towers.json 里的 id（"A"/"B"/"C"）。
## 只在本控件与 P1 的建造系统之间用，**没有**经过 SignalBus。
signal tower_card_selected(tower_id: StringName)

## 玩家取消了选择（再点一次同一张、或右键）。
signal tower_card_cleared()

const TOWERS_PATH := "res://data/towers/towers.json"

## 单张卡片的尺寸。1280 宽的基准下三张并排不挡中间战场。
const CARD_SIZE := Vector2(148, 92)

## 当前选中的塔 id，空表示没选。P1 可直接读这个变量。
var selected_tower_id: StringName = &""

## 从 JSON 读到的塔定义，按文件顺序。
var _towers: Array[Dictionary] = []
## tower_id -> Button，刷新买得起与否时要逐个改外观。
var _cards: Dictionary = {}

@onready var _cards_row: HBoxContainer = %CardsRow


func _ready() -> void:
	_towers = _read_towers()

	if _towers.is_empty():
		# 读不到数据时不要留一个空栏假装正常：这多半是 JSON 被改坏了。
		push_error("TowerCardBar: %s 没读到任何塔，塔牌栏为空" % TOWERS_PATH)
		return

	for tower in _towers:
		var card := _make_card(tower)
		_cards_row.add_child(card)
		_cards[StringName(tower.get("id", ""))] = card

	# 余额变化就重刷「买得起/买不起」，因为费用是战斗内唯一会动的资源。
	SignalBus.fee_changed.connect(_on_fee_changed)
	_refresh_affordability(GameState.fee)


# ---------------------------------------------------------------- 卡片


func _make_card(tower: Dictionary) -> Button:
	var id := StringName(tower.get("id", ""))
	var display_name := String(tower.get("name", "?"))
	var cost := int(tower.get("cost", 0))

	var card := Button.new()
	# 节点名用 PascalCase + id，方便按标识检索：TowerCardA / TowerCardB / TowerCardC。
	card.name = "TowerCard%s" % String(id)
	card.custom_minimum_size = CARD_SIZE
	# 卡片是可点的，保持默认 mouse_filter（STOP）；不改成 Ignore。
	card.toggle_mode = false
	card.text = "%s\n%s\n%d" % [String(id), display_name, cost]
	card.tooltip_text = "%s（造价 %d）" % [display_name, cost]
	# 一个按钮里三行字，对齐和字号只能靠 theme_override。
	card.alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_theme_font_size_override("font_size", 18)
	card.pressed.connect(_on_card_pressed.bind(id))
	return card


func _on_card_pressed(tower_id: StringName) -> void:
	# 再点一次同一张 = 取消。不用 ESC：ESC 已经被暂停面板占了，
	# 两个地方同时抢 ui_cancel，结果取决于谁先收到，不可预测。
	if selected_tower_id == tower_id:
		selected_tower_id = &""
		_refresh_selection_visual()
		tower_card_cleared.emit()
		return

	selected_tower_id = tower_id
	_refresh_selection_visual()
	tower_card_selected.emit(tower_id)


# ---------------------------------------------------------------- 刷新


func _refresh_selection_visual() -> void:
	for id in _cards:
		var card: Button = _cards[id]
		# 选中的那张加一圈亮边；没选中的保持默认外观。
		card.modulate = Color(1, 1, 1, 1) if id == selected_tower_id else Color(0.82, 0.84, 0.87, 1)


func _refresh_affordability(fee: int) -> void:
	for tower in _towers:
		var id := StringName(tower.get("id", ""))
		if not _cards.has(id):
			continue
		var card: Button = _cards[id]
		var cost := int(tower.get("cost", 0))
		var affordable := fee >= cost
		# 买不起时压暗，但**不禁用按钮**：点了要能给出「费用不足」的反馈，
		# 禁用按钮则连点击事件都没有，玩家只会觉得点了没反应。
		card.self_modulate = Color(1, 1, 1, 1) if affordable else Color(0.55, 0.55, 0.6, 1)
		# 费用不够时把差价写进 tooltip，玩家不用自己减。
		if affordable:
			card.tooltip_text = "%s（造价 %d）" % [String(tower.get("name", "?")), cost]
		else:
			card.tooltip_text = "%s（造价 %d，还差 %d）" % [
				String(tower.get("name", "?")), cost, cost - fee,
			]


func _on_fee_changed(value: int) -> void:
	_refresh_affordability(value)


# ---------------------------------------------------------------- 读配置


func _read_towers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(TOWERS_PATH):
		return result
	var f := FileAccess.open(TOWERS_PATH, FileAccess.READ)
	if f == null:
		push_error("TowerCardBar: 打不开 %s，错误码 %d" % [TOWERS_PATH, FileAccess.get_open_error()])
		return result
	var text := f.get_as_text()
	f.close()

	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("TowerCardBar: %s 不是合法 JSON 对象" % TOWERS_PATH)
		return result
	var raw: Variant = (data as Dictionary).get("towers")
	if typeof(raw) != TYPE_ARRAY:
		push_error("TowerCardBar: %s 缺少 towers 数组" % TOWERS_PATH)
		return result

	for item in (raw as Array):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		# id / name / cost 三个字段缺一个就没法显示，直接跳过并报出来，
		# 不要让界面出现一个写着 "?" 的空卡。
		if not (d.has("id") and d.has("name") and d.has("cost")):
			push_error("TowerCardBar: towers.json 里有一条缺 id/name/cost，已跳过：%s" % str(d))
			continue
		result.append(d)
	return result
