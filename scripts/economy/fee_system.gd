extends Node
## 费用系统（autoload 名：Fee）—— 战斗内「费用」这一轨的唯一入口。
##
## 负责：开局额度、基地定时产费、击杀奖励、建造扣费、拆塔退款、余额不足判定。
## 不负责：代币（那是 Shop）、胜负判定（那是 P1 发信号、Settlement 结算）。
##
## 铁律：费用与代币是两条轨道。这里只碰 GameState.fee，一行都不碰 GameState.tokens。
##
## 对外接口（P1 / P3 调用）：
##   Fee.try_spend(cost, &"build")       建造前扣费，返回 false 表示余额不足，不要建塔
##   Fee.refund_tower(&"A")              拆塔前算退款并加费，返回实际退回的金额
##   Fee.add_fee(amount, &"bonus")       其它来源加费（预留）
##   Fee.can_afford(cost)                只查询不扣费

const ECONOMY_PATH := "res://data/economy.json"
const TOWERS_PATH := "res://data/towers/towers.json"
const SHOP_PATH := "res://data/shop/shop.json"

# ---- 配置读出来的值，全部来自 data/，代码里不写死 ----
var _initial_fee: int = 0
var _passive_enabled: bool = false
var _passive_amount: int = 0
var _passive_interval: float = 0.0
var _kill_reward_default: int = 0
var _sell_refund_ratio: float = 0.0

## 基地产费计时器。只在战斗内有意义：station_started 开启，station_cleared / failed 关闭。
var _income_timer: Timer


func _ready() -> void:
	_load_config()
	_income_timer = Timer.new()
	_income_timer.name = "PassiveIncomeTimer"
	_income_timer.one_shot = false
	_income_timer.timeout.connect(_on_income_tick)
	add_child(_income_timer)

	SignalBus.station_started.connect(_on_station_started)
	SignalBus.station_cleared.connect(_on_station_ended)
	SignalBus.station_failed.connect(_on_station_ended)
	SignalBus.enemy_killed.connect(_on_enemy_killed)


func _load_config() -> void:
	var economy := JsonConfig.load_dict(ECONOMY_PATH)
	_initial_fee = JsonConfig.get_int(economy, "fee/initial_fee", 0)
	_passive_enabled = JsonConfig.get_bool(economy, "fee/passive_income/enabled", false)
	_passive_amount = JsonConfig.get_int(economy, "fee/passive_income/amount", 0)
	_passive_interval = JsonConfig.get_float(economy, "fee/passive_income/interval", 0.0)
	_kill_reward_default = JsonConfig.get_int(economy, "fee/kill_reward_default", 50)
	_sell_refund_ratio = JsonConfig.get_float(economy, "fee/sell_refund_ratio", 0.5)


# ============================================================
# 对外接口
# ============================================================

## 能否付得起。只查不改，P1 想在按钮上置灰时用它。
func can_afford(cost: int) -> bool:
	return GameState.fee >= cost


## 扣费。返回 false 表示余额不足，调用方（P1）必须放弃本次建造。
## 为什么先查后扣而不是"扣了再说"：建造失败要能原样退回，而不是在别处补一笔。
func try_spend(cost: int, reason: StringName = &"build") -> bool:
	if cost <= 0:
		return true
	if GameState.fee < cost:
		SignalBus.fee_insufficient.emit(cost, GameState.fee)
		return false
	GameState.fee -= cost
	SignalBus.fee_spent.emit(cost, reason)
	SignalBus.fee_changed.emit(GameState.fee)
	return true


## 加费。reason 用 &"passive" / &"kill" / &"refund" / &"bonus"。
func add_fee(amount: int, reason: StringName = &"bonus") -> void:
	if amount <= 0:
		return
	GameState.fee += amount
	SignalBus.fee_gained.emit(amount, reason)
	SignalBus.fee_changed.emit(GameState.fee)


## 拆塔退款：按 towers.json 的造价 × data/economy.json 的比例算。
## 比例只存在 P2 的数据里，所以由 P2 算，P1 拿返回值去发 tower_sold。
## 返回实际退回的金额；塔型不认识时返回 0 并警告。
func refund_tower(tower_type: StringName) -> int:
	var cost := _tower_cost(tower_type)
	if cost <= 0:
		push_warning("Fee.refund_tower: 未知塔型 %s，不退款" % tower_type)
		return 0
	var refund := int(round(cost * _sell_refund_ratio))
	add_fee(refund, &"refund")
	return refund


# ============================================================
# 信号处理（P1 发来的战斗事实）
# ============================================================

func _on_station_started(_station_index: int, _base_points: int) -> void:
	# 新的一关：费用从初始额度重新开始，上一关剩的余额不带过来。
	GameState.fee = _initial_fee
	SignalBus.fee_changed.emit(GameState.fee)
	_start_passive_income()


func _on_station_ended(_station_index: int) -> void:
	# 本关结束就停产费，避免结算界面上数字还在跳。
	_income_timer.stop()


## 击杀奖励。reward 是 P1 从 data/enemies 读到的值；传 0 时按 economy.json 的默认值兜底。
func _on_enemy_killed(_enemy_id: int, reward: int) -> void:
	GameState.note_enemy_killed()
	add_fee(reward if reward > 0 else _kill_reward_default, &"kill")


# ============================================================
# 基地定时产费
# ============================================================

func _start_passive_income() -> void:
	if not _passive_enabled or _passive_amount <= 0 or _passive_interval <= 0.0:
		return
	_income_timer.wait_time = _passive_interval
	_income_timer.start()


func _on_income_tick() -> void:
	var amount := int(round(_passive_amount * _income_multiplier()))
	add_fee(maxi(amount, 1), &"passive")


## 产能强化（两档全局升级）对产费的加成。数据在 data/shop/shop.json 的 upgrades 里。
## 找不到配置时返回 1.0，保证不影响基本产费。
func _income_multiplier() -> float:
	var tier := GameState.get_upgrade_tier(&"income")
	if tier <= 0:
		return 1.0
	var shop := JsonConfig.load_dict(SHOP_PATH)
	var upgrades := JsonConfig.get_array(shop, "upgrades")
	for entry in upgrades:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var upgrade: Dictionary = entry
		if String(upgrade.get("id", "")) != "income":
			continue
		for tier_entry in upgrade.get("tiers", []):
			if typeof(tier_entry) != TYPE_DICTIONARY:
				continue
			var tier_data: Dictionary = tier_entry
			if int(tier_data.get("tier", 0)) != tier:
				continue
			return float(tier_data.get("effect", {}).get("value", 1.0))
	return 1.0


func _tower_cost(tower_type: StringName) -> int:
	var towers := JsonConfig.load_dict(TOWERS_PATH)
	for entry in JsonConfig.get_array(towers, "towers"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var tower: Dictionary = entry
		if String(tower.get("id", "")) == String(tower_type):
			return int(tower.get("cost", 0))
	return 0
