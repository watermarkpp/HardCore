class_name SkillLoadoutRules
extends RefCounted

const ASSIGNMENT_CONTRACT_ID := "gameplay.skill.quick_slot_assignment.v1"
const UI_ASSIGNMENT_CONTRACT_IDS: Array[String] = [
	"ui.skill.button_assignment.v2",
	"ui.skill.quick_slot_assignment.v1",
]
const SLOT_GROUP_CENTER := "center"
const SLOT_GROUP_ATTACK_RING := "attack_ring"


static func assign_quick_slot(current_slots: Array[String], learned_skills: Dictionary, request: Dictionary) -> Dictionary:
	var source_contract_id := str(request.get("contract_id", ""))
	if source_contract_id not in UI_ASSIGNMENT_CONTRACT_IDS:
		return _failure("unsupported_contract", current_slots, request)
	var slot_group := str(request.get("slot_group", SLOT_GROUP_ATTACK_RING))
	if slot_group not in [SLOT_GROUP_CENTER, SLOT_GROUP_ATTACK_RING]:
		return _failure("unsupported_slot_group", current_slots, request)
	var slot_index := int(request.get("slot_index", -1))
	if slot_index < 0 or slot_index >= current_slots.size():
		return _failure("slot_out_of_range", current_slots, request)
	var skill_name := str(request.get("skill_name", ""))
	var skill_id := str(request.get("skill_id", ""))
	if skill_name.is_empty() and not skill_id.is_empty():
		skill_name = ProfessionRules.skill_display_name(skill_id)
	if skill_id.is_empty() and not skill_name.is_empty():
		skill_id = ProfessionRules.skill_id(skill_name)
	if skill_name.is_empty() or skill_id.is_empty():
		return _failure("unknown_skill", current_slots, request)
	if not learned_skills.has(skill_name):
		return _failure("skill_not_learned", current_slots, request)
	var next_slots := current_slots.duplicate()
	var previous_skill_name: String = str(next_slots[slot_index])
	next_slots[slot_index] = skill_name
	return {
		"ok": true,
		"changed": previous_skill_name != skill_name,
		"reason": "assigned",
		"slots": next_slots,
		"change": {
			"contract_id": ASSIGNMENT_CONTRACT_ID,
			"source_contract_id": source_contract_id,
			"slot_group": slot_group,
			"slot_index": slot_index,
			"slot_id": "player.quick_skill.%d" % (slot_index + 1),
			"requested_slot_id": str(request.get("slot_id", "")),
			"skill_id": skill_id,
			"skill_name": skill_name,
			"previous_skill_name": previous_skill_name,
		},
	}


static func _failure(reason: String, current_slots: Array[String], request: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"reason": reason,
		"slots": current_slots.duplicate(),
		"change": {
			"contract_id": ASSIGNMENT_CONTRACT_ID,
			"source_contract_id": str(request.get("contract_id", "")),
		},
	}
