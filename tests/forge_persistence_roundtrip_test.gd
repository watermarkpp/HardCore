extends Node

const Rules := preload("res://scripts/layers/rules/equipment_enhancement_rules.gd")
var completed_cases := 0

class FixtureState extends "res://scripts/player_state.gd":
	func _ready() -> void:
		set_process(false)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	for target_id in [81, 100, 116, 146]:
		await _roundtrip(target_id)
	_test_invalid_numbers()
	assert(completed_cases == 4)
	print("FORGE_PERSISTENCE_ROUNDTRIP_PASS targets=4 outcomes=success_and_failure")
	get_tree().quit(0)


func _roundtrip(target_id: int) -> void:
	var state := FixtureState.new()
	var root := "user://forge_roundtrip_%d_%d" % [Time.get_ticks_usec(), target_id]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.shared_warehouse_path = root.path_join("shared.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	state.active_profile_id = "owner"
	add_child(state)
	state.reset_progress(false)
	state.gold = 2000000
	var original := ItemDropInstanceRules.create_instance(
		GameData.get_item_record({"item_id": target_id}), "forge-persist:%d" % target_id)
	assert(not original.is_empty())
	state.forge_tray[4] = original.duplicate(true)
	for win in [true, false]:
		for entry: Array in [[1, 940013], [3, 239], [8, 239]]:
			var item := GameData.get_item_record({"item_id": int(entry[1])})
			state.forge_tray[int(entry[0])] = state._make_item_instance(str(item.name), item, -1, false)
			state.forge_tray[int(entry[0])]["item_id"] = int(entry[1])
		assert(state.save_game(false), str(state.last_save_result))
		var quote: Dictionary = state.quote_forge_tray()
		assert(quote.valid, str(quote))
		state._forge_service().configure_rng(_rng_for_outcome(int(quote.final_success_bps), win))
		var gold_before: int = state.gold
		var result: Dictionary = await state.commit_workbench_immediate("forge", quote)
		assert(result.committed and result.forge_succeeded == win, str(result))
		assert(state._start_item_save())
		state._json_persistence.drain()
		assert(not state._item_save_failed and state.last_save_result.success,
			"forged drop instance poisoned background save: %s" % str(state.last_save_result))
		var path: String = state._profile_path("owner")
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var saved: Dictionary = disk.forge_tray[4]
		assert(GameData.validate_item_drop_instance(saved), "forged item rejected after JSON readback")
		assert(int(saved.enhancement.forge.stage) == (1 if win else 0))
		assert(int(disk.gold) == gold_before - int(quote.gold_cost))
		for field in ["instance_id", "drop_key_digest", "modifiers", "drop_affix", "durability_raw", "max_durability_raw"]:
			assert(saved.get(field) == JSON.parse_string(JSON.stringify(original)).get(field), field)
		# Consume a disk-decoded forged item in another transaction, as after restart.
		state.forge_tray = state._load_workbench_tray(disk.forge_tray)
		assert((await state.transfer_workbench_immediate("forge", 4, -1, 70)).success)
		assert((await state.transfer_workbench_immediate("forge", 4, 70)).success)
		assert(state.save_game(false), "later saves / lifecycle barrier remain blocked")
	state.free()
	completed_cases += 1


func _rng_for_outcome(threshold: int, win: bool) -> RandomNumberGenerator:
	for candidate in range(1, 1000):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		if (rng.randi_range(0, 9999) < threshold) == win:
			rng.seed = candidate
			return rng
	assert(false)
	return RandomNumberGenerator.new()


func _test_invalid_numbers() -> void:
	var valid := {"contract_id": Rules.CONTRACT_ID,
		"forge": {"stage": 1, "history": ["magic_max"],
			"modifiers": [{"stat": "magic_max", "op": "add", "value": 1}]}}
	assert(Rules.validate_enhancement(JSON.parse_string(JSON.stringify(valid)), "武器"))
	for bad: Variant in ["1", true, 1.5, NAN, INF, -1, 8]:
		var changed := valid.duplicate(true)
		changed.forge.stage = bad
		assert(not Rules.validate_enhancement(changed, "武器"), "invalid stage accepted: %s" % str(bad))
		changed = valid.duplicate(true)
		changed.forge.modifiers[0].value = bad
		assert(not Rules.validate_enhancement(changed, "武器"), "invalid modifier accepted: %s" % str(bad))
