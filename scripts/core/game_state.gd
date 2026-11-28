extends Node
## 全局状态单例（唯一状态权威）—— 字段定稿 v1 / 2026-11-28。
##
## 谁能写：只有 P2 的四个脚本（fee_system.gd / settlement.gd / shop.gd / card_db.gd）。
##          P1、P3 一律只读；需要改状态时调用本文件或 P2 脚本的公开方法，不要直接赋值。
## 谁能读：所有人。
## 广播规则：本文件里的写方法都会自己发信号（deck / 基地点数 / 塔型 / 升级），
##          费用与代币的写入在 Fee、Shop 里，由它们发 fee_changed / tokens_changed。
##
## 字段说明与读方清单见 docs/p2-scope.md 第 2 节。改字段前先改那份文档。

# ============================================================
# 一、战斗资源（双轨，不能混用）
# ============================================================

## 战斗内可用费用。来源：初始费用、基地定时产费、击杀奖励、拆塔退款。
var fee: int = 0
## 关间代币余额。来源：每关胜利结算；去向：商店买牌、升级、重置。
var tokens: int = 0

# ============================================================
# 二、关卡进度
# ============================================================

## 当前小关序号，从 0 起。
var station_index: int = 0
## 本轮总关数。P3 用它显示「第 X / Y 站」。
var total_stations: int = 5
## 本关基地剩余点数。掉到 0 即失败（判定在 P1，扣减由 Settlement 做）。
var base_points: int = 0
## 本关基地初始总点数，用于血条比例与结算。
var base_total_points: int = 0

# ============================================================
# 三、牌组与解锁
# ============================================================

## 当前持有的牌：塔牌与技能牌的 id（见 data/cards/cards.json）。
var deck: Array[StringName] = []
## 已解锁塔型："A" / "B" / "C"。空数组时 P1 不应放出任何塔。
var unlocked_towers: Array[StringName] = []
## 已购全局升级档位，例如 {"damage": 1}；0 或缺失表示未购买。
## 注意：这是**全局增益**，不是逐塔升级。
var upgrades: Dictionary = {}

# ============================================================
# 四、统计（结算面板与开发者日志用）
# ============================================================

## 本关累计击杀数。
var enemies_killed: int = 0
## 本关累计建塔数。
var towers_built: int = 0
## 本轮已通过的小关数。
var stations_cleared: int = 0
## 最近一次结算到账的代币数（P3 的结算面板直接读它显示「本关获得 X 代币」）。
## 失败时是 0。它只是显示用的快照，真正的余额在 tokens 里。
var last_station_reward: int = 0


# ============================================================
# 写入方法（只有 P2 调用）
# ============================================================

## 开始新的一局：全部清零。失败后重开也走这里，不能只清一部分。
func reset_run() -> void:
	fee = 0
	tokens = 0
	station_index = 0
	base_points = 0
	base_total_points = 0
	deck.clear()
	unlocked_towers.clear()
	upgrades.clear()
	enemies_killed = 0
	towers_built = 0
	stations_cleared = 0
	last_station_reward = 0


## 进入某一小关：设置关号与基地点数，并广播「本关已就绪」。
## 调用时机：选完牌组进战斗前、商店关闭进下一关前。P1 收到 station_started 后才投放第一波。
func begin_station(index: int, total_points: int) -> void:
	station_index = index
	base_total_points = maxi(total_points, 0)
	base_points = base_total_points
	SignalBus.base_points_changed.emit(base_points, base_total_points)
	SignalBus.station_started.emit(station_index, base_points)


## 基地点数增减。P1 发 base_lost，Settlement 收到后调这里扣点。
## 夹在 [0, base_total_points] 之间，避免出现负血量。
func change_base_points(delta: int) -> void:
	var next_value := clampi(base_points + delta, 0, base_total_points)
	if next_value == base_points:
		return
	base_points = next_value
	SignalBus.base_points_changed.emit(base_points, base_total_points)


## 获得一张牌。允许重复卡（同一技能牌可以买两张）。
func add_card(card_id: StringName) -> void:
	if card_id == &"":
		push_error("GameState.add_card: card_id 不能为空")
		return
	deck.append(card_id)
	SignalBus.card_added.emit(card_id)
	SignalBus.deck_changed.emit(deck.duplicate())


## 消耗一张牌（卖掉或打出）。返回是否真的移除。
func remove_card(card_id: StringName) -> bool:
	var index := deck.find(card_id)
	if index == -1:
		push_warning("GameState.remove_card: 牌组里没有 %s" % card_id)
		return false
	deck.remove_at(index)
	SignalBus.deck_changed.emit(deck.duplicate())
	return true


## 解锁一种塔型。重复解锁会被忽略，不会重复广播。
func unlock_tower(tower_type: StringName) -> void:
	if unlocked_towers.has(tower_type):
		return
	unlocked_towers.append(tower_type)
	SignalBus.tower_unlocked.emit(tower_type)


func has_card(card_id: StringName) -> bool:
	return deck.has(card_id)


func is_tower_unlocked(tower_type: StringName) -> bool:
	return unlocked_towers.has(tower_type)


## 记一档全局升级。tier 从 1 起，只增不减。
func set_upgrade(upgrade_id: StringName, tier: int) -> void:
	upgrades[upgrade_id] = tier
	SignalBus.upgrade_purchased.emit(upgrade_id, tier)


## 取某一档升级的等级，未购买返回 0。P1 计算塔的属性加成时读它。
func get_upgrade_tier(upgrade_id: StringName) -> int:
	return int(upgrades.get(upgrade_id, 0))


func note_enemy_killed() -> void:
	enemies_killed += 1


func note_tower_built() -> void:
	towers_built += 1
