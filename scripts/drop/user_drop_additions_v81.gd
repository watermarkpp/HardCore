extends RefCounted

const PATH := "res://assets/data/drop/user_additions_v81.json"
var policy: Dictionary = {}
var valid := false

func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary: return
	policy = data
	valid = (str(policy.get("contract_id", "")) == "drop.user_additions.v81"
		and int(policy.get("monster_id", -1)) == 76 and int(policy.get("item_id", -1)) == 110
		and int(policy.get("reference_item_id", -1)) == 99
		and policy.get("ratio", []) is Array and policy.ratio.size() == 2
		and float(policy.ratio[0]) == 2.0 and float(policy.ratio[1]) == 3.0
		and str(policy.get("reference_slot_uid", "")) == "dpv2.direct.m76.slot_029"
		and str(policy.get("slot_uid", "")) == "dpv2.user.v81.m76.fate_blade")

func owns(monster_id: int, slot_uid: String) -> bool:
	return valid and monster_id == int(policy.monster_id) and slot_uid == str(policy.slot_uid)

func extend_profile(profile: Dictionary, monster_id: int) -> Dictionary:
	if monster_id != 76: return profile
	if not valid or profile.is_empty(): return {}
	for slot: Dictionary in profile.slots:
		if str(slot.slot_uid) != str(policy.reference_slot_uid): continue
		if int(slot.get("canonical_item_id", -1)) != 99: return {}
		var result := profile.duplicate(true)
		var added := slot.duplicate(true)
		added.slot_uid = policy.slot_uid
		added.canonical_item_id = int(policy.item_id)
		var base := _scaled(int(slot.base_numerator), int(slot.base_denominator))
		added.base_numerator = base.x
		added.base_denominator = base.y
		added.baseline_origin = "EXPLICIT_USER_20260914_ADDITION"
		added.source_provenance_id = "drop.user_additions.v81"
		result.slots.append(added)
		return result
	return {}

func probability(reference: Dictionary) -> Dictionary:
	if (not valid or not bool(reference.get("ok", false))
		or int(reference.get("canonical_item_id", -1)) != 99
		or int(reference.get("canonical_monster_id", -1)) != 76
		or str(reference.get("slot_uid", "")) != str(policy.reference_slot_uid)):
		return {"ok":false, "reason":"v81_addition_reference_unavailable"}
	var result := reference.duplicate(true)
	result.slot_uid = policy.slot_uid
	result.canonical_item_id = int(policy.item_id)
	result.source_provenance_id = "drop.user_additions.v81"
	result.baseline_origin = "EXPLICIT_USER_20260914_ADDITION"
	# Derive from the final live reference, including global presets and caps.
	var fraction := _scaled(int(reference.final_numerator), int(reference.final_denominator))
	result.final_numerator = fraction.x
	result.final_denominator = fraction.y
	result.probability_numerator = fraction.x
	result.probability_denominator = fraction.y
	result.final_probability = float(fraction.x) / fraction.y
	# Audit-stage fractions describe this new item, not the inherited reference.
	# The final stage above deliberately follows the reference AFTER any cap.
	for stage: String in ["base", "effective", "selected", "unreduced_final"]:
		var scaled := _scaled(int(reference[stage + "_numerator"]), int(reference[stage + "_denominator"]))
		result[stage + "_numerator"] = scaled.x
		result[stage + "_denominator"] = scaled.y
		if result.has(stage + "_probability"):
			result[stage + "_probability"] = float(scaled.x) / scaled.y
	result.user_balance_reason = "USER_FATE_BLADE_REFERENCE_FINAL_X2_3"
	result.user_balance_source_uid = policy.reference_slot_uid
	result.user_balance_multiplier = policy.ratio
	result.pre_user_balance_numerator = int(reference.final_numerator)
	result.pre_user_balance_denominator = int(reference.final_denominator)
	return result

func reward(slot: Dictionary) -> Dictionary:
	# This user-added exact ID is absent from the frozen 21CQ drop-only identity
	# subset. Resolve through the authoritative equipment catalog, without
	# extending that historical subset or accepting caller-supplied names.
	if not owns(76, str(slot.get("slot_uid", ""))) or int(slot.get("canonical_item_id", -1)) != 110:
		return {"ok":false, "reason":"v81_reward_identity_mismatch"}
	var item := item_identity(110)
	if item.is_empty():
		return {"ok":false, "reason":"v81_equipment_authority_unavailable"}
	return {"ok":true, "reason":"", "kind":"item", "canonical_item_id":110, "item_name":str(item.canonical_item_name)}

func item_identity(item_id: int) -> Dictionary:
	if not valid or item_id != 110: return {}
	var item := GameData.get_item_rules_record({"item_id":110})
	if item.is_empty() or GameData._stable_item_id(item) != 110 or str(item.get("kind", "")) != "equipment": return {}
	return {"canonical_item_id":110, "canonical_item_name":str(item.name), "authority":"drop.user_additions.v81"}

func _scaled(numerator: int, denominator: int) -> Vector2i:
	var n := numerator * int(policy.ratio[0])
	var d := denominator * int(policy.ratio[1])
	var a := n
	var b := d
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return Vector2i(n / a, d / a)
