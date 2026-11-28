extends Node
## 牌库与技能牌执行入口（autoload 名：Cards）。
##
## 负责：读 data/cards/cards.json 与 data/start_decks/index.json、装配起始牌组、
##       判定技能牌目标是否合法、把"打出技能牌"翻译成给 P1 的请求信号。
## 不负责：技能效果本身。改塔的攻击力/范围/间隔、地块减速、毒气扣血都在 P1 那边执行，
##         因为那些是塔与敌人的内部状态。这里只负责"该不该打、打了发什么信号"。
##
## 对外接口：
##   Cards.apply_start_deck(deck_id)                              Settlement 调用
##   Cards.request_tower_skill(card_id, tower_id, tower_type)      P3 拖牌到塔上时调用
##   Cards.request_cell_skill(card_id, cell)                       P3 拖牌到格子时调用
##   Cards.get_card(card_id) / get_price(card_id)                  给 P3 画手牌用

const CARDS_PATH := "res://data/cards/cards.json"
const DECKS_PATH := "res://data/start_decks/index.json"
const TOWERS_PATH := "res://data/towers/towers.json"

## card_id -> 卡牌配置字典
var _cards: Dictionary = {}
## 按 kind 分组的 card_id 列表
var _ids_by_kind: Dictionary = {}


func _ready() -> void:
	_load_cards()
	SignalBus.skill_request_rejected.connect(_on_skill_rejected)


func _load_cards() -> void:
	var config := JsonConfig.load_dict(CARDS_PATH)
	for kind_key in ["tower_cards", "skill_cards"]:
		var list: Array = JsonConfig.get_array(config, kind_key)
		for entry in list:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var card: Dictionary = entry
			var card_id := StringName(String(card.get("id", "")))
			if card_id == &"":
				push_error("Cards: %s 里有一张牌没有 id，已跳过" % kind_key)
				continue
			_cards[card_id] = card
			var kind := String(card.get("kind", ""))
			if not _ids_by_kind.has(kind):
				_ids_by_kind[kind] = []
			_ids_by_kind[kind].append(card_id)


# ============================================================
# 查询接口（P3 画手牌、Shop 生成陈列都用这些）
# ============================================================

func get_card(card_id: StringName) -> Dictionary:
	return _cards.get(card_id, {})


func has_card_config(card_id: StringName) -> bool:
	return _cards.has(card_id)


## 卡牌基础售价（不含商店涨价），涨价在 Shop 里叠加。
func get_price(card_id: StringName) -> int:
	return int(get_card(card_id).get("price", 0))


## 某一类牌的全部 id。kind 取 "tower" / "tower_skill" / "cell_skill"。
func get_ids_of_kind(kind: String) -> Array:
	var list: Array = _ids_by_kind.get(kind, [])
	return list.duplicate()


func get_all_skill_card_ids() -> Array:
	var result: Array = []
	result.append_array(get_ids_of_kind("tower_skill"))
	result.append_array(get_ids_of_kind("cell_skill"))
	return result


## 卡牌显示名，取不到时回落到 id，避免界面出现空字符串。
func get_display_name(card_id: StringName) -> String:
	var display := String(get_card(card_id).get("name", ""))
	return display if not display.is_empty() else String(card_id)


# ============================================================
# 起始牌组
# ============================================================

## 装配起始牌组。deck_id 传 &"" 表示玩家跳过了选择，按 skip_option 只给基础塔。
## 调用时机：Settlement.start_run() 里，紧跟在 GameState.reset_run() 之后。
func apply_start_deck(deck_id: StringName) -> void:
	var config := JsonConfig.load_dict(DECKS_PATH)
	var card_ids: Array = []
	var tower_types: Array = []

	if deck_id == &"":
		var skip := JsonConfig.get_dict(config, "skip_option")
		if skip.is_empty() or not JsonConfig.get_bool(skip, "enabled", true):
			push_error("Cards: 玩家跳过了牌组选择，但 start_decks/index.json 没有可用的 skip_option")
			return
		card_ids = skip.get("cards", [])
		tower_types = skip.get("unlocked_towers", [])
	else:
		var found := false
		for entry in JsonConfig.get_array(config, "decks"):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var deck: Dictionary = entry
			if StringName(String(deck.get("id", ""))) != deck_id:
				continue
			found = true
			card_ids = deck.get("cards", [])
			break
		if not found:
			push_error("Cards: 找不到起始牌组 %s，按跳过处理" % deck_id)
			apply_start_deck(&"")
			return

	# 先解锁塔型再发牌：塔牌本身是"解锁凭证"，不是一次性道具。
	for tower_type in tower_types:
		GameState.unlock_tower(StringName(String(tower_type)))
	for raw_id in card_ids:
		grant_card(StringName(String(raw_id)))


## 发一张牌到玩家手里。塔牌同时解锁对应塔型。
## Shop 买牌也走这里，保证"发牌 + 解锁"永远成对发生。
func grant_card(card_id: StringName) -> void:
	var card := get_card(card_id)
	if card.is_empty():
		push_error("Cards: 牌组里有一张不存在的牌 %s" % card_id)
		return
	GameState.add_card(card_id)
	if String(card.get("kind", "")) == "tower":
		GameState.unlock_tower(StringName(String(card.get("tower_type", ""))))


# ============================================================
# 打出技能牌
# ============================================================

## 塔技能牌：拖到具体一座塔上。
## tower_type 由 P3 从被拖中的塔节点上读出，用来做"攻击力 ≥ 1"的预检——
## B 阻挡塔攻击力为 0，按策划案必须原路退回、不生效。
## 返回 true 表示请求已发出；P1 若判定非法会回 skill_request_rejected，牌会自动退回。
func request_tower_skill(card_id: StringName, tower_id: int, tower_type: StringName) -> bool:
	var card := get_card(card_id)
	if card.is_empty():
		push_warning("Cards: 未知卡牌 %s" % card_id)
		return false
	if String(card.get("kind", "")) != "tower_skill":
		push_warning("Cards: %s 不是塔技能牌" % card_id)
		return false
	if not GameState.has_card(card_id):
		push_warning("Cards: 手牌里没有 %s" % card_id)
		return false

	var min_attack := int(card.get("requires_attack_min", 0))
	if min_attack > 0 and _tower_attack(tower_type) < min_attack:
		var reason := StringName(String(card.get("reject_reason", "attack_zero")))
		SignalBus.skill_request_rejected.emit(card_id, reason)
		return false

	_consume_card(card_id)
	SignalBus.tower_skill_requested.emit(card_id, tower_id)
	return true


## 地块技能牌：拖到格子上。格子是否可放（例如冰冻要求格内无塔）由 P1 校验。
func request_cell_skill(card_id: StringName, cell: Vector2i) -> bool:
	var card := get_card(card_id)
	if card.is_empty():
		push_warning("Cards: 未知卡牌 %s" % card_id)
		return false
	if String(card.get("kind", "")) != "cell_skill":
		push_warning("Cards: %s 不是地块技能牌" % card_id)
		return false
	if not GameState.has_card(card_id):
		push_warning("Cards: 手牌里没有 %s" % card_id)
		return false

	_consume_card(card_id)
	SignalBus.cell_skill_requested.emit(card_id, cell)
	return true


func _consume_card(card_id: StringName) -> void:
	if GameState.remove_card(card_id):
		SignalBus.card_removed.emit(card_id, 0)


## P1 判定目标非法：卡片退回手牌。
## 因为 Godot 的信号是同步派发的，这次退回发生在 request_* 返回之前，不会出现"牌没了但也打不出去"。
## 注意：P2 自己的预检也会发同一条信号，那时牌根本没被消耗，
## 所以必须先用 has_card 判断，否则会一牌变两张。
func _on_skill_rejected(card_id: StringName, reason: StringName) -> void:
	push_warning("Cards: 技能牌 %s 被拒（%s），已退回手牌" % [card_id, reason])
	if GameState.has_card(card_id):
		return
	GameState.add_card(card_id)


func _tower_attack(tower_type: StringName) -> int:
	var towers := JsonConfig.load_dict(TOWERS_PATH)
	for entry in JsonConfig.get_array(towers, "towers"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var tower: Dictionary = entry
		if String(tower.get("id", "")) == String(tower_type):
			return int(tower.get("attack", 0))
	return 0
