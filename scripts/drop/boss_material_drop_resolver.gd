class_name BossMaterialDropResolver
extends RefCounted

const BLACK_IRON_TOKEN_ID := 940000
const ANCIENT_RELIC_FRAGMENT_ID := 950001
const BLACK_IRON_NAME := "黑铁矿"
const FRAGMENT_NAME := "远古圣物碎片"


static func owns(item_id: int) -> bool:
	return item_id == BLACK_IRON_TOKEN_ID or item_id == ANCIENT_RELIC_FRAGMENT_ID


static func reward(item_id: int) -> Dictionary:
	if not owns(item_id):
		return {"ok": false, "reason": "boss_material_token_unknown"}
	var name := BLACK_IRON_NAME if item_id == BLACK_IRON_TOKEN_ID else FRAGMENT_NAME
	var sample_id := 940010 if item_id == BLACK_IRON_TOKEN_ID else ANCIENT_RELIC_FRAGMENT_ID
	var sample := GameData.get_item_record({"item_id": sample_id})
	if int(sample.get("itemId", -1)) != sample_id or str(sample.get("name", "")) != name:
		return {"ok": false, "reason": "boss_material_identity_unavailable"}
	return {"ok": true, "reason": "", "kind": "item", "canonical_item_id": item_id, "item_name": name}


static func output_record(item_id: int, original_name: String, rng: RandomNumberGenerator) -> Dictionary:
	var reward_data := reward(item_id)
	if not bool(reward_data.get("ok", false)) or original_name != str(reward_data.get("item_name", "")):
		return {}
	var output_id := item_id
	if item_id == BLACK_IRON_TOKEN_ID:
		if rng == null:
			return {}
		# One successful ore slot yields exactly one purity, uniformly 10–20.
		output_id = BLACK_IRON_TOKEN_ID + rng.randi_range(10, 20)
	var catalog := GameData.get_item_record({"item_id": output_id})
	if int(catalog.get("itemId", -1)) != output_id or str(catalog.get("name", "")) != original_name:
		return {}
	return {
		"item_id": output_id,
		"canonical_item_id": output_id,
		"canonical_name": original_name,
		"source_item_id": item_id,
		"source_canonical_item_id": item_id,
		"source_canonical_name": original_name,
		"item_name": original_name,
		"name": original_name,
		"output_item_id": output_id,
		"output_record": catalog.duplicate(true),
		"identity_status": "resolved",
	}
