extends Node
## 关卡推进与代币结算（autoload 名：Settlement）。
##
## 负责：开一局、进入某一小关、基地掉点、胜利后把「基地剩余点数」换成代币、推进关号。
## 不负责：胜负判定（P1 发 station_cleared / station_failed）、界面切换（P3 的 Flow）。
##
## 对外接口：
##   Settlement.start_run(deck_id)          选完牌组、进战斗前调用一次；deck_id 传 &"" 表示跳过选择
##   Settlement.begin_current_station()     战斗场景 _ready 里调用，本关状态就位后才发 station_started
##   Settlement.advance_to_next_station()   一般由 shop_closed 自动触发，也可手动调
##
## 重要：station_started 是在场景加载前发出的，P1 / P3 的节点 _ready 里请直接读 GameState，
## 不要依赖收到这条信号——那时场景还不存在。

const ECONOMY_PATH := "res://data/economy.json"

var _config: Dictionary = {}
var _stations: Array = []
## 已经结算过的关号。用来挡住同一关重复发来的 station_cleared，
## 否则同一条信号被 P1 和调试脚本各发一次，代币就会翻倍。
var _settled_index: int = -1


func _ready() -> void:
	_config = JsonConfig.load_dict(ECONOMY_PATH)
	_stations = JsonConfig.get_array(_config, "stations")
	GameState.total_stations = maxi(_stations.size(), 1)

	SignalBus.station_cleared.connect(_on_station_cleared)
	SignalBus.station_failed.connect(_on_station_failed)
	SignalBus.base_lost.connect(_on_base_lost)
	SignalBus.shop_closed.connect(_on_shop_closed)


# ============================================================
# 对外接口
# ============================================================

## 开一局：状态清零 → 装配起始牌组 → 通知全队。
## 调用方：P3 的选牌组界面。跳过选择时 deck_id 传 &""。
func start_run(deck_id: StringName) -> void:
	GameState.reset_run()
	GameState.total_stations = maxi(_stations.size(), 1)
	Cards.apply_start_deck(deck_id)
	SignalBus.run_started.emit()


## 本关状态就位。由战斗场景的 _ready 调用，保证 Fee 的产费、P3 的血条都在本关开始时才启动。
func begin_current_station() -> void:
	_settled_index = -1
	GameState.begin_station(GameState.station_index, _base_points_for(GameState.station_index))


## 进入下一小关。已经是最后一关时返回 false，本轮结束（通关界面由 P3 处理）。
func advance_to_next_station() -> bool:
	if GameState.station_index + 1 >= GameState.total_stations:
		return false
	GameState.station_index += 1
	return true


# ============================================================
# 信号处理
# ============================================================

## 一处基地被摧毁 → 扣 1 点基地点数（占位规则，见 docs/p2-scope.md 第 7 节）。
func _on_base_lost(_base_id: int) -> void:
	GameState.change_base_points(-1)


## 本关胜利：按基地剩余点数结算代币。同一关只结算一次。
func _on_station_cleared(station_index: int) -> void:
	if station_index != GameState.station_index:
		push_warning("Settlement: 收到第 %d 关的胜利信号，但当前是第 %d 关，已忽略" % [
			station_index, GameState.station_index,
		])
		return
	if _settled_index == station_index:
		push_warning("Settlement: 第 %d 关已经结算过，重复信号已忽略" % station_index)
		return
	_settled_index = station_index
	GameState.stations_cleared += 1
	var gained := _compute_tokens(true)
	_award_tokens(gained)
	SignalBus.station_settled.emit(station_index, gained)


## 本关失败：不结算代币，只把"本关到此为止"告诉界面。
func _on_station_failed(station_index: int) -> void:
	if station_index != GameState.station_index:
		return
	if _settled_index == station_index:
		return
	_settled_index = station_index
	SignalBus.station_settled.emit(station_index, 0)


## 商店关门 = 玩家买完了，推进到下一关。
func _on_shop_closed() -> void:
	advance_to_next_station()


# ============================================================
# 结算公式（数值全部来自 data/economy.json）
# ============================================================

func _compute_tokens(cleared: bool) -> int:
	if not cleared:
		return JsonConfig.get_int(_config, "settlement/fail_bonus", 0)
	var bonus := JsonConfig.get_int(_config, "settlement/clear_base_bonus", 0)
	var per_point := JsonConfig.get_float(_config, "settlement/tokens_per_base_point", 0.0)
	return int(round(bonus + float(GameState.base_points) * per_point))


func _award_tokens(amount: int) -> void:
	if amount <= 0:
		return
	GameState.tokens += amount
	SignalBus.tokens_changed.emit(GameState.tokens)


func _base_points_for(station_index: int) -> int:
	for entry in _stations:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var station: Dictionary = entry
		if int(station.get("index", -1)) == station_index:
			return int(station.get("base_points", 0))
	# 配置里没有这一关（例如关数被改动过），给一个保守值而不是 0：0 会让本关直接失败。
	push_warning("Settlement: data/economy.json 的 stations 里没有第 %d 关，按 20 点兜底" % station_index)
	return 20
