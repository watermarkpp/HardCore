extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded(), "catalog load failed")
	var ids: Array[int] = []
	for value: Variant in GameData.monsters:
		if value is Dictionary:
			ids.append(int(value.get("id", -1)))
			if ids.size() >= 8: break
	var names := LootRuntime.possible_item_names_for_monster_ids(ids)
	assert(names == LootRuntime.possible_item_names_for_monster_ids(ids), "possible set is nondeterministic")
	assert(names.size() == names.duplicate().size(), "possible set contains duplicates")
	var detailed_rng := RandomNumberGenerator.new()
	detailed_rng.seed = 918273
	var lean_rng := RandomNumberGenerator.new()
	lean_rng.seed = 918273
	var detailed := LootRuntime.roll_monster_drops(31, detailed_rng, true)
	var lean := LootRuntime.roll_monster_drops(31, lean_rng, false)
	for field in ["items", "gold_drops", "successful_roll_count", "ground_output_count", "overflow_discarded_count", "protected_overflow_count"]:
		assert(detailed.get(field) == lean.get(field), "lean parity mismatch: %s" % field)
	assert(lean.attempts.is_empty() and lean.slot_attempts.is_empty() and lean.debug.is_empty(), "lean retained audit views")
	LootPickup.clear_descriptor_cache_for_test()
	UIItemTextureCache.clear_for_test()
	LootPickup.prewarm_item_names(names)
	for _frame in range(30):
		UIItemTextureCache.poll_threaded_paths()
		if UIItemTextureCache.threaded_pending_count() == 0: break
	assert(UIItemTextureCache.threaded_pending_count() == 0, "prewarm did not finish")
	if not names.is_empty():
		var descriptor := LootPickup.ground_visual_descriptor(names[0])
		UIItemTextureCache.texture_at_path(str(descriptor.get("path", "")))
		assert(UIItemTextureCache.sync_miss_count() == 0, "prewarm fell back to sync load")
	print("LOOT_GROUND_ICON_PREWARM_PASS")
	get_tree().quit(0)
