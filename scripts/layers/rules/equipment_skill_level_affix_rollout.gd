class_name EquipmentSkillLevelAffixRollout
extends RefCounted

## Project-owned generation contract. The default policy is inert until the
## equipment IDs, gate and weights are explicitly authored. It never changes
## the historical item.drop.affix.rules.v3 table.

const CONTRACT_ID := "equipment.skill_level_affix_rollout.v1"
const POLICY_PATH := "res://assets/data/equipment_skill_level_affix_rollout_v1.json"


static func default_policy() -> Dictionary:
	var file := FileAccess.open(POLICY_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func generate(item_id: int, gate_roll: int, choice_roll: int, policy: Dictionary = {}) -> Dictionary:
	var selected := default_policy() if policy.is_empty() else policy
	if str(selected.get("contract_id", "")) != CONTRACT_ID:
		return {"generated": false, "reason": "invalid_contract"}
	if not bool(selected.get("enabled", false)):
		return {"generated": false, "reason": "rollout_disabled"}
	var item_ids: Variant = selected.get("eligible_item_ids", [])
	if not item_ids is Array or not (item_ids as Array).has(item_id):
		return {"generated": false, "reason": "ineligible_item"}
	var gate: Variant = selected.get("gate", {})
	if not gate is Dictionary:
		return {"generated": false, "reason": "invalid_gate"}
	var numerator := int((gate as Dictionary).get("numerator", 0))
	var denominator := int((gate as Dictionary).get("denominator", 0))
	if numerator <= 0 or denominator <= 0 or numerator > denominator or gate_roll < 0 or gate_roll >= denominator:
		return {"generated": false, "reason": "invalid_gate"}
	if gate_roll >= numerator:
		return {"generated": false, "reason": "gate_miss"}
	var choices: Variant = selected.get("weighted_affixes", [])
	if not choices is Array or (choices as Array).is_empty():
		return {"generated": false, "reason": "missing_weights"}
	var total_weight := 0
	for raw: Variant in choices:
		if not raw is Dictionary:
			return {"generated": false, "reason": "invalid_affix"}
		var entry := raw as Dictionary
		if int(entry.get("weight", 0)) <= 0 or int(entry.get("value", 0)) <= 0 or not _allowed_scope(str(entry.get("scope", ""))):
			return {"generated": false, "reason": "invalid_affix"}
		total_weight += int(entry.weight)
	if choice_roll < 0 or choice_roll >= total_weight:
		return {"generated": false, "reason": "invalid_choice_roll"}
	var cursor := choice_roll
	for raw: Variant in choices:
		var entry := raw as Dictionary
		cursor -= int(entry.weight)
		if cursor < 0:
			return {
				"generated": true,
				"modifier": {"stat": "skill_level", "op": "add", "scope": str(entry.scope), "value": int(entry.value)},
			}
	return {"generated": false, "reason": "invalid_choice_roll"}


static func _allowed_scope(scope: String) -> bool:
	if scope == "all" or scope in ["profession:warrior", "profession:wizard", "profession:taoist"]:
		return true
	return scope.begins_with("skill:") and SkillRankExtensionPolicy.can_extend(scope.trim_prefix("skill:"))
