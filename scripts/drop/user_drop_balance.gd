extends RefCounted
## User-authorized final balance stage. Original source and SPB ledgers stay sealed.
const PATH := "res://assets/data/drop/single_player_balance_v80.json"
const Seal = preload("res://scripts/generated/drop_balance_v80_seal.gd")
var valid := false
var records: Dictionary = {}
var copied_slots: Array = []

func _init() -> void:
	var text := FileAccess.get_file_as_string(PATH).replace("\r\n", "\n")
	if text.sha256_text() != Seal.SHA256:
		return
	var doc: Variant = JSON.parse_string(text)
	if not doc is Dictionary or str(doc.get("contract_id", "")) != "drop.user_balance.v80":
		return
	for path: String in doc.source_bindings:
		if FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").sha256_text() != str(doc.source_bindings[path]):
			return
	records = doc.records
	copied_slots = doc.copied_slots
	valid = true

func extend_profile(profile: Dictionary, monster_id: int) -> Dictionary:
	if monster_id == 159 and valid and not profile.is_empty():
		profile = profile.duplicate(true)
		profile.slots.append_array(copied_slots.duplicate(true))
	return profile

func apply(probability: Dictionary, slot_uid: String, monster_id: int) -> Dictionary:
	if not valid:
		return {"ok": false, "reason": "user_drop_balance_unavailable"}
	if not bool(probability.get("ok", false)) or not records.has(slot_uid):
		return probability
	var row: Dictionary = records[slot_uid]
	if int(row.monster_id) != monster_id or int(row.item_id) != int(probability.get("canonical_item_id", -1)):
		return {"ok": false, "reason": "user_drop_balance_identity_mismatch"}
	var result := probability.duplicate()
	result["slot_uid"] = slot_uid
	result["canonical_monster_id"] = monster_id
	if not bool(probability.get("spb_enabled", false)):
		return result
	if int(probability.final_numerator) * int(row.before[1]) != int(probability.final_denominator) * int(row.before[0]):
		return {"ok": false, "reason": "user_drop_balance_input_drift"}
	result["pre_user_balance_numerator"] = int(probability.final_numerator)
	result["pre_user_balance_denominator"] = int(probability.final_denominator)
	result["user_balance_reason"] = row.reason
	result["user_balance_source_uid"] = row.source_uid
	result["user_balance_multiplier"] = row.multiplier
	result["final_numerator"] = int(row.after[0])
	result["final_denominator"] = int(row.after[1])
	result["probability_numerator"] = int(row.after[0])
	result["probability_denominator"] = int(row.after[1])
	result["final_probability"] = float(row.after[0]) / float(row.after[1])
	return result
