extends Control
## 战前情报面板：开打前看一眼这一关长什么样。
##
## 图纸（plan-v2.0-master.docx）要求显示四样东西：
##   ① 地图布局与航路 ② 基地位置与点数 ③ 已有的防御塔位置 ④ 敌方阵营
##
## 这四样里，只有「敌方阵营」的数据现在存在（data/enemies/enemies.json，P2 维护）。
## ①②③ 都依赖 P1 的关卡场景与 build_system，接口还没有。
## 所以三者的显示位置先占好，数据走 show_brief(brief: Dictionary) 注入——**字段名等 P1 定**。
## 我不替 P1 编字段名，就像商店卡面不替 P2 编 schema 一样。
##
## 为什么是 Control 而不是 CanvasLayer：
## 战前情报是一个需要「打开/关闭」的模态面板，会被实例化进某个场景里当子节点；
## CanvasLayer 只能挂在场景根层级，作为子节点时层级行为不可控。

## 玩家点了「知道了 / 开打」，关闭面板。
signal dismissed()

## 敌方阵营数据文件。三种敌人（A 普通 / B 远程 / C 隐身），归 P2。
const ENEMIES_PATH := "res://data/enemies/enemies.json"

## enemies.json 里的 type 值 → 中文显示名。
## 为什么在界面层映射而不是让 P2 在 JSON 里直接写中文：
## JSON 里的值同时被 P1 当逻辑键用（比较 "stealth" 决定能否阻挡），
## 中文化应该只发生在显示层，否则逻辑一改就全乱。
const ENEMY_TYPE_NAMES := {
	"normal": "普通",
	"ranged": "远程",
	"stealth": "隐身",
}

## 敌人特殊能力的说明。**不按 type 字段判断**——enemies.json 里没有 "type" 这个键，
## 真实存在的是 can_be_targeted / can_be_blocked / facing_block_immune 三个布尔。
## 早先我按 "type" 写，跑起来会永远匹配不到，隐身敌人最关键的那句预警就消失了。
## 现在按布尔组合生成，JSON 改数值也不用动这段代码：
##   不可索敌 + 不可阻挡 = 隐身（图纸 表 4 的 C）
##   可索敌但攻击半径 > 1 格 = 远程（表 4 的 B）
func _traits_of(enemy: Dictionary) -> String:
	var targeted := bool(enemy.get("can_be_targeted", true))
	var blocked := bool(enemy.get("can_be_blocked", true))
	var radius := int(enemy.get("attack_radius", 1))

	if not targeted and not blocked:
		# 这一句是战前情报最重要的信息：玩家不知道就会拿单体塔去守，然后莫名漏怪。
		return "无法被索敌 · 不可阻挡 · 可被范围伤害波及"
	if radius > 1:
		# 这里必须 % radius，否则玩家看到的是一行字面量「%d 格半径」——
		# 这种错截图之前看不出来，因为探针只断言了「不可阻挡」那几条。
		return "远程攻击（%d 格半径）· 优先打射程内的塔" % radius
	if not targeted:
		return "无法被正常索敌"
	if not blocked:
		return "不可被阻挡"
	return ""

@onready var _title_label: Label = %TitleLabel
@onready var _station_label: Label = %StationLabel
@onready var _base_label: Label = %BaseLabel
@onready var _enemy_list: VBoxContainer = %EnemyList
@onready var _layout_note: Label = %LayoutNote
@onready var _dismiss_button: Button = %DismissButton


func _ready() -> void:
	_dismiss_button.pressed.connect(_on_dismiss_pressed)
	# 面板默认藏起来，等调用方 open(...) 才显示。
	hide()


## 打开面板并填充。
##
## brief 支持的键（**都可有可无**，缺哪个就退到 GameState，再缺就显示「—」而不是编一个值）：
##   station_index: int    当前是第几站（从 0 起，与 GameState.station_index 一致）
##   total_stations: int   本轮共几站
##   base_points: int      本关基地初始点数
##   tower_count: int      场上已有的塔数量
##
## 这几个键名都取自 GameState 的字段名，不是我另造的接口。
## P1 若要从自己的关卡数据里取，映射到这几个名字即可。
func open(brief: Dictionary) -> void:
	_fill_station(brief)
	_fill_base(brief)
	_fill_towers(brief)
	_fill_enemies()
	show()
	_dismiss_button.grab_focus()


## 关闭面板。
func close() -> void:
	hide()


# ---------------------------------------------------------------- 填充


func _fill_station(brief: Dictionary) -> void:
	_title_label.text = "战前情报"
	# 关号优先用传进来的，没有就读 GameState（只读，P3 允许读）。
	var index := int(brief.get("station_index", _gs_int(&"station_index", 0)))
	# 站号对外从 1 起算，GameState 从 0 起，只在这一处 +1。
	var total := int(brief.get("total_stations", _gs_int(&"total_stations", 0)))
	if total > 0:
		_station_label.text = "第 %d / %d 站" % [index + 1, total]
	else:
		# 总关数还没有定数时不要编一个，宁可只显示当前站。
		_station_label.text = "第 %d 站" % (index + 1)


func _fill_base(brief: Dictionary) -> void:
	# 战前该看的是「本关基地总点数」，P2 分支上叫 base_total_points；
	# main 上只有 base_points（当前点数）。按顺序找第一个存在的字段，
	# 不能写死其中一个：写死 base_total_points 在 main 上整个面板编译不过（见 _gs_int 注释）。
	var points := int(brief.get("base_points", _gs_int_first([&"base_total_points", &"base_points"], 0)))
	if points > 0:
		_base_label.text = "基地点数 %d" % points
	else:
		# 0 说明关卡还没 begin_station，这不是错误状态，但也不该假装有数值。
		_base_label.text = "基地点数 —"


## 按顺序找第一个在 GameState 上存在的 int 字段并返回它。
## 全都不存在时返回 fallback，只警告一次（不是每个键都警告，否则 main 上会刷两行同样的字）。
func _gs_int_first(keys: Array[StringName], fallback: int) -> int:
	for key in keys:
		var value: Variant = GameState.get(key)
		if value != null:
			return int(value)
	_warn_once(str(keys))
	return fallback


## 已经警告过的字段名。同一个字段只警告一次——
## 每次 open() 都警告会把日志刷满同样的字，真正的报错反而被埋掉。
static var _warned_keys: Dictionary = {}


func _warn_once(key: String) -> void:
	if _warned_keys.has(key):
		return
	_warned_keys[key] = true
	push_warning("PreBattlePanel: GameState 还没有字段 %s（P2 分支未合并？），先按默认值显示" % key)


## 从 GameState 读一个 int 字段，**字段不存在时返回 fallback 而不是报错**。
##
## 为什么不能直接写 GameState.total_stations：
## total_stations 是 P2 的 feat/p2-economy 分支新增的，main 上还没有；
## GameState 是已知类型的 autoload，Godot 4 静态检查会把它判成编译错误，
## 结果是整个面板连加载都做不到，而不是「这一个数字显示不出来」。
## 用 Object.get() 走运行期查找：main 上返回 null → 退到 fallback，
## P2 合并后同一个名字自动读得到，这里不用再改一次。
##
## 查不到时只 push_warning 不 push_error：这是「上游还没到」的正常阶段，
## 不是错误，刷红字会掩盖真正的报错。
func _gs_int(key: StringName, fallback: int) -> int:
	var value: Variant = GameState.get(key)
	if value == null:
		_warn_once(String(key))
		return fallback
	return int(value)


func _fill_towers(brief: Dictionary) -> void:
	var count := int(brief.get("tower_count", -1))
	if count < 0:
		_layout_note.text = "地图布局：本关加载后显示"
	elif count == 0:
		_layout_note.text = "场上没有防御塔，本关从零建造"
	else:
		_layout_note.text = "场上已有 %d 座防御塔" % count


func _fill_enemies() -> void:
	# 先清空，避免重复 open 时叠加。
	for child in _enemy_list.get_children():
		child.queue_free()

	var enemies := _read_enemies()
	if enemies.is_empty():
		var empty := Label.new()
		empty.text = "敌方阵营：未配置"
		_enemy_list.add_child(empty)
		return

	for enemy in enemies:
		_enemy_list.add_child(_make_enemy_row(enemy))


func _make_enemy_row(enemy: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	# 标题用 JSON 里的 name（"普通"/"远程"/"隐身"），P2 已经写成中文，界面不再映射一遍。
	# id 补在括号里，方便和群里的讨论对上号（"C 那个隐身"）。
	var name_label := Label.new()
	name_label.text = "%s（%s）" % [String(enemy.get("name", "?")), String(enemy.get("id", "?"))]
	row.add_child(name_label)

	# 数值一行：血量 / 攻击 / 速度。字段名严格照 enemies.json：
	# 速度是 move_speed（不是 speed），血量是 hp，攻击是 attack。
	var stats := Label.new()
	stats.text = "血 %d · 攻 %d · 速 %.1f 格/秒 · 击杀 +%d" % [
		int(enemy.get("hp", 0)),
		int(enemy.get("attack", 0)),
		float(enemy.get("move_speed", 0.0)),
		int(enemy.get("reward_fee", 0)),
	]
	# 次级信息压暗一档，主次分明。
	stats.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82, 1.0))
	row.add_child(stats)

	# 特殊能力单独一行，这是玩家真正需要预警的东西。
	# 变量名不能叫 trait：Godot 4.7 把 trait 作为保留字了，用在 var 后面直接 Parse Error。
	var traits := _traits_of(enemy)
	if not traits.is_empty():
		var trait_label := Label.new()
		trait_label.text = "⚠ %s" % traits
		trait_label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.45, 1.0))
		trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(trait_label)

	return row


func _on_dismiss_pressed() -> void:
	hide()
	dismissed.emit()


# ---------------------------------------------------------------- 读配置


func _read_enemies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(ENEMIES_PATH):
		push_error("PreBattlePanel: 找不到 %s" % ENEMIES_PATH)
		return out
	var f := FileAccess.open(ENEMIES_PATH, FileAccess.READ)
	if f == null:
		push_error("PreBattlePanel: 打不开 %s，错误码 %d" % [ENEMIES_PATH, FileAccess.get_open_error()])
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()

	if typeof(data) != TYPE_DICTIONARY:
		push_error("PreBattlePanel: %s 不是合法 JSON 对象" % ENEMIES_PATH)
		return out
	var raw: Variant = (data as Dictionary).get("enemies")
	if typeof(raw) != TYPE_ARRAY:
		push_error("PreBattlePanel: %s 缺少 enemies 数组" % ENEMIES_PATH)
		return out

	for item in (raw as Array):
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item as Dictionary)
	return out
