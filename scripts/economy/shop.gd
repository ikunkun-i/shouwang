extends Node
## 商店业务逻辑（autoload 名：Shop）—— 关间「代币」这一轨的唯一入口。
##
## 负责：陈列生成、买塔牌、买技能牌、出售技能牌、付费重置、两档全局升级、涨价。
## 不负责：面板外观与控件摆放（P3 做）。P3 只调用这里的方法，并监听 shop_offer_changed 重画。
##
## 铁律：这里只碰 GameState.tokens，一行都不碰 GameState.fee。

const SHOP_PATH := "res://data/shop/shop.json"

var _config: Dictionary = {}
## 当前陈列：[{kind, card_id, price, sold, name, desc}]
var _offers: Array = []
var _reroll_count: int = 0
var _is_open: bool = false


func _ready() -> void:
	_config = JsonConfig.load_dict(SHOP_PATH)


# ============================================================
# 开关与陈列
# ============================================================

## 商店开张。由商店场景的 _ready 调用（P3 的 scenes/shop/shop.tscn）。
func open_shop(station_index: int) -> void:
	_is_open = true
	if JsonConfig.get_bool(_config, "reroll/reset_per_station", true):
		_reroll_count = 0
	_generate_offers()
	SignalBus.shop_opened.emit(station_index)
	SignalBus.shop_offer_changed.emit(get_offers())


## 离开商店。P2 收到 shop_closed 后会推进到下一关（见 Settlement）。
func close_shop() -> void:
	if not _is_open:
		return
	_is_open = false
	SignalBus.shop_closed.emit()


func is_open() -> bool:
	return _is_open


func get_offers() -> Array:
	return _offers.duplicate(true)


## 当前重置价格：基础价 + 每次递增，次数越多越贵。
func get_reroll_cost() -> int:
	var base := JsonConfig.get_int(_config, "reroll/base_cost", 0)
	var step := JsonConfig.get_int(_config, "reroll/cost_step", 0)
	return base + step * _reroll_count


## 卡牌实际售价 = 基础售价 × 涨价系数。
func get_price(card_id: StringName) -> int:
	var base := Cards.get_price(card_id)
	if base <= 0:
		return 0
	return int(round(float(base) * _price_multiplier(GameState.station_index)))


# ============================================================
# 购买
# ============================================================

func buy_tower_card(card_id: StringName) -> bool:
	return _buy_offer(card_id)


func buy_skill_card(card_id: StringName) -> bool:
	return _buy_offer(card_id)


func _buy_offer(card_id: StringName) -> bool:
	if not _is_open:
		SignalBus.purchase_failed.emit(&"shop_closed", 0, GameState.tokens)
		return false

	var index := _find_offer_index(card_id)
	if index == -1:
		SignalBus.purchase_failed.emit(&"not_offered", 0, GameState.tokens)
		return false

	var offer: Dictionary = _offers[index]
	if bool(offer.get("sold", false)):
		SignalBus.purchase_failed.emit(&"sold_out", int(offer.get("price", 0)), GameState.tokens)
		return false

	# 已解锁的塔型不再上架，这条只防手滑重复买。
	if String(offer.get("kind", "")) == "tower":
		var card := Cards.get_card(card_id)
		var tower_type := StringName(String(card.get("tower_type", "")))
		if GameState.is_tower_unlocked(tower_type):
			SignalBus.purchase_failed.emit(&"already_owned", int(offer.get("price", 0)), GameState.tokens)
			return false

	var price := int(offer.get("price", 0))
	if not _spend_tokens(price):
		SignalBus.purchase_failed.emit(&"insufficient_tokens", price, GameState.tokens)
		return false

	Cards.grant_card(card_id)
	offer["sold"] = true
	_offers[index] = offer
	SignalBus.shop_offer_changed.emit(get_offers())
	return true


## 出售技能牌，返还售价的固定比例（比例在 data/shop/shop.json）。
## 塔牌不能卖：卖掉塔牌等于把已解锁的塔型收回，会把 P1 那边的塔变成"非法存在"。
func sell_card(card_id: StringName) -> bool:
	var card := Cards.get_card(card_id)
	if card.is_empty():
		return false
	if String(card.get("kind", "")) == "tower":
		SignalBus.purchase_failed.emit(&"cannot_sell_tower", 0, GameState.tokens)
		return false
	if not GameState.has_card(card_id):
		SignalBus.purchase_failed.emit(&"not_in_deck", 0, GameState.tokens)
		return false

	var ratio := JsonConfig.get_float(_config, "sell_refund_ratio", 0.5)
	var refund := int(round(float(Cards.get_price(card_id)) * ratio))
	if not GameState.remove_card(card_id):
		return false
	if refund > 0:
		GameState.tokens += refund
		SignalBus.tokens_changed.emit(GameState.tokens)
	SignalBus.card_removed.emit(card_id, refund)
	return true


## 两档全局升级。tier 自动取"当前档位 + 1"，买满了就失败。
func buy_upgrade(upgrade_id: StringName) -> bool:
	var upgrade := _find_upgrade(upgrade_id)
	if upgrade.is_empty():
		SignalBus.purchase_failed.emit(&"unknown_upgrade", 0, GameState.tokens)
		return false

	var next_tier := GameState.get_upgrade_tier(upgrade_id) + 1
	var tier_data := _find_tier(upgrade, next_tier)
	if tier_data.is_empty():
		SignalBus.purchase_failed.emit(&"max_tier", 0, GameState.tokens)
		return false

	var price := int(tier_data.get("price", 0))
	if not _spend_tokens(price):
		SignalBus.purchase_failed.emit(&"insufficient_tokens", price, GameState.tokens)
		return false

	# 升级档位是"累计生效"：买第二档直接覆盖成第二档的效果，不叠加两次。
	GameState.set_upgrade(upgrade_id, next_tier)
	return true


# ============================================================
# 重置
# ============================================================

## 付费重置陈列。返回 false 表示代币不够。
func reroll() -> bool:
	if not _is_open:
		return false
	var cost := get_reroll_cost()
	var max_rerolls := JsonConfig.get_int(_config, "reroll/max_rerolls", 0)
	if max_rerolls > 0 and _reroll_count >= max_rerolls:
		SignalBus.purchase_failed.emit(&"max_rerolls", cost, GameState.tokens)
		return false
	if not _spend_tokens(cost):
		SignalBus.purchase_failed.emit(&"insufficient_tokens", cost, GameState.tokens)
		return false

	_reroll_count += 1
	_generate_offers()
	SignalBus.shop_offer_changed.emit(get_offers())
	return true


## 「查看挑战」：策划案只给了入口，没有玩法，这里先把配置原样交给 P3 显示。
func get_challenge_info() -> Dictionary:
	return JsonConfig.get_dict(_config, "challenge")


# ============================================================
# 给界面的展示数据（P3 直接渲染，不要自己解析 data/）
# ============================================================

## 陈列槽位的展示数据。affordable 已经把「买不买得起」算好，P3 据此置灰即可。
## 每项：{kind, card_id, name, desc, price, sold, affordable, card}
func get_offer_view_models() -> Array:
	var views: Array = []
	for offer in _offers:
		var card_id := StringName(String(offer.get("card_id", "")))
		var price := int(offer.get("price", 0))
		var sold := bool(offer.get("sold", false))
		views.append({
			"kind": String(offer.get("kind", "")),
			"card_id": card_id,
			"name": String(offer.get("name", "")),
			"desc": String(offer.get("desc", "")),
			"price": price,
			"sold": sold,
			"affordable": (not sold) and GameState.tokens >= price,
			"card": Cards.get_card_view(card_id),
		})
	return views


## 两档升级服务的展示数据。每项给出「当前档」与「下一档」，买满时 next_tier 为 0。
## 每项：{id, name, current_tier, max_tier, next_tier, next_price, next_desc, maxed, affordable}
func get_upgrade_view_models() -> Array:
	var views: Array = []
	for entry in JsonConfig.get_array(_config, "upgrades"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var upgrade: Dictionary = entry
		var upgrade_id := StringName(String(upgrade.get("id", "")))
		var tiers: Array = upgrade.get("tiers", [])
		var max_tier := tiers.size()
		var current := GameState.get_upgrade_tier(upgrade_id)
		var next_tier := current + 1
		var next_price := 0
		var next_desc := "已满级"
		if next_tier <= max_tier:
			var tier_data := _find_tier(upgrade, next_tier)
			next_price = int(tier_data.get("price", 0))
			next_desc = String(tier_data.get("desc", ""))
		views.append({
			"id": upgrade_id,
			"name": String(upgrade.get("name", "")),
			"current_tier": current,
			"max_tier": max_tier,
			"next_tier": next_tier if next_tier <= max_tier else 0,
			"next_price": next_price,
			"next_desc": next_desc,
			"maxed": next_tier > max_tier,
			"affordable": next_tier <= max_tier and GameState.tokens >= next_price,
		})
	return views


## 当前可以出售的牌（技能牌）。塔牌卖了会把已解锁塔型收回，所以不在列表里。
## 每项：{card_id, name, refund, card}
func get_sellable_cards() -> Array:
	var ratio := JsonConfig.get_float(_config, "sell_refund_ratio", 0.5)
	var views: Array = []
	for card_id in GameState.deck:
		var card := Cards.get_card(card_id)
		if card.is_empty():
			continue
		if String(card.get("kind", "")) == "tower":
			continue
		views.append({
			"card_id": card_id,
			"name": Cards.get_display_name(card_id),
			"refund": int(round(float(Cards.get_price(card_id)) * ratio)),
			"card": Cards.get_card_view(card_id),
		})
	return views


## 商店面板一次刷新要的全部数据。P3 调这一个方法就够，不用分别取。
func get_panel_state() -> Dictionary:
	return {
		"open": _is_open,
		"station_index": GameState.station_index,
		"tokens": GameState.tokens,
		"offers": get_offer_view_models(),
		"upgrades": get_upgrade_view_models(),
		"sellable": get_sellable_cards(),
		"reroll_cost": get_reroll_cost(),
		"can_reroll": _is_open and GameState.tokens >= get_reroll_cost(),
		"challenge": get_challenge_info(),
	}


# ============================================================
# 内部
# ============================================================

func _generate_offers() -> void:
	_offers.clear()

	var slots := JsonConfig.get_dict(_config, "slots")
	var tower_slots := JsonConfig.get_int(slots, "tower_cards", 0)
	var skill_slots := JsonConfig.get_int(slots, "skill_cards", 0)

	# 塔牌：三张全上架，但已解锁的塔型不再出现。
	var available_towers: Array = []
	for card_id in Cards.get_ids_of_kind("tower"):
		var card := Cards.get_card(card_id)
		var tower_type := StringName(String(card.get("tower_type", "")))
		if not GameState.is_tower_unlocked(tower_type):
			available_towers.append(card_id)
	for i in mini(tower_slots, available_towers.size()):
		_offers.append(_make_offer(available_towers[i], "tower"))

	# 技能牌：从六张里随机取，不重复。
	var pool := Cards.get_all_skill_card_ids()
	_shuffle(pool)
	for i in mini(skill_slots, pool.size()):
		_offers.append(_make_offer(pool[i], "skill"))


func _make_offer(card_id: StringName, kind: String) -> Dictionary:
	var card := Cards.get_card(card_id)
	return {
		"kind": kind,
		"card_id": card_id,
		"name": Cards.get_display_name(card_id),
		"desc": String(card.get("desc", card.get("_detail", ""))),
		"price": get_price(card_id),
		"sold": false,
	}


func _find_offer_index(card_id: StringName) -> int:
	for i in _offers.size():
		var offer: Dictionary = _offers[i]
		if StringName(String(offer.get("card_id", ""))) == card_id:
			return i
	return -1


func _spend_tokens(amount: int) -> bool:
	if amount <= 0:
		return true
	if GameState.tokens < amount:
		return false
	GameState.tokens -= amount
	SignalBus.tokens_changed.emit(GameState.tokens)
	return true


## 涨价系数：从 data/shop/shop.json 的 price_inflation 读。
## 第二大关起每多一关乘一次，封顶 max_multiplier。
func _price_multiplier(station_index: int) -> float:
	var start := JsonConfig.get_int(_config, "price_inflation/start_station", 1)
	var step := JsonConfig.get_float(_config, "price_inflation/step_per_station", 0.0)
	var cap := JsonConfig.get_float(_config, "price_inflation/max_multiplier", 1.0)
	if station_index < start or step <= 0.0:
		return 1.0
	var multiplier := 1.0 + step * float(station_index - start + 1)
	return minf(multiplier, cap)


func _find_upgrade(upgrade_id: StringName) -> Dictionary:
	for entry in JsonConfig.get_array(_config, "upgrades"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var upgrade: Dictionary = entry
		if StringName(String(upgrade.get("id", ""))) == upgrade_id:
			return upgrade
	return {}


func _find_tier(upgrade: Dictionary, tier: int) -> Dictionary:
	for entry in upgrade.get("tiers", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var tier_data: Dictionary = entry
		if int(tier_data.get("tier", 0)) == tier:
			return tier_data
	return {}


## 打乱数组。用 Fisher-Yates，避免依赖全局随机数的实现细节。
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
