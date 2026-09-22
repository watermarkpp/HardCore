extends Node

var rows: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profile_directory = "user://takeover_loot_profile/characters"
	PlayerState.profile_index_path = "user://takeover_loot_profile/profiles.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.active_profile_id = "takeover_probe"
	PlayerState.character_name = "拾取计时"
	PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	var catalog: Dictionary = {}
	for item_id in range(80, 300):
		var candidate := GameData.get_item_record({"item_id": item_id})
		if candidate.get("kind") == "equipment" and int(candidate.get("weight", 100)) <= 1:
			catalog = candidate
			break
	assert(not catalog.is_empty())
	for scenario: String in ["gold", "equipment", "batch15"]:
		PlayerState.inventory = []
		for i in range(64):
			PlayerState.inventory.append(PlayerState._make_item_instance(str(catalog.name), catalog, 10000+i))
		PlayerState.gold = 0
		PlayerState.test_mode = false
		assert(PlayerState.save_game(false))
		for trial in range(8):
			var candidates: Array = []
			match scenario:
				"gold": candidates.append({"gold": true, "amount": 17})
				"equipment": candidates.append({"item_id": int(catalog.itemId), "item_name": str(catalog.name)})
				"batch15":
					for j in range(15):
						candidates.append({"item_name": "金创药(小量)"})
			var result := PlayerState.receive_loot_batch_partial(candidates)
			assert(result.success and result.success_count == candidates.size(), str(result))
			rows.append({"scenario": scenario, "trial":trial, "profile":PlayerState._last_loot_batch_profile.duplicate(true), "save_phases":PlayerState._last_save_phase_profile.duplicate(),"atomic_phases":PlayerState._atomic_write_phases.duplicate()})
			# Verify durable truth, including the real (test_mode=false) write.
			var saved := PlayerState._read_json(PlayerState._profile_path(PlayerState.active_profile_id))
			assert(int(saved.gold) == PlayerState.gold, "durable gold")
			assert(saved.inventory == JSON.parse_string(JSON.stringify(PlayerState.inventory)), "durable inventory JSON roundtrip")
			if scenario == "batch15":
				PlayerState.inventory.resize(64)
	var label := OS.get_environment("HARDCORE_LOOT_PROFILE_LABEL")
	if label.is_empty(): label = "unlabelled"
	var output := FileAccess.open("res://outputs/takeover_20260913/loot_save_%s.json" % label, FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify({"rows":rows}, "  "))
	output.close()
	PlayerState.test_mode = true
	print("LOOT_SAVE_PROFILE_PASS samples=%d real_atomic_save=true" % rows.size())
	get_tree().quit()
