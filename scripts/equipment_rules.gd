class_name EquipmentRules
extends RefCounted

const NEED_LEVEL := 0
const NEED_ATTACK := 1
const NEED_MAGIC := 2
const NEED_TAO := 3
const SUPPORTED_NEEDS: Array[int] = [NEED_LEVEL, NEED_ATTACK, NEED_MAGIC, NEED_TAO]
const BLESSING_UNLUCKY_RATE := 20
const LUCK_POINT_1 := 1
const LUCK_POINT_2 := 3
const LUCK_POINT_3 := 7
const LUCK_POINT_2_RATE := 6
const LUCK_POINT_3_RATE := 40
const MAX_WEAPON_CURSE := 10
const ACTOR_VISUAL_SORT_CONTRACT_ID := "equipment_actor_visual_sort_unit_v2"
const MALE_WORLD_HELMET_EXTENSION_CONTRACT_ID := "equipment.world_helmet.male.extension.v1"
const ACTOR_VISUAL_BODY_LAYER := &"body_and_dress"
const ACTOR_VISUAL_WEAPON_LAYER := &"weapon"
const ACTOR_VISUAL_HELMET_LAYER := &"helmet"
const SPECIAL_EFFECTS_BY_NAME := {
	"隐身戒指": {"id": "stealth", "label": "隐身", "source_code": 111, "runtime": true, "confidence": "B"},
	"传送戒指": {"id": "teleport", "label": "安全传送", "source_code": 112, "runtime": true, "confidence": "B"},
	"麻痹戒指": {"id": "paralysis", "label": "近战麻痹", "source_code": 113, "runtime": true, "confidence": "B"},
	"复活戒指": {"id": "revival", "label": "60秒复活", "source_code": 114, "runtime": true, "confidence": "B"},
	"火焰戒指": {"id": "flame_skill", "label": "火球技能", "source_code": 115, "runtime": true, "confidence": "B"},
	"防御戒指": {"id": "recovery_skill", "label": "治愈技能", "source_code": 116, "runtime": true, "confidence": "B"},
	"护身戒指": {"id": "magic_shield", "label": "魔法值抵伤", "source_code": 118, "runtime": true, "confidence": "B"},
	"超负载戒指": {"id": "double_weight", "label": "负重上限翻倍", "source_code": 119, "runtime": true, "confidence": "B"},
}
const SET_PIECES_BY_NAME := {
	"魔血项链": {"set": "magic_blood", "piece": "necklace", "power": 25},
	"魔血手镯": {"set": "magic_blood", "piece": "bracelet", "power": 25},
	"魔血戒指": {"set": "magic_blood", "piece": "ring", "power": 25},
	"虹魔项链": {"set": "rainbow_demon", "piece": "necklace", "power": 4},
	"虹魔手镯": {"set": "rainbow_demon", "piece": "bracelet", "power": 3},
	"虹魔戒指": {"set": "rainbow_demon", "piece": "ring", "power": 2},
}


static func weapon_draws_behind_actor(direction_row: int) -> bool:
	return posmod(direction_row, 8) in [7, 0, 1]


static func actor_visual_layer_order(direction_row: int) -> Array[StringName]:
	# Wall fronts and actors only Y-sort when their final z_index matches. Keep
	# every wear layer on Z=0 and express classic equipment overlap by sibling
	# tree order inside the actor subtree.
	if weapon_draws_behind_actor(direction_row):
		return [
			ACTOR_VISUAL_WEAPON_LAYER,
			ACTOR_VISUAL_BODY_LAYER,
			ACTOR_VISUAL_HELMET_LAYER,
		]
	return [
		ACTOR_VISUAL_BODY_LAYER,
		ACTOR_VISUAL_WEAPON_LAYER,
		ACTOR_VISUAL_HELMET_LAYER,
	]


static func max_wear_weight(profession: String, level: int) -> int:
	var safe_level := maxi(1, level)
	match profession:
		"法师": return 15 + int(round((safe_level / 100.0) * safe_level))
		"道士": return 15 + int(round((safe_level / 50.0) * safe_level))
		_: return 15 + int(round((safe_level / 20.0) * safe_level))


static func max_hand_weight(profession: String, level: int) -> int:
	var safe_level := maxi(1, level)
	match profession:
		"法师": return 12 + int(round((safe_level / 90.0) * safe_level))
		"道士": return 12 + int(round((safe_level / 42.0) * safe_level))
		_: return 12 + int(round((safe_level / 13.0) * safe_level))


static func requirement_for(item: Dictionary) -> Dictionary:
	if item.has("serviceNeed") and item.has("serviceNeedLevel"):
		return {
			"type": int(item.get("serviceNeed", NEED_LEVEL)),
			"value": maxi(0, int(item.get("serviceNeedLevel", 0))),
			"source": "服务端StdItems",
			"confidence": "A",
		}
	for field: String in ["reqAttack", "reqMagic", "reqTao"]:
		var value: Variant = item.get(field, null)
		if value == null or int(value) <= 0:
			continue
		var need_type: int = int({"reqAttack": NEED_ATTACK, "reqMagic": NEED_MAGIC, "reqTao": NEED_TAO}[field])
		return {"type": need_type, "value": int(value), "source": "现有目录候选字段", "confidence": str(item.get("confidence", "B"))}
	return {
		"type": NEED_LEVEL,
		"value": maxi(0, int(item.get("reqLevel", 0) if item.get("reqLevel", null) != null else 0)),
		"source": "现有目录候选字段",
		"confidence": str(item.get("confidence", "B")),
	}


static func requirement_error(item: Dictionary, level: int, stats: Dictionary) -> String:
	var requirement := requirement_for(item)
	var need_type := int(requirement.get("type", NEED_LEVEL))
	var required := int(requirement.get("value", 0))
	match need_type:
		NEED_LEVEL:
			return "" if level >= required else "需要等级%d" % required
		NEED_ATTACK:
			return "" if int(stats.get("attack_max", 0)) >= required else "需要攻击%d" % required
		NEED_MAGIC:
			return "" if int(stats.get("magic_max", 0)) >= required else "需要魔法%d" % required
		NEED_TAO:
			return "" if int(stats.get("tao_max", 0)) >= required else "需要道术%d" % required
		_:
			return "尚未支持服务端装备需求类型%d" % need_type


static func requirement_label(item: Dictionary) -> String:
	var requirement := requirement_for(item)
	var labels := {NEED_LEVEL: "等级", NEED_ATTACK: "攻击", NEED_MAGIC: "魔法", NEED_TAO: "道术"}
	var need_type := int(requirement.get("type", NEED_LEVEL))
	var label := str(labels.get(need_type, "类型%d" % need_type))
	return "%s%d（%s/%s）" % [label, int(requirement.get("value", 0)), str(requirement.get("source", "未知来源")), str(requirement.get("confidence", "?"))]


static func reference_price(item: Dictionary) -> int:
	if int(item.get("servicePrice", 0)) > 0:
		return int(item.get("servicePrice", 0))
	if int(item.get("price", 0)) > 0:
		return int(item.get("price", 0))
	var requirement := requirement_for(item)
	var required := maxi(1, int(requirement.get("value", 1)))
	return maxi(50, required * required * 3)


static func repair_cost(item: Dictionary, durability: int, max_durability: int) -> int:
	var maximum := maxi(1, max_durability)
	var missing := maximum - clampi(durability, 0, maximum)
	if missing <= 0:
		return 0
	# ObjNpc.pas: Round(nPrice div 3 / DuraMax * missing). 本项目持久已换算为显示单位。
	return maxi(0, int(round(float(reference_price(item) / 3) / maximum * missing)))


static func blessing_outcome(luck: int, curse: int, attack_min: int, attack_max: int, unlucky_roll: int, success_roll: int) -> Dictionary:
	var next_luck := clampi(luck, 0, LUCK_POINT_3)
	var next_curse := clampi(curse, 0, MAX_WEAPON_CURSE)
	if unlucky_roll == 1:
		if next_luck > 0:
			next_luck -= 1
		elif next_curse < MAX_WEAPON_CURSE:
			next_curse += 1
		return {"result": "cursed", "luck": next_luck, "curse": next_curse}
	if next_curse > 0:
		next_curse -= 1
		return {"result": "improved", "luck": next_luck, "curse": next_curse}
	if next_luck < LUCK_POINT_1:
		return {"result": "improved", "luck": next_luck + 1, "curse": next_curse}
	var span_factor := int(absi(attack_max - attack_min) / 5)
	if next_luck < LUCK_POINT_2:
		var denominator := span_factor + LUCK_POINT_2_RATE
		if denominator > 1 and success_roll == 1:
			return {"result": "improved", "luck": next_luck + 1, "curse": next_curse}
	elif next_luck < LUCK_POINT_3:
		var denominator := span_factor * LUCK_POINT_3_RATE
		if denominator > 1 and success_roll == 1:
			return {"result": "improved", "luck": next_luck + 1, "curse": next_curse}
	return {"result": "ineffective", "luck": next_luck, "curse": next_curse}


static func blessing_success_denominator(luck: int, attack_min: int, attack_max: int) -> int:
	var span_factor := int(absi(attack_max - attack_min) / 5)
	if luck < LUCK_POINT_1:
		return 1
	if luck < LUCK_POINT_2:
		return span_factor + LUCK_POINT_2_RATE
	if luck < LUCK_POINT_3:
		return span_factor * LUCK_POINT_3_RATE
	return 0


static func weapon_luck_label(instance: Dictionary) -> String:
	var luck := int(instance.get("weapon_luck", 0))
	var curse := int(instance.get("weapon_curse", 0))
	if luck > 0:
		return "幸运+%d" % luck
	if curse > 0:
		return "诅咒+%d" % curse
	return "幸运0"


static func special_effect_for(item: Dictionary) -> Dictionary:
	if item.has("specialEffect"):
		var configured: Variant = item.get("specialEffect", {})
		if not configured is Dictionary or configured.is_empty():
			return {}
		var result: Dictionary = configured.duplicate(true)
		result["mapping_source"] = str(item.get("customizationSource", "装备数据字段specialEffect"))
		return result
	if item.has("serviceAniCount"):
		var code := int(item.get("serviceAniCount", 0))
		for effect: Dictionary in SPECIAL_EFFECTS_BY_NAME.values():
			if int(effect.get("source_code", -1)) == code:
				var exact := effect.duplicate(true)
				exact["confidence"] = "A"
				exact["mapping_source"] = "服务端StdItems.AniCount"
				return exact
	var by_name: Dictionary = SPECIAL_EFFECTS_BY_NAME.get(str(item.get("name", "")), {})
	if by_name.is_empty():
		var set_piece := set_piece_for(item)
		if set_piece.is_empty():
			return {}
		return {
			"id": "%s_piece" % set_piece.get("set", "set"),
			"label": "%s组件" % ("魔血" if set_piece.get("set", "") == "magic_blood" else "虹魔"),
			"runtime": true,
			"confidence": "B",
			"mapping_source": "服务端Shape公式 + 项目候选AniCount",
		}
	var candidate := by_name.duplicate(true)
	candidate["mapping_source"] = "装备名称候选·待StdItems.AniCount复核"
	return candidate


static func set_piece_for(item: Dictionary) -> Dictionary:
	if item.has("setPiece"):
		var configured: Variant = item.get("setPiece", {})
		if not configured is Dictionary or configured.is_empty():
			return {}
		var configured_result: Dictionary = configured.duplicate(true)
		configured_result["power_source"] = str(item.get("customizationSource", "装备数据字段setPiece"))
		return configured_result
	var piece: Dictionary = SET_PIECES_BY_NAME.get(str(item.get("name", "")), {})
	if piece.is_empty():
		return {}
	var result := piece.duplicate(true)
	result["power_source"] = "serviceAniCount" if item.has("serviceAniCount") else "项目候选·待StdItems.AniCount替换"
	if item.has("serviceAniCount"):
		result["power"] = int(item.get("serviceAniCount", result.get("power", 0)))
	return result


static func effective_profession(item: Dictionary) -> String:
	if not set_piece_for(item).is_empty():
		return "通用"
	return str(item.get("profession", "通用"))


static func special_action_label(effect_id: String) -> String:
	return {"teleport": "传送", "flame_skill": "火球", "recovery_skill": "治愈"}.get(effect_id, effect_id)


static func paralysis_succeeds(target_anti_poison: int, roll: int) -> bool:
	var denominator := maxi(1, target_anti_poison + 5)
	return clampi(roll, 0, denominator - 1) == 0


static func critical_succeeds(chance: float, roll: float) -> bool:
	return clampf(roll, 0.0, 0.999999) < clampf(chance, 0.0, 1.0)


static func critical_damage(damage: int, multiplier: float) -> int:
	return maxi(1, int(round(float(maxi(1, damage)) * maxf(1.0, multiplier))))


static func required_gender(item: Dictionary) -> String:
	var std_mode := int(item.get("serviceStdMode", -1))
	if std_mode == 10:
		return "男"
	if std_mode == 11:
		return "女"
	var name := str(item.get("name", ""))
	if name.ends_with("(男)"):
		return "男"
	if name.ends_with("(女)"):
		return "女"
	return ""


static func enrich_catalog_record(item: Dictionary) -> Dictionary:
	var result := item.duplicate(true)
	result["serviceRequirement"] = requirement_for(result)
	result["fieldSemanticsSource"] = "M2Server/Common/Grobal2.pas:TStdItem + M2Server/ObjBase.pas:CanUseItem"
	result["concreteStdItemsStatus"] = "已接入" if result.has("serviceNeed") else "数据库缺失·保留候选值"
	result["referencePrice"] = reference_price(result)
	result["referencePriceSource"] = "服务端StdItems.Price" if result.has("servicePrice") else "项目价格候选·待StdItems.Price替换"
	var special := special_effect_for(result)
	if not special.is_empty():
		result["specialEffect"] = special
	return result
