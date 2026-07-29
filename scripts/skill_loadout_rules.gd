class_name SkillLoadoutRules
extends RefCounted

const ASSIGNMENT_CONTRACT_ID := "gameplay.skill.quick_slot_assignment.v1"
const BUTTON_ASSIGNMENTS_CONTRACT_ID := "gameplay.skill.button_assignments.v2"
const UI_ASSIGNMENT_CONTRACT_IDS: Array[String] = [
	"ui.skill.button_assignment.v2",
	"ui.skill.quick_slot_assignment.v1",
]
const SLOT_GROUP_CENTER := "center"
const SLOT_GROUP_ATTACK_RING := "attack_ring"
const CENTER_SLOT_COUNT := 4
const ATTACK_RING_SLOT_COUNT := 3


static func normalize_assignments(value: Variant, legacy_center: Array = []) -> Dictionary:
	var center := _normalized_slot_array([], CENTER_SLOT_COUNT)
	var attack_ring := _normalized_slot_array([], ATTACK_RING_SLOT_COUNT)
	var migrated_from_legacy := false
	if value is Dictionary and str(value.get("contract_id", "")) == BUTTON_ASSIGNMENTS_CONTRACT_ID:
		center = _normalized_slot_array(value.get(SLOT_GROUP_CENTER, []), CENTER_SLOT_COUNT)
		attack_ring = _normalized_slot_array(
			value.get(SLOT_GROUP_ATTACK_RING, []),
			ATTACK_RING_SLOT_COUNT
		)
	else:
		center = _normalized_slot_array(legacy_center, CENTER_SLOT_COUNT)
		# The old HUD rendered attack-ring buttons 1–3 as mirrors of quick
		# slots 1–3. Duplicate that initial state, then let v2 persist the two
		# groups independently.
		attack_ring = _normalized_slot_array(legacy_center, ATTACK_RING_SLOT_COUNT)
		migrated_from_legacy = not legacy_center.is_empty()
	return {
		"contract_id": BUTTON_ASSIGNMENTS_CONTRACT_ID,
		SLOT_GROUP_CENTER: center,
		SLOT_GROUP_ATTACK_RING: attack_ring,
		"migration": (
			"legacy_quick_slots_mirrored_once"
			if migrated_from_legacy
			else "native_v2"
		),
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
	if slot_group not in [SLOT_GROUP_CENTER, SLOT_GROUP_ATTACK_RING]:
		return _button_failure("unsupported_slot_group", assignments, request)
	var slot_count := (
		CENTER_SLOT_COUNT
		if slot_group == SLOT_GROUP_CENTER
		else ATTACK_RING_SLOT_COUNT
	)
	var slot_index := int(request.get("slot_index", -1))
	if slot_index < 0 or slot_index >= slot_count:
		return _button_failure("slot_out_of_range", assignments, request)
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
	var next_assignments := normalize_assignments(assignments)
	var group_slots: Array = next_assignments[slot_group]
	var previous_skill_name := str(group_slots[slot_index])
	group_slots[slot_index] = skill_name
	next_assignments[slot_group] = group_slots
	next_assignments["migration"] = "native_v2"
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
			"slot_id": _stable_slot_id(slot_group, slot_index),
			"requested_slot_id": str(request.get("slot_id", "")),
			"skill_id": skill_id,
			"skill_name": skill_name,
			"previous_skill_name": previous_skill_name,
		},
	}


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


static func _normalized_slot_array(value: Variant, count: int) -> Array[String]:
	var result: Array[String] = []
	var source: Array = value if value is Array else []
	for index in range(count):
		result.append(str(source[index]) if index < source.size() else "")
	return result


static func _learned_skills_contains(
	learned_skills: Dictionary,
	skill_name: String,
	skill_id: String
) -> bool:
	return learned_skills.has(skill_name) or learned_skills.has(skill_id)


static func _stable_slot_id(slot_group: String, slot_index: int) -> String:
	return (
		"hud.profession_skill.%d" % (slot_index + 1)
		if slot_group == SLOT_GROUP_CENTER
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
