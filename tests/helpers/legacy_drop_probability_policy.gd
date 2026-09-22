extends RefCounted

## TEST ONLY: replay the sealed v80/v81 probability contract. Runtime callers
## must use the compiled user sheet; this adapter is never a production fallback.
## The catalog is the COMPLETE original Git blob, deterministically gzip'd.
## Its decompressed bytes and every original source binding must still match.
const PATH := "res://assets/data/drop/single_player_balance_v80.json"
const Seal := preload("res://scripts/generated/drop_balance_v80_seal.gd")
const CATALOG_SOURCE_PATH := "assets/data/runtime/canonical_monster_catalog.json"
const CATALOG_FIXTURE_PATH := "res://tests/fixtures/legacy_loot_v80/catalog.json.gz"
const CATALOG_MAX_BYTES := 16 * 1024 * 1024

const SMALL_MONSTER_CLASSIFICATION := "ordinary"
const SMALL_MONSTER_EQUIPMENT_DENOMINATOR_MULTIPLIER := 3
const SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER := 6
const ELITE_BOSS_SOLAR_DENOMINATOR_MULTIPLIER := 2
const ELITE_BOSS_CLASSIFICATIONS := {
	"elite": true,
	"boss": true,
}
const ELITE_BOSS_SOLAR_ITEM_IDS := {
	920014: true,
	920016: true,
}
const SMALL_MONSTER_SHENSHUI_ITEM_IDS := {
	910001: true,
	910002: true,
	910003: true,
	910004: true,
	910005: true,
	910006: true,
}

var valid := false
var records: Dictionary = {}
var copied_slots: Array = []
var _historical_classification_by_id: Dictionary = {}
var _additions := preload("res://scripts/drop/user_drop_additions_v81.gd").new()


func _init() -> void:
	var text := FileAccess.get_file_as_string(PATH).replace("\r\n", "\n")
	if text.sha256_text() != Seal.SHA256:
		return
	var doc: Variant = JSON.parse_string(text)
	if not doc is Dictionary or str(doc.get("contract_id", "")) != "drop.user_balance.v80":
		return
	if not FileAccess.file_exists(CATALOG_FIXTURE_PATH):
		return
	var catalog_bytes := FileAccess.get_file_as_bytes(CATALOG_FIXTURE_PATH).decompress_dynamic(
		CATALOG_MAX_BYTES, FileAccess.COMPRESSION_GZIP
	)
	if catalog_bytes.is_empty():
		return
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK:
		return
	if digest.update(catalog_bytes) != OK:
		return
	if digest.finish().hex_encode() != str(doc.source_bindings.get(CATALOG_SOURCE_PATH, "")):
		return
	var catalog_text := catalog_bytes.get_string_from_utf8()
	# Same seal and complete binding verification as user_drop_balance.gd.
	# Only the catalog's storage location changes to its exact historical blob.
	for path: String in doc.source_bindings:
		var source_text := (
			catalog_text if path == CATALOG_SOURCE_PATH
			else FileAccess.get_file_as_string("res://" + path)
		)
		if source_text.replace("\r\n", "\n").sha256_text() != str(doc.source_bindings[path]):
			return
	var catalog: Variant = JSON.parse_string(catalog_text)
	if not catalog is Dictionary or not catalog.get("entries", null) is Array:
		return
	for entry: Dictionary in catalog.entries:
		_historical_classification_by_id[int(entry.monster_id)] = str(entry.classification)
	if _historical_classification_by_id.is_empty():
		return
	records = doc.records
	copied_slots = doc.copied_slots
	valid = true


func profile_v80(monster_id: int) -> Dictionary:
	return extend_profile(GameData.dpv2_direct_profile(monster_id), monster_id)


func profile_v81(monster_id: int) -> Dictionary:
	return _additions.extend_profile(profile_v80(monster_id), monster_id)


func probability_v80(monster_id: int, slot_uid: String) -> Dictionary:
	var row: Dictionary = records.get(slot_uid, {})
	var source_id := int(row.get("source_monster_id", monster_id))
	var source_uid := str(row.get("source_uid", slot_uid))
	var probability := GameData.dpv2_effective_slot_probability(source_id, source_uid)
	if bool(probability.get("ok", false)):
		if not _historical_classification_by_id.has(source_id):
			return {"ok": false, "reason": "legacy_catalog_monster_missing"}
		probability = _apply_drop_probability_policy(
			probability, str(_historical_classification_by_id[source_id])
		)
	return apply(probability, slot_uid, monster_id)


func probability_v81(monster_id: int, slot_uid: String) -> Dictionary:
	if _additions.owns(monster_id, slot_uid):
		return _additions.probability(
			probability_v80(monster_id, str(_additions.policy.reference_slot_uid))
		)
	return probability_v80(monster_id, slot_uid)


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


func _apply_drop_probability_policy(
	probability: Dictionary,
	monster_classification: String,
) -> Dictionary:
	var multiplier := _drop_denominator_multiplier(
		probability,
		monster_classification,
	)
	if multiplier == 1:
		return probability
	var adjusted := _apply_denominator_multiplier(
		probability,
		multiplier,
	)
	if adjusted == probability:
		return probability
	if monster_classification == SMALL_MONSTER_CLASSIFICATION:
		var reason := (
			"small_monster_shenshui_denominator_x6"
			if multiplier == SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER
			else "small_monster_equipment_denominator_x3"
		)
		adjusted["pre_small_monster_numerator"] = int(
			probability.get("final_numerator", 0)
		)
		adjusted["pre_small_monster_denominator"] = int(
			probability.get("final_denominator", 0)
		)
		adjusted["small_monster_denominator_multiplier"] = multiplier
		adjusted["small_monster_probability_policy"] = reason
		adjusted["drop_denominator_policy"] = reason
	else:
		adjusted["elite_boss_solar_denominator_multiplier"] = multiplier
		adjusted["elite_boss_solar_probability_policy"] = (
			"elite_boss_solar_consumable_denominator_x2"
		)
		adjusted["drop_denominator_policy"] = (
			"elite_boss_solar_consumable_denominator_x2"
		)
	adjusted["drop_denominator_multiplier"] = multiplier
	return adjusted


func _apply_small_monster_probability_policy(
	probability: Dictionary,
	monster_classification: String,
) -> Dictionary:
	var multiplier := _small_monster_denominator_multiplier(
		probability,
		monster_classification,
	)
	if multiplier == 1:
		return probability
	var adjusted := _apply_denominator_multiplier(probability, multiplier)
	if adjusted == probability:
		return probability
	var reason := (
		"small_monster_shenshui_denominator_x6"
		if multiplier == SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER
		else "small_monster_equipment_denominator_x3"
	)
	adjusted["pre_small_monster_numerator"] = int(
		probability.get("final_numerator", 0)
	)
	adjusted["pre_small_monster_denominator"] = int(
		probability.get("final_denominator", 0)
	)
	adjusted["small_monster_denominator_multiplier"] = multiplier
	adjusted["small_monster_probability_policy"] = reason
	return adjusted


func _apply_denominator_multiplier(
	probability: Dictionary,
	multiplier: int,
) -> Dictionary:
	var numerator := int(probability.get("final_numerator", 0))
	var denominator := int(probability.get("final_denominator", 0))
	if numerator <= 0 or denominator <= 0 or multiplier <= 1:
		return probability
	var adjusted := probability.duplicate(true)
	adjusted["final_denominator"] = denominator * multiplier
	adjusted["probability_denominator"] = denominator * multiplier
	adjusted["final_probability"] = (
		float(numerator) / float(denominator * multiplier)
	)
	return adjusted


func _drop_denominator_multiplier(
	probability: Dictionary,
	monster_classification: String,
) -> int:
	var small_monster_multiplier := _small_monster_denominator_multiplier(
		probability,
		monster_classification,
	)
	if small_monster_multiplier > 1:
		return small_monster_multiplier
	var item_id := int(probability.get("canonical_item_id", -1))
	if (
		ELITE_BOSS_CLASSIFICATIONS.has(monster_classification)
		and ELITE_BOSS_SOLAR_ITEM_IDS.has(item_id)
	):
		return ELITE_BOSS_SOLAR_DENOMINATOR_MULTIPLIER
	return 1


func _small_monster_denominator_multiplier(
	probability: Dictionary,
	monster_classification: String,
) -> int:
	if monster_classification != SMALL_MONSTER_CLASSIFICATION:
		return 1
	var item_id := int(probability.get("canonical_item_id", -1))
	if SMALL_MONSTER_SHENSHUI_ITEM_IDS.has(item_id):
		return SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER
	if item_id > 0 and GameData.canonical_item_kind(item_id) == "equipment":
		return SMALL_MONSTER_EQUIPMENT_DENOMINATOR_MULTIPLIER
	return 1
