class_name SkillLoadoutRules
extends RefCounted

const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")

const ASSIGNMENT_CONTRACT_ID := "gameplay.skill.quick_slot_assignment.v1"
const BUTTON_ASSIGNMENTS_CONTRACT_ID := "gameplay.skill.button_assignments.v3"
const LEGACY_BUTTON_ASSIGNMENTS_CONTRACT_ID := "gameplay.skill.button_assignments.v2"
const UI_ASSIGNMENT_CONTRACT_IDS: Array[String] = [
	"ui.skill.button_assignment.v3",
	"ui.skill.button_assignment.v2",
	"ui.skill.quick_slot_assignment.v1",
]
const SLOT_GROUP_CENTER := "center"
const SLOT_GROUP_ATTACK := "attack"
const SLOT_GROUP_ATTACK_RING := "attack_ring"
const CENTER_SLOT_COUNT := 4
const ATTACK_SLOT_COUNT := 1
const ATTACK_RING_SLOT_COUNT := 6


static func normalize_assignments(value: Variant, legacy_center: Array = []) -> Dictionary:
	var attack := _normalized_slot_array([], ATTACK_SLOT_COUNT)
	var attack_ring := _normalized_slot_array([], ATTACK_RING_SLOT_COUNT)
	var migration := "native_v3"
	if value is Dictionary and str(value.get("contract_id", "")) == BUTTON_ASSIGNMENTS_CONTRACT_ID:
		attack = _normalized_bindable_slot_array(
			value.get(SLOT_GROUP_ATTACK, []),
			ATTACK_SLOT_COUNT,
			"attack_slot"
		)
		attack_ring = _normalized_bindable_slot_array(
			value.get(SLOT_GROUP_ATTACK_RING, []),
			ATTACK_RING_SLOT_COUNT,
			"skill_slot"
		)
	elif value is Dictionary and str(value.get("contract_id", "")) == LEGACY_BUTTON_ASSIGNMENTS_CONTRACT_ID:
		# v2 had center[4] + attack_ring[3]. The center controls no longer
		# exist. Preserve the actual ring assignments in the first three new
		# ring slots and leave the separately bindable attack key empty.
		attack_ring = _normalized_bindable_slot_array(
			value.get(SLOT_GROUP_ATTACK_RING, []),
			ATTACK_RING_SLOT_COUNT,
			"skill_slot"
		)
		migration = "v2_attack_ring_preserved"
	else:
		attack_ring = _normalized_bindable_slot_array(
			legacy_center,
			ATTACK_RING_SLOT_COUNT,
			"skill_slot"
		)
		migration = (
			"legacy_quick_slots_to_attack_ring"
			if not legacy_center.is_empty()
			else "native_v3"
		)
	return {
		"contract_id": BUTTON_ASSIGNMENTS_CONTRACT_ID,
		SLOT_GROUP_ATTACK: attack,
		SLOT_GROUP_ATTACK_RING: attack_ring,
		"migration": migration,
	}


static func assign_button_slot(
	current_assignments: Variant,
	learned_skills: Dictionary,
	request: Dictionary
) -> Dictionary:
	var assignments := normalize_assignments(current_assignments)
	var source_contract_id := str(request.get("contract_id", ""))
	if source_contract_id not in UI_ASSIGNMENT_CONTRACT_IDS:
		return _button_failure("unsupported_contract", assignments, request)
	var slot_group := str(request.get("slot_group", ""))
	if slot_group not in [SLOT_GROUP_ATTACK, SLOT_GROUP_ATTACK_RING]:
		return _button_failure("unsupported_slot_group", assignments, request)
	var slot_count := (
		ATTACK_SLOT_COUNT
		if slot_group == SLOT_GROUP_ATTACK
		else ATTACK_RING_SLOT_COUNT
	)
	var slot_index := int(request.get("slot_index", -1))
	if slot_index < 0 or slot_index >= slot_count:
		return _button_failure("slot_out_of_range", assignments, request)
	var expected_slot_id := _stable_slot_id(slot_group, slot_index)
	var requested_slot_id := str(request.get("slot_id", ""))
	if not requested_slot_id.is_empty() and requested_slot_id != expected_slot_id:
		return _button_failure("slot_id_mismatch", assignments, request)
	var skill_name := str(request.get("skill_name", ""))
	var skill_id := str(request.get("skill_id", ""))
	if skill_name.is_empty() and not skill_id.is_empty():
		skill_name = ProfessionRules.skill_display_name(skill_id)
	if skill_id.is_empty() and not skill_name.is_empty():
		skill_id = ProfessionRules.skill_id(skill_name)
	if skill_name.is_empty() or skill_id.is_empty():
		return _button_failure("unknown_skill", assignments, request)
	if not _learned_skills_contains(learned_skills, skill_name, skill_id):
		return _button_failure("skill_not_learned", assignments, request)
	var destination := "attack_slot" if slot_group == SLOT_GROUP_ATTACK else "skill_slot"
	if not SkillInputPolicyScript.can_bind(skill_id, destination):
		return _button_failure("skill_not_bindable", assignments, request)
	var next_assignments := normalize_assignments(assignments)
	var group_slots: Array = next_assignments[slot_group]
	var previous_skill_name := str(group_slots[slot_index])
	group_slots[slot_index] = skill_name
	next_assignments[slot_group] = group_slots
	next_assignments["migration"] = "native_v3"
	return {
		"ok": true,
		"changed": previous_skill_name != skill_name,
		"reason": "assigned",
		"assignments": next_assignments,
		"change": {
			"contract_id": BUTTON_ASSIGNMENTS_CONTRACT_ID,
			"source_contract_id": source_contract_id,
			"slot_group": slot_group,
			"slot_index": slot_index,
			"slot_id": expected_slot_id,
			"requested_slot_id": requested_slot_id,
			"skill_id": skill_id,
			"skill_name": skill_name,
			"previous_skill_name": previous_skill_name,
		},
	}


static func clear_button_slot(
	current_assignments: Variant,
	request: Dictionary
) -> Dictionary:
	var assignments := normalize_assignments(current_assignments)
	var source_contract_id := str(request.get("contract_id", ""))
	if source_contract_id not in UI_ASSIGNMENT_CONTRACT_IDS:
		return _button_failure("unsupported_contract", assignments, request)
	var slot_group := str(request.get("slot_group", ""))
	if slot_group not in [SLOT_GROUP_ATTACK, SLOT_GROUP_ATTACK_RING]:
		return _button_failure("unsupported_slot_group", assignments, request)
	var slot_count := (
		ATTACK_SLOT_COUNT
		if slot_group == SLOT_GROUP_ATTACK
		else ATTACK_RING_SLOT_COUNT
	)
	var slot_index := int(request.get("slot_index", -1))
	if slot_index < 0 or slot_index >= slot_count:
		return _button_failure("slot_out_of_range", assignments, request)
	var expected_slot_id := _stable_slot_id(slot_group, slot_index)
	var requested_slot_id := str(request.get("slot_id", ""))
	if not requested_slot_id.is_empty() and requested_slot_id != expected_slot_id:
		return _button_failure("slot_id_mismatch", assignments, request)
	var next_assignments := normalize_assignments(assignments)
	var group_slots: Array = next_assignments[slot_group]
	var previous_skill_name := str(group_slots[slot_index])
	group_slots[slot_index] = ""
	next_assignments[slot_group] = group_slots
	next_assignments["migration"] = "native_v3"
	return {
		"ok": true,
		"changed": not previous_skill_name.is_empty(),
		"reason": (
			"restored_basic_attack"
			if slot_group == SLOT_GROUP_ATTACK
			else "cleared"
		),
		"assignments": next_assignments,
		"change": {
			"contract_id": BUTTON_ASSIGNMENTS_CONTRACT_ID,
			"source_contract_id": source_contract_id,
			"operation": "clear",
			"slot_group": slot_group,
			"slot_index": slot_index,
			"slot_id": expected_slot_id,
			"requested_slot_id": requested_slot_id,
			"skill_id": "",
			"skill_name": "",
			"previous_skill_name": previous_skill_name,
		},
	}


# Compatibility wrapper for old profile quick_slots. New UI code must use
# assign_button_slot and the v3 attack/attack_ring groups.
static func assign_quick_slot(
	current_slots: Array[String],
	learned_skills: Dictionary,
	request: Dictionary
) -> Dictionary:
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
	if not _learned_skills_contains(learned_skills, skill_name, skill_id):
		return _failure("skill_not_learned", current_slots, request)
	if not SkillInputPolicyScript.can_bind(skill_id, "skill_slot"):
		return _failure("skill_not_bindable", current_slots, request)
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


static func assignment_candidate(skill_name_or_id: String) -> Dictionary:
	return SkillInputPolicyScript.metadata(skill_name_or_id)


static func can_bind_to_attack_slot(skill_name_or_id: String) -> bool:
	return SkillInputPolicyScript.can_bind(skill_name_or_id, "attack_slot")


static func validate_assignments(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"valid": false, "errors": ["not_dictionary"]}
	if str(value.get("contract_id", "")) != BUTTON_ASSIGNMENTS_CONTRACT_ID:
		errors.append("contract_id")
	var attack: Variant = value.get(SLOT_GROUP_ATTACK, [])
	var attack_ring: Variant = value.get(SLOT_GROUP_ATTACK_RING, [])
	if not attack is Array or attack.size() != ATTACK_SLOT_COUNT:
		errors.append("attack_slot_count")
	if not attack_ring is Array or attack_ring.size() != ATTACK_RING_SLOT_COUNT:
		errors.append("attack_ring_slot_count")
	for skill_name: Variant in attack if attack is Array else []:
		if not str(skill_name).is_empty() and not can_bind_to_attack_slot(str(skill_name)):
			errors.append("attack_skill_not_bindable:%s" % str(skill_name))
	for skill_name: Variant in attack_ring if attack_ring is Array else []:
		if (
			not str(skill_name).is_empty()
			and not SkillInputPolicyScript.can_bind(str(skill_name), "skill_slot")
		):
			errors.append("ring_skill_not_bindable:%s" % str(skill_name))
	return {"valid": errors.is_empty(), "errors": errors}


static func _failure(
	reason: String,
	current_slots: Array[String],
	request: Dictionary
) -> Dictionary:
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


static func _normalized_slot_array(value: Variant, count: int) -> Array[String]:
	var result: Array[String] = []
	var source: Array = value if value is Array else []
	for index in range(count):
		result.append(str(source[index]) if index < source.size() else "")
	return result


static func _normalized_bindable_slot_array(
	value: Variant,
	count: int,
	destination: String
) -> Array[String]:
	var result := _normalized_slot_array(value, count)
	for index in range(result.size()):
		var skill_name := result[index]
		if (
			not skill_name.is_empty()
			and not SkillInputPolicyScript.can_bind(skill_name, destination)
		):
			result[index] = ""
	return result


static func _learned_skills_contains(
	learned_skills: Dictionary,
	skill_name: String,
	skill_id: String
) -> bool:
	return learned_skills.has(skill_name) or learned_skills.has(skill_id)


static func _stable_slot_id(slot_group: String, slot_index: int) -> String:
	return (
		"hud.attack.primary"
		if slot_group == SLOT_GROUP_ATTACK
		else "hud.attack_ring_skill.%d" % (slot_index + 1)
	)


static func _button_failure(
	reason: String,
	assignments: Dictionary,
	request: Dictionary
) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"reason": reason,
		"assignments": normalize_assignments(assignments),
		"change": {
			"contract_id": BUTTON_ASSIGNMENTS_CONTRACT_ID,
			"source_contract_id": str(request.get("contract_id", "")),
		},
	}
