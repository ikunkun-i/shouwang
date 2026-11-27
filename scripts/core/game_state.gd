extends Node
## 全局状态单例（唯一状态权威）。
##
## 只有 P2（经济域）可以写入，P1、P3 一律只读；任何修改都必须
## 在写入后通过 SignalBus 发信号，界面依据信号刷新，不得自行推算。

## 战斗内可用费用余额。
var fee: int = 0
## 关间代币余额。
var tokens: int = 0
## 已解锁的塔型列表。
var unlocked_towers: Array[StringName] = []
## 当前关卡序号，从 0 开始。
var station_index: int = 0
## 本关基地剩余点数（掉到 0 即失败）。
var base_points: int = 0


## 开始新的一局时清零。
func reset_run() -> void:
	fee = 0
	tokens = 0
	unlocked_towers.clear()
	station_index = 0
	base_points = 0
