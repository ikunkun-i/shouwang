extends Node
## 事件总线：跨模块通信的唯一通道。
##
## 冻结版本：v1 / 2026-11-28（P2 定稿）。
## 规则：**只增不改**。可以新增信号，禁止改名、禁止改参数类型、禁止删除。
## 改名或删参数等于全队返工；确需变更先在群里说，并同步改 docs/p2-scope.md 第 3 节。
##
## 命名约定：
## - 过去式（`xxx_changed` / `xxx_gained`）= 事实已发生，监听方刷新即可
## - `xxx_requested` = P2 请求 P1 施加效果，P1 判定合法性后执行
## - `xxx_failed` = 操作被拒，理由放在 `reason` 里，值用 StringName 常量

# ============================================================
# 一、资源与进度（P2 发）
# ============================================================

## 费用数值发生变化。任何加减之后都必须发，包括 0 的变化。
signal fee_changed(value: int)
## 费用增加。reason 取值：&"passive"（基地产费）、&"kill"（击杀奖励）、&"refund"（拆塔退款）。
signal fee_gained(amount: int, reason: StringName)
## 费用减少。reason 取值：&"build"（建造）、&"upgrade"（全局升级）。
signal fee_spent(amount: int, reason: StringName)
## 费用不足，操作被拒。P3 据此弹提示，P1 据此不建塔。
signal fee_insufficient(required: int, current: int)
## 代币余额发生变化。
signal tokens_changed(value: int)
## 代币不足，购买被拒。与 fee_insufficient 分开，避免两条资源轨道串味。
signal purchase_failed(reason: StringName, cost: int, balance: int)

## 基地点数变化。total 是本关初始总点数，P3 血条按 value / total 画。
signal base_points_changed(value: int, total: int)
## 进入某一小关，状态已就绪。P1 收到后才开始投放第一波。
signal station_started(station_index: int, base_points: int)
## 本关胜利并完成结算。tokens_gained 为本关实际到账代币。
signal station_cleared(station_index: int)
## 本关失败（P1 判定）。P2 收到后结算并让流程回到失败界面。
signal station_failed(station_index: int)
## 代币结算完成。P3 结算面板读这一条显示「本关获得 X 代币」。
signal station_settled(station_index: int, tokens_gained: int)
## 新开一局、牌组装配完成。P3 收到后才切进战斗场景。
signal run_started()

# ============================================================
# 二、战斗事实（P1 发，P2 只监听并结算奖惩）
# ============================================================

## 新一波敌人开始投放。
signal wave_started(wave_index: int)
## 敌人被击杀。reward 传 0 时 P2 按 data/enemies 里的 reward_fee 兜底。
signal enemy_killed(enemy_id: int, reward: int)
## 一座塔建造成功。扣费已在 Fee.try_spend 完成，这里只通知。
signal tower_built(tower_id: int, tower_type: StringName)
## 一座塔被拆除并退款。refund 传 0 时 P2 按 data/economy.json 的比例兜底。
signal tower_sold(tower_id: int, refund: int)
## 一处基地被摧毁。
signal base_lost(base_id: int)

# ============================================================
# 三、牌与商店（P2 发）
# ============================================================

## 获得一张牌。
signal card_added(card_id: StringName)
## 卖掉或打出并消耗一张牌。refund 为返还代币，0 表示无返还。
signal card_removed(card_id: StringName, refund: int)
## 牌组整体变化。cards 是 StringName 数组，P3 手牌区据此重画。
signal deck_changed(cards: Array)
## 塔牌生效、新塔型可用。P1 据此在建造菜单里放出该塔。
signal tower_unlocked(tower_type: StringName)
## 商店开张、陈列已生成。P3 收到后显示面板。
signal shop_opened(station_index: int)
## 离开商店进入下一关。P2 与 P3 都会发：玩家点关闭时 P3 发，买完自动关闭时 P2 发。
signal shop_closed()
## 陈列首次生成或重置后。offers 是 Dictionary 数组，结构见 data/shop/shop.json。
signal shop_offer_changed(offers: Array)
## 两档升级之一购买成功。
signal upgrade_purchased(upgrade_id: StringName, tier: int)

# ============================================================
# 四、技能牌（P2 发请求，P1 施加）
# ============================================================

## 塔技能牌拖到塔上，P2 已按 data/towers 预检攻击力门槛。
## P1 收到后施加到该塔，持续时长与数值全部读 data/cards/cards.json。
signal tower_skill_requested(card_id: StringName, tower_id: int)
## 地块技能牌落到格子。格子是否可放由 P1 校验（例如冰冻要求格内无塔）。
signal cell_skill_requested(card_id: StringName, cell: Vector2i)
## P1 判定目标非法：不消耗该牌，P2 把牌退回手牌区。
## reason 取值：&"no_target"、&"occupied"、&"invalid_kind"。
signal skill_request_rejected(card_id: StringName, reason: StringName)
