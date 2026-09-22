extends RefCounted
## User spreadsheet drop authority (compiled). The sheet's E column is the
## final per-slot probability entering RNG; D is the final gold amount.
## No SPB, no V5 repair, no monster-class denominator policy, no v80/v81
## extension and no global multiplier may be applied downstream.
## Original baseline/SPB/21cq files stay sealed on disk; they are no longer
## consulted for production probabilities of compiled monsters.
##
## RV15-J2 review: validation is fail-closed over the whole document. Slots
## are checked with an immediately-updated seen-UID set (same-monster
## duplicates cannot slip past the index that is only published after every
## check passes), every numeric field is verified as an exact integer before
## conversion (bools, strings, fractions, NaN/Inf are rejected, not
## truncated), overflow metadata types are checked, and the per-slot tally
## must match the compiled summary counters before the authority is
## published. No missing field defaults silently into a usable value.
const PATH := "res://assets/data/drop/dpv2_user_loot_sheet_authority_v1.json"
const CONTRACT_ID := "hardcore.dpv2.user_loot_sheet_authority.v1"
## Narrow test seam: only the validation counterexample tests set this, and
## they must reset it in a finally-equivalent block. Production always reads
## PATH.
static var authority_path_override := ""
const MAX_SHEET_INTEGER := 2147483647
const VALID_ORIGINS := {
	"sheet_row": true,
	"new_equip": true,
	"v81_fate_blade": true,
	"user_directive_overlay": true,
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
var overlay_slot_count := 0
var empty_profile_ids: Array = []


func _init() -> void:
	var authority_path := (
		authority_path_override if not authority_path_override.is_empty() else PATH
	)
	if not FileAccess.file_exists(authority_path):
		load_error = "user_loot_sheet_authority_missing"
		return
	var text := FileAccess.get_file_as_string(authority_path).replace("\r\n", "\n")
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
	sheet_sha256 = str((source as Dictionary).get("sheet_sha256", "")).to_lower()
	if not _is_sha256_hex_strict(sheet_sha256):
		load_error = "user_loot_sheet_authority_sheet_sha_missing"
		return
	var monsters_value: Variant = parsed.get("monsters", [])
	if not monsters_value is Array:
		load_error = "user_loot_sheet_authority_monsters_invalid"
		return
	# RV15-J2: the seen-UID set is updated while validating each slot, so a
	# duplicate UID inside the same monster is rejected exactly like a
	# cross-monster duplicate; the public index is only published after the
	# whole document validates.
	var seen_uids: Dictionary = {}
	for raw_monster: Variant in monsters_value:
		if not raw_monster is Dictionary:
			load_error = "user_loot_sheet_authority_monster_invalid"
			return
		var monster: Dictionary = raw_monster
		var monster_id := _exact_integer(monster.get("monster_id", null), 1, MAX_SHEET_INTEGER)
		if monster_id < 1 or profiles_by_id.has(monster_id):
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
			if not _slot_valid(slot, seen_uids):
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
	# The whole document validated: publish the index and the tallies.
	for raw_monster: Variant in monsters_value:
		var monster: Dictionary = raw_monster
		var monster_id := int(monster.get("monster_id"))
		var slots: Array = monster.get("slots", [])
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
			if str(slot2.get("origin", "")) == "user_directive_overlay":
				overlay_slot_count += 1
	if monster_count == 0 or slot_count == 0:
		load_error = "user_loot_sheet_authority_empty_compiled"
		return
	# RV15-J2: the compiled summary must match the per-slot tally; a hard
	#-coded total is never trusted on its own.
	if not _summary_matches(parsed):
		return
	authority_id = str(parsed.get("authority_id", ""))
	if authority_id.is_empty():
		load_error = "user_loot_sheet_authority_id_missing"
		return
	digest = text.sha256_text()
	valid = true


## Exact integer gate: accepts JSON int/float values that are finite and
## integral; rejects bool, strings, fractions, NaN/Inf and out-of-range.
static func _exact_integer(value: Variant, minimum: int, maximum: int) -> int:
	if value is bool or (not value is int and not value is float):
		return minimum - 1
	var numeric := float(value)
	if not is_finite(numeric) or numeric != floorf(numeric):
		return minimum - 1
	if numeric < float(minimum) or numeric > float(maximum):
		return minimum - 1
	return int(numeric)


static func _is_sha256_hex_strict(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		var code := character.unicode_at(0)
		var is_digit := code >= 48 and code <= 57
		var is_lower_hex := code >= 97 and code <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true


func _slot_valid(slot: Dictionary, seen_uids: Dictionary) -> bool:
	var uid_value: Variant = slot.get("slot_uid", null)
	if not uid_value is String or (uid_value as String).is_empty():
		load_error = "user_loot_sheet_authority_slot_uid_invalid:"
		return false
	var uid := uid_value as String
	if seen_uids.has(uid):
		# RV15-J2: duplicates are refused outright — merging or deduplicating
		# would change the user's independent draw counts.
		load_error = "user_loot_sheet_authority_slot_uid_duplicate:%s" % uid
		return false
	seen_uids[uid] = true
	var item_value: Variant = slot.get("canonical_item_id", null)
	var item_id := -1
	if item_value != null:
		item_id = _exact_integer(item_value, 1, MAX_SHEET_INTEGER)
		if item_id < 1:
			load_error = "user_loot_sheet_authority_slot_identity_invalid:%s" % uid
			return false
	var gold_value: Variant = slot.get("gold_amount", null)
	var gold_amount := 0
	if gold_value != null:
		gold_amount = _exact_integer(gold_value, 1, MAX_SHEET_INTEGER)
		if gold_amount < 1:
			load_error = "user_loot_sheet_authority_slot_identity_invalid:%s" % uid
			return false
	# Exactly one identity: an item slot must not carry gold and vice versa.
	if (item_id > 0) == (gold_amount > 0):
		load_error = "user_loot_sheet_authority_slot_identity_invalid:%s" % uid
		return false
	var numerator_value: Variant = slot.get("final_numerator", null)
	var denominator_value: Variant = slot.get("final_denominator", null)
	var numerator := _exact_integer(numerator_value, 1, MAX_SHEET_INTEGER)
	var denominator := _exact_integer(denominator_value, 1, MAX_SHEET_INTEGER)
	if numerator < 1 or denominator < 1 or numerator > denominator:
		load_error = "user_loot_sheet_authority_slot_probability_invalid:%s" % uid
		return false
	var overflow_value: Variant = slot.get("overflow_priority", null)
	if overflow_value != null:
		var overflow := _exact_integer(overflow_value, 0, MAX_SHEET_INTEGER)
		if overflow < 0:
			load_error = "user_loot_sheet_authority_slot_overflow_invalid:%s" % uid
			return false
	var protected_value: Variant = slot.get("protected_drop", null)
	if protected_value != null and not protected_value is bool:
		load_error = "user_loot_sheet_authority_slot_protected_invalid:%s" % uid
		return false
	if not VALID_ORIGINS.has(str(slot.get("origin", ""))):
		load_error = "user_loot_sheet_authority_slot_origin_invalid:%s" % uid
		return false
	return true


func _summary_matches(parsed: Dictionary) -> bool:
	var summary_value: Variant = parsed.get("summary", null)
	if not summary_value is Dictionary:
		load_error = "user_loot_sheet_authority_summary_missing"
		return false
	var summary: Dictionary = summary_value
	var expected_monsters := _exact_integer(summary.get("monsters", null), 0, MAX_SHEET_INTEGER)
	var expected_slots := (
		_exact_integer(summary.get("slot_rows_compiled", null), 0, MAX_SHEET_INTEGER)
		+ _exact_integer(summary.get("new_equipment_slots", null), 0, MAX_SHEET_INTEGER)
		+ _exact_integer(summary.get("fate_blade_slots", null), 0, MAX_SHEET_INTEGER)
		+ _exact_integer(summary.get("user_directive_overlay_slots", null), 0, MAX_SHEET_INTEGER)
	)
	if expected_monsters != monster_count:
		load_error = (
			"user_loot_sheet_authority_summary_monster_mismatch:%d:%d"
			% [expected_monsters, monster_count]
		)
		return false
	if expected_slots != slot_count:
		load_error = (
			"user_loot_sheet_authority_summary_slot_mismatch:%d:%d"
			% [expected_slots, slot_count]
		)
		return false
	var expected_overlay := _exact_integer(
		summary.get("user_directive_overlay_slots", null), 0, MAX_SHEET_INTEGER
	)
	if expected_overlay != overlay_slot_count:
		load_error = (
			"user_loot_sheet_authority_summary_overlay_mismatch:%d:%d"
			% [expected_overlay, overlay_slot_count]
		)
		return false
	var empty_sheets_value: Variant = summary.get("empty_sheets", null)
	if not empty_sheets_value is Array or (empty_sheets_value as Array).size() != empty_profile_ids.size():
		load_error = "user_loot_sheet_authority_summary_empty_mismatch"
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
	var numerator_value: Variant = slot.get("final_numerator", null)
	var denominator_value: Variant = slot.get("final_denominator", null)
	var numerator := _exact_integer(numerator_value, 1, MAX_SHEET_INTEGER)
	var denominator := _exact_integer(denominator_value, 1, MAX_SHEET_INTEGER)
	if numerator <= 0 or denominator <= 0:
		return {"ok": false, "reason": "user_loot_sheet_probability_invalid"}
	var item_value: Variant = slot.get("canonical_item_id", -1)
	var resolved_item := -1
	if item_value != null:
		resolved_item = _exact_integer(item_value, 1, MAX_SHEET_INTEGER)
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
	var overflow_value: Variant = slot.get("overflow_priority", null)
	result["overflow_priority"] = (
		_exact_integer(overflow_value, 0, MAX_SHEET_INTEGER)
		if overflow_value != null
		else 0
	)
	var gold_value: Variant = slot.get("gold_amount", null)
	var final_gold := (
		_exact_integer(gold_value, 1, MAX_SHEET_INTEGER)
		if gold_value != null
		else 0
	)
	if final_gold > 0:
		result["final_gold_amount"] = final_gold
	return result
