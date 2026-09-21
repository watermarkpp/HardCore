extends RefCounted
## User spreadsheet drop authority (compiled). The sheet's E column is the
## final per-slot probability entering RNG; D is the final gold amount.
## No SPB, no V5 repair, no monster-class denominator policy, no v80/v81
## extension and no global multiplier may be applied downstream.
## Original baseline/SPB/21cq files stay sealed on disk; they are no longer
## consulted for production probabilities of compiled monsters.
const PATH := "res://assets/data/drop/dpv2_user_loot_sheet_authority_v1.json"
const CONTRACT_ID := "hardcore.dpv2.user_loot_sheet_authority.v1"
const VALID_ORIGINS := {
	"sheet_row": true,
	"new_equip": true,
	"v81_fate_blade": true,
}

var valid := false
var load_error := ""
var authority_id := ""
var sheet_sha256 := ""
var digest := ""
var profiles_by_id: Dictionary = {}
var slot_index: Dictionary = {}
var monster_count := 0
var slot_count := 0
var new_slot_count := 0
var empty_profile_ids: Array = []


func _init() -> void:
	if not FileAccess.file_exists(PATH):
		load_error = "user_loot_sheet_authority_missing"
		return
	var text := FileAccess.get_file_as_string(PATH).replace("\r\n", "\n")
	if text.is_empty():
		load_error = "user_loot_sheet_authority_empty"
		return
	var doc: Variant = JSON.parse_string(text)
	if not doc is Dictionary:
		load_error = "user_loot_sheet_authority_invalid_json"
		return
	var parsed: Dictionary = doc
	if str(parsed.get("schema", "")) != CONTRACT_ID:
		load_error = "user_loot_sheet_authority_schema_invalid"
		return
	var source: Variant = parsed.get("source", {})
	if not source is Dictionary:
		load_error = "user_loot_sheet_authority_source_invalid"
		return
	sheet_sha256 = str((source as Dictionary).get("sheet_sha256", ""))
	if sheet_sha256.is_empty():
		load_error = "user_loot_sheet_authority_sheet_sha_missing"
		return
	var monsters_value: Variant = parsed.get("monsters", [])
	if not monsters_value is Array:
		load_error = "user_loot_sheet_authority_monsters_invalid"
		return
	for raw_monster: Variant in monsters_value:
		if not raw_monster is Dictionary:
			load_error = "user_loot_sheet_authority_monster_invalid"
			return
		var monster: Dictionary = raw_monster
		var monster_id := int(monster.get("monster_id", -1))
		if monster_id <= 0 or profiles_by_id.has(monster_id):
			load_error = "user_loot_sheet_authority_monster_id_invalid"
			return
		var slots_value: Variant = monster.get("slots", [])
		if not slots_value is Array:
			load_error = "user_loot_sheet_authority_slots_invalid"
			return
		var slots: Array = slots_value
		for raw_slot: Variant in slots:
			if not raw_slot is Dictionary:
				load_error = "user_loot_sheet_authority_slot_invalid"
				return
			var slot: Dictionary = raw_slot
			if not _slot_valid(slot):
				return
		profiles_by_id[monster_id] = {
			"canonical_monster_id": monster_id,
			"monster_name": str(monster.get("monster_name", "")),
			"drop_enabled": true,
			"drop_profile_id": "dpv2.user_loot_sheet.%d" % monster_id,
			"baseline_origin": "USER_LOOT_SHEET_COMPILED",
			"slots": slots.duplicate(true),
		}
		monster_count += 1
		if slots.is_empty():
			empty_profile_ids.append(monster_id)
		for raw_slot2: Variant in slots:
			var slot2: Dictionary = raw_slot2
			var uid := str(slot2.get("slot_uid", ""))
			slot_index[uid] = {
				"canonical_monster_id": monster_id,
				"slot": slot2,
			}
			slot_count += 1
			if str(slot2.get("origin", "")) == "new_equip":
				new_slot_count += 1
	if monster_count == 0 or slot_count == 0:
		load_error = "user_loot_sheet_authority_empty_compiled"
		return
	authority_id = str(parsed.get("authority_id", ""))
	if authority_id.is_empty():
		load_error = "user_loot_sheet_authority_id_missing"
		return
	digest = text.sha256_text()
	valid = true


func _slot_valid(slot: Dictionary) -> bool:
	var uid := str(slot.get("slot_uid", ""))
	if uid.is_empty() or slot_index.has(uid):
		load_error = "user_loot_sheet_authority_slot_uid_invalid:%s" % uid
		return false
	var item_id_value: Variant = slot.get("canonical_item_id", -1)
	var item_id := int(item_id_value) if item_id_value != null else -1
	var gold_value: Variant = slot.get("gold_amount", 0)
	var gold_amount := int(gold_value) if gold_value != null else 0
	if (item_id > 0) == (gold_amount > 0):
		load_error = "user_loot_sheet_authority_slot_identity_invalid:%s" % uid
		return false
	var numerator_value: Variant = slot.get("final_numerator", 0)
	var denominator_value: Variant = slot.get("final_denominator", 0)
	var numerator := int(numerator_value) if numerator_value != null else 0
	var denominator := int(denominator_value) if denominator_value != null else 0
	if numerator < 1 or denominator < 1 or numerator > denominator:
		load_error = "user_loot_sheet_authority_slot_probability_invalid:%s" % uid
		return false
	if not VALID_ORIGINS.has(str(slot.get("origin", ""))):
		load_error = "user_loot_sheet_authority_slot_origin_invalid:%s" % uid
		return false
	return true


func has_profile(monster_id: int) -> bool:
	return valid and profiles_by_id.has(monster_id)


func is_empty_profile(monster_id: int) -> bool:
	return valid and profiles_by_id.has(monster_id) and (profiles_by_id[monster_id]["slots"] as Array).is_empty()


func profile(monster_id: int) -> Dictionary:
	if not valid:
		return {}
	var value: Variant = profiles_by_id.get(monster_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func owns(monster_id: int, slot_uid: String) -> bool:
	if not valid or not slot_index.has(slot_uid):
		return false
	var indexed: Dictionary = slot_index[slot_uid]
	return int(indexed.get("canonical_monster_id", -1)) == monster_id


func probability(monster_id: int, slot_uid: String) -> Dictionary:
	if not valid:
		return {"ok": false, "reason": "user_loot_sheet_authority_unavailable"}
	if not slot_index.has(slot_uid):
		return {"ok": false, "reason": "user_loot_sheet_slot_unresolved"}
	var indexed: Dictionary = slot_index[slot_uid]
	var resolved_id := int(indexed.get("canonical_monster_id", -1))
	if resolved_id != monster_id:
		return {"ok": false, "reason": "user_loot_sheet_slot_monster_mismatch"}
	var slot: Dictionary = indexed.get("slot", {})
	var numerator_value: Variant = slot.get("final_numerator", 0)
	var denominator_value: Variant = slot.get("final_denominator", 0)
	var numerator := int(numerator_value) if numerator_value != null else 0
	var denominator := int(denominator_value) if denominator_value != null else 0
	if numerator <= 0 or denominator <= 0:
		return {"ok": false, "reason": "user_loot_sheet_probability_invalid"}
	var item_value: Variant = slot.get("canonical_item_id", -1)
	var resolved_item := int(item_value) if item_value != null else -1
	var result := {
		"ok": true,
		"reason": "",
		"slot_uid": slot_uid,
		"canonical_monster_id": monster_id,
		"canonical_item_id": resolved_item,
		"drop_authority": authority_id,
		"drop_authority_digest": digest,
		"probability_stage": "sheet_final_pre_rng",
		"final_numerator": numerator,
		"final_denominator": denominator,
		"probability_numerator": numerator,
		"probability_denominator": denominator,
		"final_probability": float(numerator) / float(denominator),
		"protected_drop": bool(slot.get("protected_drop", false)),
		"slot_origin": str(slot.get("origin", "")),
	}
	var overflow_value: Variant = slot.get("overflow_priority", 0)
	result["overflow_priority"] = int(overflow_value) if overflow_value != null else 0
	var gold_result: Variant = slot.get("gold_amount", 0)
	var final_gold := int(gold_result) if gold_result != null else 0
	if final_gold > 0:
		result["final_gold_amount"] = final_gold
	return result
