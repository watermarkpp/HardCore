extends Node

const Service := preload("res://scripts/layers/runtime/equipment_enhancement_service.gd")
const DropInstance := preload("res://scripts/item_drop_instance_rules.gd")


func _ready() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	for item_id: int in [81, 940010, 191, 192, 252]:
		var item := GameData.get_item_record({"item_id": item_id})
		assert(not item.is_empty())
		assert(bool(PlayerState.receive_record({"item_id": item_id, "name": str(item.name)}, false).success))
	PlayerState.gold = 1000000
	var service := Service.new(PlayerState)
	var target := _index_for_id(81)
	var iron := _index_for_id(940010)
	var accessory_a := _index_for_id(191)
	var accessory_b := _index_for_id(192)
	var forbidden := _index_for_id(252)
	var invalid := service.quote_forge(target, iron, forbidden, accessory_b)
	assert(not bool(invalid.get("valid", false)))
	assert(str(invalid.message) == "麻痹戒指不可以作为锻造材料")
	var quote := service.quote_forge(target, iron, accessory_a, accessory_b)
	assert(bool(quote.get("valid", false)))
	var inventory_before := PlayerState.inventory.duplicate(true)
	var gold_before := PlayerState.gold
	PlayerState._test_force_atomic_write_failure = true
	var save_failed := service.commit_forge(quote)
	PlayerState._test_force_atomic_write_failure = false
	assert(not bool(save_failed.get("committed", false)))
	assert(PlayerState.inventory == inventory_before and PlayerState.gold == gold_before)
	assert(not bool(service.commit_forge(quote).get("committed", false)), "a rolled quote was replayed")
	quote = service.quote_forge(target, iron, accessory_a, accessory_b)
	var result := service.commit_forge(quote)
	assert(bool(result.get("committed", false)), str(result.get("message", "")))
	assert(PlayerState.gold == gold_before - int(quote.gold_cost))
	assert(int((PlayerState.inventory[iron] as Dictionary).get("count", 0)) == 0)
	assert(int((PlayerState.inventory[accessory_a] as Dictionary).get("count", 0)) == 0)
	assert(int((PlayerState.inventory[accessory_b] as Dictionary).get("count", 0)) == 0)
	var target_after: Dictionary = PlayerState.inventory[target]
	assert(str(target_after.get("name", "")) == "匕首")
	assert(int(target_after.enhancement.forge.stage) == int(result.stage_after))
	assert(not bool(service.commit_forge(quote).get("committed", false)))
	_test_w7_success_and_failure()
	print("EQUIPMENT_ENHANCEMENT_TRANSACTION_PASS")
	get_tree().quit(0)


func _test_w7_success_and_failure() -> void:
	PlayerState.reset_progress(false)
	var item := GameData.get_item_record({"item_id": 81})
	var original := DropInstance.create_instance(item, "forge-w7-preserve-natural-fields")
	assert(not original.is_empty())
	assert(bool(PlayerState.receive_record(original, false).success))
	for item_id: int in [940010, 191, 192, 940011, 193, 194]:
		var catalog := GameData.get_item_record({"item_id": item_id})
		assert(bool(PlayerState.receive_record({"item_id": item_id, "name": str(catalog.name)}, false).success))
	PlayerState.gold = 1000000
	var service := Service.new(PlayerState)
	var target := _index_for_id(81)
	var first := service.quote_forge(target, _index_for_id(940010), _index_for_id(191), _index_for_id(192))
	assert(bool(first.valid))
	service.configure_rng(_rng_for_outcome(int(first.final_success_bps), true))
	var success := service.commit_forge(first)
	assert(bool(success.committed) and bool(success.forge_succeeded) and int(success.stage_after) == 1)
	var after_success: Dictionary = PlayerState.inventory[target]
	assert(GameData.validate_item_drop_instance(after_success))
	for field: String in ["instance_id", "drop_key_digest", "modifiers", "drop_affix", "durability_raw", "max_durability_raw", "weapon_luck", "weapon_curse"]:
		assert(after_success.get(field) == original.get(field), "forge changed natural field %s" % field)
	var second := service.quote_forge(target, _index_for_id(940011), _index_for_id(193), _index_for_id(194))
	assert(bool(second.valid))
	service.configure_rng(_rng_for_outcome(int(second.final_success_bps), false))
	var failure := service.commit_forge(second)
	assert(bool(failure.committed) and not bool(failure.forge_succeeded) and int(failure.stage_after) == 0)
	var after_failure: Dictionary = PlayerState.inventory[target]
	assert(GameData.validate_item_drop_instance(after_failure))
	for field: String in ["instance_id", "drop_key_digest", "modifiers", "drop_affix", "durability_raw", "max_durability_raw", "weapon_luck", "weapon_curse"]:
		assert(after_failure.get(field) == original.get(field), "failed forge changed natural field %s" % field)


func _rng_for_outcome(threshold: int, want_success: bool) -> RandomNumberGenerator:
	for candidate in range(1, 1000):
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate
		var wins := probe.randi_range(0, 9999) < threshold
		if wins == want_success:
			var result := RandomNumberGenerator.new()
			result.seed = candidate
			return result
	assert(false, "no RNG seed for requested outcome")
	return RandomNumberGenerator.new()


func _index_for_id(item_id: int) -> int:
	for index in range(PlayerState.inventory.size()):
		var value: Variant = PlayerState.inventory[index]
		if value is Dictionary and int((value as Dictionary).get("item_id", -1)) == item_id:
			return index
	return -1
