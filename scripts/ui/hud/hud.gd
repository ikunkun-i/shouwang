extends CanvasLayer
## 战斗内 HUD：只显示数字，不计算任何数值。
##
## 数据来源分两处，都必须遵守：
## - 余额与基地点数：读 GameState（P2 写的），只在收到信号时刷新
## - 波次总数：读 data/waves/index.json（Godot 只读文件，不算写状态）
##
## 为什么不在 _process 里每帧轮询 GameState：轮询会让「谁改了值」这件事
## 变得不可追，信号才是唯一可靠的刷新时机；轮询只在信号漏发时掩盖 bug。

## 波次索引文件。总数显示从这里取，因为 SignalBus.wave_started 只带当前序号。
const WAVE_INDEX_PATH := "res://data/waves/index.json"

## SignalBus.wave_started 的序号是否从 0 开始。P1 若改成从 1 开始，只改这一处。
const WAVE_IS_ZERO_BASED := true

var _total_waves: int = 0
var _current_wave: int = 0
var _has_battle_started: bool = false

@onready var _fee_label: Label = %FeeLabel
@onready var _tokens_label: Label = %TokensLabel
@onready var _wave_label: Label = %WaveLabel
@onready var _base_label: Label = %BaseLabel


func _ready() -> void:
	_total_waves = _read_total_waves()

	# 只订阅这四个信号。多听一个信号，界面就可能和真正的数据源抢着刷新。
	SignalBus.fee_changed.connect(_on_fee_changed)
	SignalBus.tokens_changed.connect(_on_tokens_changed)
	SignalBus.wave_started.connect(_on_wave_started)
	SignalBus.base_lost.connect(_on_base_lost)

	_refresh_all()


# ---------------------------------------------------------------- 刷新逻辑


func _refresh_all() -> void:
	_fee_label.text = "费用 %d" % GameState.fee
	_tokens_label.text = "代币 %d" % GameState.tokens
	_base_label.text = "基地 %d" % GameState.base_points
	_refresh_wave()


func _refresh_wave() -> void:
	if not _has_battle_started:
		_wave_label.text = "未开战"
		return
	if _total_waves > 0:
		_wave_label.text = "第 %d 波 / 共 %d 波" % [_current_wave, _total_waves]
	else:
		# 读不到 index.json 时不要把总数编成 1，宁可少显示一半。
		_wave_label.text = "第 %d 波" % _current_wave
		push_warning("HUD: 未能从 %s 读到 total_waves，波次总数不显示" % WAVE_INDEX_PATH)


func _on_fee_changed(value: int) -> void:
	_fee_label.text = "费用 %d" % value


func _on_tokens_changed(value: int) -> void:
	_tokens_label.text = "代币 %d" % value


func _on_wave_started(wave_index: int) -> void:
	_has_battle_started = true
	_current_wave = wave_index + 1 if WAVE_IS_ZERO_BASED else wave_index
	_refresh_wave()


func _on_base_lost(_base_id: int) -> void:
	# 基地点数由 P1 扣、P2 写，这里只重新读一次，不自己减。
	_base_label.text = "基地 %d" % GameState.base_points


# ---------------------------------------------------------------- 读配置


func _read_total_waves() -> int:
	if not FileAccess.file_exists(WAVE_INDEX_PATH):
		return 0
	var f := FileAccess.open(WAVE_INDEX_PATH, FileAccess.READ)
	if f == null:
		push_error("HUD: 打不开 %s，错误码 %d" % [WAVE_INDEX_PATH, FileAccess.get_open_error()])
		return 0
	var text := f.get_as_text()
	f.close()

	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("HUD: %s 不是合法 JSON 对象" % WAVE_INDEX_PATH)
		return 0

	var total: Variant = data.get("total_waves")
	if typeof(total) != TYPE_FLOAT and typeof(total) != TYPE_INT:
		push_error("HUD: %s 缺少 total_waves 或类型不对" % WAVE_INDEX_PATH)
		return 0
	return int(total)
