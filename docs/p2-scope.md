# P2 经济域：职责与实现范围

> 依据：`docs/plan-v2.0-master.docx`（2026-11-27 拍板口径）、`docs/program-division.pdf`、`docs/team.md`。
> 冲突时的优先级：**主策划案 > 本文件 > AI 提示词**。`docs/plan-v1.0.pdf` 已作废，只作对照，不得据此实现。
> 旧《程序组分工方案》与 v2.0 的逐条差异见 `docs/division-delta-v2.md`（那份成稿依据的是 v1.0，有 8 处需要改）。
> 本文件由 P2（星辰）维护，改了字段或信号必须同步更新本文件并在群里说一句。

## 0. 一句话边界

我负责**钱、牌、买卖，以及全队唯一的状态与信号**。

- 战斗事实（塔打没打中、敌人死没死、基地被谁撞掉、波次怎么投）归 P1，我只结算奖惩、只读它的信号。
- 界面外观、主题、HUD 排版、场景流程推进归 P3；商店的**业务逻辑**归我，**视觉与控件外观**归 P3，两者以「我提供数据与方法、P3 负责摆放与样式」为界。

## 1. 要从策划案落地的规则

| 编号 | 策划案要点 | 落地位置 | 状态 |
| --- | --- | --- | --- |
| E1 | 双资源：战斗内「费用」、关间「代币」，两套不能混用 | `GameState.fee` / `GameState.tokens`、`scripts/economy/fee_system.gd` | 定稿 |
| E2 | 费用来源三条：每小关初始费用、战斗中基地定时产费、每击杀一名敌人 +50 | `fee_system.gd`、`data/economy.json` | 定稿（数值占位） |
| E3 | 拆塔可回收费用，返还比例待定 | `fee_system.gd`、`data/economy.json > fee.sell_refund_ratio` | 比例待定 |
| E4 | 建造费用：A 100 / B 75 / C 150 | 读 `data/towers/towers.json`，不写死在代码里 | 定稿 |
| E5 | 胜利后按基地剩余点数结算代币 | `scripts/economy/settlement.gd`、`data/economy.json > settlement` | 公式占位 |
| E6 | 商店陈列 3 张塔牌 + 2 张技能牌 | `scripts/economy/shop.gd`、`data/shop/shop.json` | 定稿 |
| E7 | 商店服务：两档升级（第二档更贵）、查看挑战、付费重置、出售卡牌 | 同上 | 定稿（价格占位） |
| E8 | 进入第二大关后商店价格略有上涨 | `data/shop/shop.json > price_inflation` | 曲线占位 |
| E9 | 技能牌售价一律暂定 50 代币 | `data/cards/cards.json` | 暂定 |
| E10 | 塔牌效果是「解锁塔型」，不是一次性放置 | `scripts/cards/card_db.gd`、`GameState.unlocked_towers` | 定稿 |
| E11 | 起始牌组三套（塔组 / 技能组 / 混合组），可跳过；跳过只给 1 种基础炮台（A） | `data/start_decks/`、`scripts/economy/shop.gd > start_run_from_deck` | 定稿 |
| E12 | 四张塔技能牌：加攻击力 / 加攻击范围 / 狂暴 / 修理 | `data/cards/cards.json`、`scripts/cards/skill_effects.gd` | 定稿 |
| E13 | 两张地块技能：冰冻 / 毒气 | 同上 | 毒气待调整 |
| E14 | 一次失败结束本轮挑战（回主菜单，不是重开本关） | `GameState.reset_run()`、P3 的 `Flow` | 定稿 |
| E15 | 随关卡推进，难度与基地数量增加，可结算代币随之增加 | `data/economy.json > stations` | 数值占位 |

### 明确不做（避免第二套实现）

- 不做「反应堆区」这类第二套产费来源。
- 不做逐塔升级：两档升级是**全局增益**（作用于全部塔）。
- 不做「用代币补费用」这类跨轨操作。
- 不做塔的攻击判定、索敌、阻挡、敌人移动：那是 P1。技能牌我只发「请求」，由 P1 施加到塔上。

## 2. 定稿 GameState 字段表

> 冻结版本：`v1 / 2026-11-28`。字段只增不改，改名等于全队返工。
> 写入者只有 P2 的四个脚本：`fee_system.gd`、`settlement.gd`、`shop.gd`、`card_db.gd`。P1 / P3 只读字段，或调用 P2 提供的公开方法。

| 字段 | 类型 | 含义 | 初始值 | 读方 |
| --- | --- | --- | --- | --- |
| `fee` | int | 战斗内可用费用 | 0 | P1 建塔、P3 HUD |
| `tokens` | int | 关间代币余额 | 0 | P3 商店、HUD |
| `station_index` | int | 当前小关序号，从 0 起 | 0 | P1 波次、P3 HUD |
| `total_stations` | int | 本轮总关数 | 5（占位） | P3 进度显示 |
| `base_points` | int | 本关基地剩余点数 | 0 | P3 HUD、`settlement.gd` |
| `base_total_points` | int | 本关基地初始总点数 | 0 | 结算比例、P3 血条 |
| `deck` | `Array[StringName]` | 当前持有的牌（塔牌 + 技能牌 id） | `[]` | P3 手牌区、`card_db.gd` |
| `unlocked_towers` | `Array[StringName]` | 已解锁塔型（"A" / "B" / "C"） | `[]` | P1 建造菜单、P3 显示 |
| `upgrades` | `Dictionary` | 已购全局升级档位：`{"damage": 1}`，0 或缺失 = 未购买 | `{}` | P1 取加成、P3 显示 |
| `enemies_killed` | int | 本关累计击杀数（结算与日志用） | 0 | P3 结算面板 |
| `towers_built` | int | 本关累计建塔数 | 0 | P3 结算面板 |
| `stations_cleared` | int | 本轮已通过的小关数 | 0 | P3 结算面板 |

**写入规则**：任何字段变化都要在同一帧内通过 `SignalBus` 广播对应信号；界面只监听，不自行推算。

## 3. 定稿 SignalBus 信号表

> 冻结版本：`v1 / 2026-11-28`。**只增不改**：可以新增信号，禁止改名、禁止改参数类型、禁止删除。
> 「谁发」一列里 `P2` 指本域的四个脚本。

### 3.1 资源与进度

| 信号 | 参数 | 谁发 | 谁听 | 时机 |
| --- | --- | --- | --- | --- |
| `fee_changed` | `value: int` | P2 | P1、P3 | 费用任何变化后 |
| `fee_gained` | `amount: int, reason: StringName` | P2 | P3（飘字） | 产费 / 击杀奖励 / 拆塔退款 |
| `fee_spent` | `amount: int, reason: StringName` | P2 | P3（飘字） | 建造 / 升级扣费 |
| `fee_insufficient` | `required: int, current: int` | P2 | P3（提示） | 余额不足、操作被拒 |
| `tokens_changed` | `value: int` | P2 | P3 | 代币任何变化后 |
| `base_points_changed` | `value: int, total: int` | P2 | P3（血条） | 基地点数变化后 |
| `station_started` | `station_index: int, base_points: int` | P2 | P1、P3 | 进入某一小关、状态已就绪。**注意：这条信号在战斗场景加载前就发出了**，场景 `_ready` 里请直接读 `GameState`，不要等信号 |
| `station_cleared` | `station_index: int` | P1 | P2、P3 | 基地守住了（P1 判定） |
| `station_failed` | `station_index: int` | P1 | P2、P3 | 基地被打空（P1 判定） |
| `station_settled` | `station_index: int, tokens_gained: int` | P2 | P3（结算面板） | 代币结算完成 |
| `run_started` | — | P2 | P1、P3 | 新开一局、牌组装配完成 |

### 3.2 战斗事实（P1 发，P2 只监听）

| 信号 | 参数 | 谁发 | 谁听 | 时机 |
| --- | --- | --- | --- | --- |
| `wave_started` | `wave_index: int` | P1 | P3 | 新一波开始投放 |
| `enemy_killed` | `enemy_id: int, reward: int` | P1 | P2、P3 | 敌人死亡；`reward` 传 0 时 P2 按 `data/enemies` 兜底 |
| `tower_built` | `tower_id: int, tower_type: StringName` | P1 | P2、P3 | 建塔成功（扣费已在 `Fee.try_spend` 完成） |
| `tower_sold` | `tower_id: int, refund: int` | P1 | P3 | 拆塔后通知；**退款本身由 `Fee.refund_tower()` 完成**，这条信号只用于显示，P2 不再监听它加费（否则会退两次） |
| `base_lost` | `base_id: int` | P1 | P2、P3 | 一处基地被摧毁 |

### 3.3 牌与商店

| 信号 | 参数 | 谁发 | 谁听 | 时机 |
| --- | --- | --- | --- | --- |
| `card_added` | `card_id: StringName` | P2 | P3 | 获得一张牌（买牌 / 起始牌组） |
| `card_removed` | `card_id: StringName, refund: int` | P2 | P3 | 卖掉或打出并消耗一张牌 |
| `deck_changed` | `cards: Array[StringName]` | P2 | P3 | 牌组整体变化后（含装配完成） |
| `tower_unlocked` | `tower_type: StringName` | P2 | P1、P3 | 塔牌生效、新塔型可用 |
| `shop_opened` | `station_index: int` | P2 | P3 | 商店开张、陈列已生成 |
| `shop_closed` | — | P2 / P3 | P2、P3 | 离开商店；P2 收到后进下一关 |
| `shop_offer_changed` | `offers: Array[Dictionary]` | P2 | P3 | 陈列首次生成或重置后 |
| `purchase_failed` | `reason: StringName, cost: int, balance: int` | P2 | P3 | 代币不足 / 槽位已售出 / 重复购买 |
| `upgrade_purchased` | `upgrade_id: StringName, tier: int` | P2 | P1、P3 | 两档升级之一购买成功 |

### 3.4 技能牌（P2 发请求，P1 施加）

| 信号 | 参数 | 谁发 | 谁听 | 时机 |
| --- | --- | --- | --- | --- |
| `tower_skill_requested` | `card_id: StringName, tower_id: int` | P2 | P1 | 技能牌拖到塔上且合法性由 P2 预检通过 |
| `cell_skill_requested` | `card_id: StringName, cell: Vector2i` | P2 | P1 | 地块技能落到格子；格子占用由 P1 校验 |
| `skill_request_rejected` | `card_id: StringName, reason: StringName` | P1 / P2 | P2、P3 | 目标非法，牌退回。P2 自己预检失败（例如对 B 塔用加攻击力）也会发这一条，所以收到时先判断牌是否还在手里，否则会出现一张变两张 |

## 4. 对外接口（P1 / P3 怎么用我）

```gdscript
# ── P1：建造 ────────────────────────────────────────────
# 建造前扣费。返回 false 表示余额不足，不要建塔。
if not Fee.try_spend(tower_cost, &"build"):
    return

# ── P1：拆塔 ────────────────────────────────────────────
# 退款由 P2 算（比例是 P2 的数据，P1 不该知道），拿到返回值后再发信号。
var refund := Fee.refund_tower(&"A")
SignalBus.tower_sold.emit(tower_id, refund)

# ── P1：击杀 / 基地 ─────────────────────────────────────
# 击杀发 enemy_killed(enemy_id, reward)；reward 传 0 时 P2 按 economy.json 兜底 +50。
# 基地被撞发 base_lost(base_id)，P2 扣 1 点基地点数（占位规则）。
# 注意：P1 不要自己加费、不要自己改 tokens / station_index / base_points。

# ── P1：本关开始与结束 ──────────────────────────────────
# 战斗场景 _ready 里调用一次，本关状态才就位（费用重置、产费启动、基地点数刷出）。
Settlement.begin_current_station()

# 本关结束时发（判定在 P1，结算在 P2）。
SignalBus.station_cleared.emit(GameState.station_index)
SignalBus.station_failed.emit(GameState.station_index)

# ── P1：施加技能牌效果 ──────────────────────────────────
# 监听 tower_skill_requested / cell_skill_requested，从 data/cards/cards.json 读数值施加。
# 目标非法（格子里有塔、塔已不存在等）时发 skill_request_rejected，P2 会把牌退回手牌。
SignalBus.skill_request_rejected.emit(card_id, &"occupied")

# ── P3：开局、商店、界面 ────────────────────────────────
Settlement.start_run(deck_id)          # 选完牌组；跳过选择传 &""
Shop.open_shop(GameState.station_index) # 商店场景 _ready 调一次
Shop.buy_tower_card(&"tower_B")
Shop.buy_skill_card(&"skill_attack_up")
Shop.buy_upgrade(&"damage")
Shop.reroll()
Shop.sell_card(&"skill_repair")
Shop.close_shop()                      # P2 收到后推进到下一关

# 界面一律只读 GameState + 监听信号；价格用 Shop.get_price()，不要自己乘系数。
```

## 5. `data/` 文件清单

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `data/towers/towers.json` | 三种塔的攻击、生命、间隔、造价、范围 | 已有，v2.0 |
| `data/enemies/enemies.json` | 三种敌人的攻击、生命、间隔、半径、速度、奖励 | 已有，v2.0 |
| `data/waves/*.json` | 波次结构（P1 读，P2 填数值） | 已有 wave_01 |
| `data/economy.json` | 初始费用、产费节奏、拆塔比例、代币结算、各关基地点数 | 本次新增 |
| `data/cards/cards.json` | 3 张塔牌 + 6 张技能牌（4 塔技能 + 2 地块技能） | 本次新增 |
| `data/shop/shop.json` | 陈列槽位、重置费用、涨价曲线、两档升级 | 本次新增 |
| `data/start_decks/index.json` | 三套起始牌组 + 跳过选项 | 本次新增 |

单位约定沿用 `data/README.md`：格边长 30 单位，范围用格数，速度用格/秒，时间用秒。

## 6. 数值表（照抄策划案，代码里不写死）

### 6.1 三种塔（`data/towers/towers.json`）

| 塔 | 攻击力 | 生命值 | 攻击间隔 | 造价 | 基础范围 |
| --- | --- | --- | --- | --- | --- |
| A 直线输出 | 100 | 1000 | 1 秒 | 100 | 沿朝向覆盖整条单元格射线 |
| B 阻挡 | 0 | 5000 | 10 秒 | 75 | 自身所在格 |
| C 范围输出 | 1（特殊伤害 350） | 1250 | 3 秒 | 150 | 以自身格为中心 3×3 |

### 6.2 三种敌人（`data/enemies/enemies.json`）

| 敌人 | 攻击力 | 生命值 | 攻击间隔 | 攻击半径 | 移动速度 | 击杀奖励 |
| --- | --- | --- | --- | --- | --- | --- |
| A 普通 | 100 | 700 | 1.5 秒 | 1 格 | 1 格/秒 | 50 |
| B 远程 | 100 | 500 | 2 秒 | 3 格 | 1 格/秒 | 50 |
| C 隐身 | 75 | 700 | 1.5 秒 | 1 格 | 0.5 格/秒 | 50 |

### 6.3 塔技能牌（拖到塔上）

| 牌 | 合法目标 | 效果 | 持续 |
| --- | --- | --- | --- |
| 加攻击力 | 攻击力 ≥ 1，否则原路退回不生效 | 攻击力 ×1.3：A 100→130；C 面板仍 1、特殊伤害 350→455 | 25 秒 |
| 加攻击范围 | 攻击力 ≥ 1 | A 前向范围 1 格宽→3 格宽（30→90 单位），中心线与朝向不变；C 3×3→4×4 | 待定（占位 25 秒） |
| 狂暴模式 | 攻击力 ≥ 1，否则退回并取消使用 | 攻击间隔 ×0.5：A 1→0.5 秒，C 3→1.5 秒；无目标也按节奏挥空 | 15 秒 |
| 修理 | 任意存活塔 | 每 0.25 秒回 25 点，持续 7 秒，最多 28 次共 700 点；回到初始生命值或上限即停 | 7 秒 |

### 6.4 地块技能牌（拖到格子）

| 牌 | 落点限制 | 效果 | 持续 |
| --- | --- | --- | --- |
| 冰冻 | 格内不能有塔 | 经过该格的敌人移速减半；离开格子后仍保留减速，直至死亡 | 30 秒 |
| 毒气（待调整） | 无 | 以落点为中心 3×3，范围内敌我双方每秒失去 100 点生命，离开即停 | 10 秒 |

### 6.5 商店

| 项 | 规则 | 数值 |
| --- | --- | --- |
| 陈列 | 3 张塔牌 + 2 张技能牌 | 槽位数定稿 |
| 技能牌售价 | 一律 | 50 代币（暂定） |
| 塔牌售价 | 策划案未给 | 占位：A 100 / B 75 / C 150（= 建造费用） |
| 两档升级 | 全局增益，第二档更贵 | 占位：火力 60 / 130；产能 50 / 110 |
| 重置商店 | 付费 | 占位：首次 20，每次 +10，进新关重置 |
| 出售卡牌 | 返还 | 占位：售价的 50% |
| 涨价 | 第二大关起 | 占位：每关 +15% |

**塔牌槽的特殊规则**：塔牌的效果是「解锁塔型」，所以**已解锁的塔型不再上架**。后果是——
选了「塔组」开局（A/B/C 全解锁）时，商店的 3 个塔牌槽会是空的；选「技能组」或「跳过」开局时才有 B、C 可买。
P3 画面板时把空槽画成空位即可，不要补货。

## 6.6 已实现（2026-11-28，分支 `feat/p2-economy`）

| 文件 | 内容 | 验证 |
| --- | --- | --- |
| `scripts/core/json_config.gd` | `data/` 下 JSON 的统一读取器（带缓存与类型转换） | 通过 |
| `scripts/core/game_state.gd` | 13 个字段 + 写入方法，写后广播 | 通过 |
| `scripts/core/signal_bus.gd` | 27 条信号，冻结 v1 | 通过 |
| `scripts/economy/fee_system.gd` | 扣费、击杀奖励、拆塔退款、基地定时产费、产能升级加成 | 通过 |
| `scripts/economy/settlement.gd` | 开一局、进入本关、基地掉点、代币结算、推进关卡、重复结算防护 | 通过 |
| `scripts/economy/shop.gd` | 陈列、买卖、重置、两档升级、涨价 | 通过 |
| `scripts/cards/card_db.gd` | 牌库、起始牌组、技能牌合法性预检与请求 | 通过 |
| `data/economy.json`、`data/cards/cards.json`、`data/shop/shop.json`、`data/start_decks/index.json` | 全部占位数值 | 通过 |

回归方式：工程里有 20 组冒烟断言（扣费、退款、结算、重复结算、商店买卖、重置、升级、售卖、技能牌预检与退回、跳过牌组、推进关卡），
在 `feat/p2-economy` 分支上跑 `godot --headless --path . res://.tmp/smoke.tscn` 全绿。该测试脚本不入库。

## 7. 待定项（拍板前不许自己填死）

| 项 | 影响 | 我的占位 |
| --- | --- | --- |
| 拆塔返还比例 | `sell_refund_ratio` | 50% |
| 每小关初始费用 | `initial_fee` | 100 |
| 基地产费节奏 | `passive_income` | 每 3 秒 25 |
| 代币结算公式 | `settlement` | 通关基础 30 + 剩余点数 ×0.05 |
| 各关基地点数与基地数量 | `stations` | 20/25/30/35/40，基地数 1→2 |
| 塔牌售价 | `cards.json` | 同建造费用 |
| 两档升级的具体增益与价格 | `shop.json > upgrades` | 见 6.5 |
| 加攻击范围的持续时间与 4×4 方阵偏移 | `cards.json` | 25 秒，居中 |
| 毒气是否敌我同伤、是否保留 | `cards.json` | 按策划案：同伤、保留 |
| 隐身敌人面对多塔的选择顺序 | P1 的索敌 | 不归我 |

**规则**：以上任何一项被拍板后，只改 `data/` 里的值 + 本表的状态，不改代码结构。

## 8. 里程碑（对齐分工方案的 D4 / D5 / D8 硬卡点）

| 里程碑 | 日期 | P2 交付 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| D1 | 11-28 | 契约冻结：`GameState` 13 字段、`SignalBus` 27 条信号、本文件、`data/` 四份配置、六个脚本 | 冒烟 20 组全绿；P1、P3 能按表编程 | **已完成**，待 PR 合入 `main` |
| D2 | 11-29 | `fee_system` 接上 P1 的真实建造 / 拆塔链路，复核占位数值 | 建塔扣费、余额不足被拒、拆塔退回 50% | 代码就绪，等 P1 调用 |
| D3 | 11-30 | 商店业务逻辑接上 P3 的商店场景 | 塔牌 / 技能牌能买，代币正确扣减 | 代码就绪，等 P3 场景 |
| D4 | 12-01 | 与全队对齐「能打一关」 | 选牌组进关卡、建塔、击杀得费、基地掉点、波次推进、胜利结算，全程无报错 | 待联调 |
| D5 | 12-02 | 「胜利 → 商店 → 再胜」闭环。**验收时用技能组或跳开局**，塔组开局塔牌槽是空的 | 完整循环跑通 | 待联调 |
| D6 | 12-03 | 六张技能牌效果与 P1 对接 | 四张塔技能 + 两张地块技能生效 | 待 P1 |
| D7 | 12-04 | 三套起始牌组定稿、数值调整 | 三套牌组各能开局 | 待调 |
| D8 | 12-05 | 功能冻结前修缺陷，配合 P3 出包 | 连续三关不崩 | 待 |

## 9. 每次提交前的自查四问

1. 写状态后有没有**立刻发信号**？
2. 有没有把数值**写死在代码里**（应该在 `data/`）？
3. 有没有**跨轨**（用代币补费用、用费用买牌）？
4. 有没有**改已冻结的信号名或字段名**？
