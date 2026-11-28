class_name SkillEffects
extends RefCounted
## 技能牌效果数值计算器（P2 的数值职责）。
##
## 边界：这里只算「这张牌打完之后，塔/地块的数值该变成多少」，**不碰任何节点**。
## 真正把结果写进塔、改敌人速度、扣血的是 P1；界面显示是 P3。
## 为什么数值要单独抽出来：×1.3、350→455、3×3→4×4、28 跳、每秒 100 这些数字
## 只该有一份来源（data/cards/cards.json），否则 P1 各写一遍，改数值时必然漏改一处。
##
## P1 的用法：
##   var after := SkillEffects.apply_tower_skill(card_id, {
##       "attack": stats.attack,
##       "special_damage": stats.special_damage,   # 只有 C 塔有，没有就不要传
##       "attack_interval": stats.attack_interval,
##       "range_type": "ray" / "box",
##       "ray_width": 1,
##       "box_width": 3,
##       "box_height": 3,
##   })
##   # after.attack / after.special_damage / after.attack_interval / after.duration …
##   然后把 after 里的值套到自己塔上，按 after.duration 到期还原。
##
## 地块技能：
##   SkillEffects.slow_multiplier(&"skill_freeze")       # 0.5，离开格子仍然保留
##   SkillEffects.poison_profile(&"skill_poison")        # 每秒 100、3×3、持续 10 秒
##   SkillEffects.area_offsets(&"skill_poison")          # 相对落点的 9 个格子偏移

const CARDS_PATH := "res://data/cards/cards.json"


# ============================================================
# 基础读取
# ============================================================

## 读一张牌的配置。不要在用的时候直接 load，静态方法里统一走这里。
static func _card(card_id: StringName) -> Dictionary:
	var config := JsonConfig.load_dict(CARDS_PATH)
	for key in ["tower_cards", "skill_cards"]:
		for entry in JsonConfig.get_array(config, key):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var card: Dictionary = entry
			if StringName(String(card.get("id", ""))) == card_id:
				return card
	push_warning("SkillEffects: 找不到卡牌 %s" % card_id)
	return {}


static func _effect(card_id: StringName) -> Dictionary:
	var card := _card(card_id)
	var effect: Variant = card.get("effect", {})
	return effect if typeof(effect) == TYPE_DICTIONARY else {}


## 效果持续时间（秒）。地块技能与塔技能都用 `duration`。
static func duration_of(card_id: StringName) -> float:
	return float(_card(card_id).get("duration", 0.0))


## 这张牌是不是地块技能（拖到格子上）。
static func is_cell_skill(card_id: StringName) -> bool:
	return String(_card(card_id).get("kind", "")) == "cell_skill"


# ============================================================
# 塔技能牌：各项倍率（单独取，方便界面显示说明文字）
# ============================================================

## 加攻击力的倍率（1.3 = +30%）。
static func attack_multiplier(card_id: StringName) -> float:
	var effect := _effect(card_id)
	if String(effect.get("type", "")) != "attack_multiplier":
		return 1.0
	return float(effect.get("multiplier", 1.0))


## 狂暴模式的攻击间隔倍率（0.5 = 间隔减半）。
static func interval_multiplier(card_id: StringName) -> float:
	var effect := _effect(card_id)
	if String(effect.get("type", "")) != "attack_interval_multiplier":
		return 1.0
	return float(effect.get("multiplier", 1.0))


## 狂暴期间是否「没有目标也照节奏挥空」。
static func swings_without_target(card_id: StringName) -> bool:
	return JsonConfig.get_bool(_effect(card_id), "swing_without_target", false)


## 加攻击范围后，A 塔前向射线的格宽（策划案：1 格宽 → 3 格宽，即 30 → 90 单位）。
static func ray_width_cells(card_id: StringName) -> int:
	return JsonConfig.get_int(_effect(card_id), "ray_width_cells", 0)


## 加攻击范围后，C 塔方阵的边长（策划案：3×3 → 4×4）。返回 Vector2i.ZERO 表示这张牌不改范围。
static func box_size(card_id: StringName) -> Vector2i:
	var effect := _effect(card_id)
	var width := JsonConfig.get_int(effect, "box_width_cells", 0)
	var height := JsonConfig.get_int(effect, "box_height_cells", 0)
	if width <= 0 or height <= 0:
		return Vector2i.ZERO
	return Vector2i(width, height)


# ============================================================
# 塔技能牌：一次算出打完之后的整组属性
# ============================================================

## 把一张塔技能牌作用到一组塔属性上，返回**新的**字典（不改传入的 stats）。
##
## 输入的键（缺哪个就跳过哪项，不会崩）：
##   attack            float  面板攻击力
##   special_damage    float  范围特殊伤害（只有 C 塔有）
##   attack_interval   float  攻击间隔（秒）
##   range_type        String "ray"（A）或 "box"（C）
##   ray_width         int    射线格宽
##   box_width / box_height int 方阵边长
##
## 返回：输入的全部键 + 被这张牌改掉的项 + `duration`（持续秒数）+ `card_id`。
##
## 关键口径（来自策划案）：加攻击力对 C 塔只放大「特殊范围伤害」，面板攻击力保持 1。
## 所以：stats 里带 special_damage 就按特殊伤害算，不带才按面板攻击力算。
static func apply_tower_skill(card_id: StringName, stats: Dictionary) -> Dictionary:
	var effect := _effect(card_id)
	var result := stats.duplicate(true)
	if effect.is_empty():
		result["duration"] = duration_of(card_id)
		result["card_id"] = card_id
		return result

	match String(effect.get("type", "")):
		"attack_multiplier":
			var multiplier := float(effect.get("multiplier", 1.0))
			var has_special := stats.has("special_damage")
			if has_special and bool(effect.get("apply_to_special_damage", false)):
				# C 塔：面板攻击力不动，只放大特殊伤害（350 → 455）。
				result["special_damage"] = float(stats.get("special_damage", 0.0)) * multiplier
			else:
				# A 塔：面板攻击力乘倍率（100 → 130）。
				result["attack"] = float(stats.get("attack", 0.0)) * multiplier

		"attack_interval_multiplier":
			var multiplier := float(effect.get("multiplier", 1.0))
			result["attack_interval"] = float(stats.get("attack_interval", 0.0)) * multiplier
			result["swing_without_target"] = swings_without_target(card_id)

		"range_upgrade":
			if String(stats.get("range_type", "")) == "box":
				var box := box_size(card_id)
				if box != Vector2i.ZERO:
					result["box_width"] = box.x
					result["box_height"] = box.y
			else:
				var width := ray_width_cells(card_id)
				if width > 0:
					result["ray_width"] = width

		"heal_over_time":
			result["repair"] = repair_plan(card_id)

		_:
			push_warning("SkillEffects: %s 的效果类型 %s 不是塔技能，已原样返回" % [
				card_id, effect.get("type", "?"),
			])

	result["duration"] = duration_of(card_id)
	result["card_id"] = card_id
	return result


# ============================================================
# 修理：分跳回血
# ============================================================

## 修理的完整执行计划，P1 按这个表逐跳回血。
## 返回：{tick_interval, heal_per_tick, max_ticks, total_heal, stop_at_max}
## 策划案：每 0.25 秒回 25 点，持续 7 秒，最多 28 次共 700 点；
## 回到该塔初始生命值或生命上限时停止。
static func repair_plan(card_id: StringName) -> Dictionary:
	var effect := _effect(card_id)
	if String(effect.get("type", "")) != "heal_over_time":
		return {}
	var tick_interval := float(effect.get("tick_interval", 0.25))
	var heal_per_tick := int(effect.get("heal_per_tick", 25))
	var max_ticks := int(effect.get("max_ticks", 28))
	return {
		"tick_interval": tick_interval,
		"heal_per_tick": heal_per_tick,
		"max_ticks": max_ticks,
		"total_heal": heal_per_tick * max_ticks,
		"stop_at_max": JsonConfig.get_bool(effect, "stop_at_max", true),
		"duration": duration_of(card_id),
	}


## 修理的平均每秒回血量，界面写「每秒约 X 点」时用。
static func heal_per_second(card_id: StringName) -> float:
	var plan := repair_plan(card_id)
	if plan.is_empty() or float(plan["tick_interval"]) <= 0.0:
		return 0.0
	return float(plan["heal_per_tick"]) / float(plan["tick_interval"])


# ============================================================
# 地块技能
# ============================================================

## 冰冻的减速倍率（0.5 = 移速减半）。
## persist_after_leave = true 表示离开格子后仍然保留减速，直到死亡——P1 别自己清掉。
static func slow_multiplier(card_id: StringName) -> float:
	var effect := _effect(card_id)
	if String(effect.get("type", "")) != "slow":
		return 1.0
	return float(effect.get("move_speed_multiplier", 1.0))


static func slow_persists_after_leave(card_id: StringName) -> bool:
	return JsonConfig.get_bool(_effect(card_id), "persist_after_leave", false)


## 毒气的完整参数。P1 按这个每秒结算一次伤害，离开范围就停。
## 返回：{damage_per_second, duration, affects_friend_and_foe, stop_on_leave}
static func poison_profile(card_id: StringName) -> Dictionary:
	var effect := _effect(card_id)
	if String(effect.get("type", "")) != "damage_over_time":
		return {}
	return {
		"damage_per_second": float(effect.get("damage_per_second", 0.0)),
		"duration": duration_of(card_id),
		"affects_friend_and_foe": JsonConfig.get_bool(effect, "affects_friend_and_foe", false),
		"stop_on_leave": JsonConfig.get_bool(effect, "stop_on_leave", true),
	}


## 地块技能覆盖的格子，返回**相对落点**的偏移数组。
## 冰冻是单格 → [Vector2i(0,0)]；毒气是 3×3 → 9 个偏移（含中心）。
static func area_offsets(card_id: StringName) -> Array:
	var card := _card(card_id)
	var area: Variant = card.get("area", {})
	if typeof(area) != TYPE_DICTIONARY:
		return [Vector2i.ZERO]
	var area_dict: Dictionary = area
	if String(area_dict.get("shape", "single")) != "box":
		return [Vector2i.ZERO]

	var width := JsonConfig.get_int(area_dict, "width", 1)
	var height := JsonConfig.get_int(area_dict, "height", 1)
	# 居中：3×3 → x/y 各取 -1、0、1。偶数宽高时多出来的一格偏向左上，不影响当前牌面。
	var start_x := -int((width - 1) / 2)
	var start_y := -int((height - 1) / 2)
	var offsets: Array = []
	for y in height:
		for x in width:
			offsets.append(Vector2i(start_x + x, start_y + y))
	return offsets


# ============================================================
# 叠加规则
# ============================================================

## 同类增益重复施加时的合成规则：**取更强的那个，不叠乘**（占位规则，待拍板）。
## 理由：如果 1.3 叠成 1.69，玩家连开两张就能滚雪球，而策划案只写了单张效果。
## 拍板后只改这一个函数。
static func combine_multiplier(current: float, incoming: float) -> float:
	return maxf(current, incoming)
