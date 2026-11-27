extends Node
## 事件总线：跨模块通信的唯一通道。
##
## 开工首日冻结信号名与参数，此后只允许向后兼容的新增，禁止改名或删除。

## 费用数值发生变化。
signal fee_changed(value: int)
## 代币余额发生变化。
signal tokens_changed(value: int)
## 一座塔建造成功。
signal tower_built(tower_id: int, tower_type: StringName)
## 一座塔被拆除并退款。
signal tower_sold(tower_id: int, refund: int)
## 敌人被击杀并结算奖励。
signal enemy_killed(enemy_id: int, reward: int)
## 新一波敌人开始投放。
signal wave_started(wave_index: int)
## 一处基地被摧毁。
signal base_lost(base_id: int)
## 本关胜利并完成结算。
signal station_cleared(station_index: int)
## 本关失败。
signal station_failed(station_index: int)
## 离开商店进入下一关。
signal shop_closed()
