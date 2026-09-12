extends Node
var timings: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profile_directory = "user://takeover_async_loot/characters"
	PlayerState.profile_index_path = "user://takeover_async_loot/profiles.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.active_profile_id = "async_probe"
	PlayerState.character_name = "异步拾取回归"
	PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	var catalog := GameData.get_item_record({"item_id": 197})
	PlayerState.inventory = []
	for i in range(64): PlayerState.inventory.append(PlayerState._make_item_instance(str(catalog.name), catalog, 50000+i))
	PlayerState.gold = 0
	PlayerState.test_mode = false
	assert(PlayerState.save_game(false))
	var path := PlayerState._profile_path(PlayerState.active_profile_id)
	for mode: String in ["gold", "equipment", "batch15"]:
		for trial in range(8):
			var candidates: Array = [{"gold": true, "amount": 17}]
			if mode == "equipment": candidates = [{"item_id":197, "item_name":str(catalog.name)}]
			if mode == "batch15":
				candidates = []
				for i in range(15): candidates.append({"item_name":"金创药(小量)"})
			var before := PlayerState.inventory.duplicate(true)
			var gold_before := PlayerState.gold
			var start := Time.get_ticks_usec()
			var plan := PlayerState.prepare_loot_save(candidates)
			var prepare_ms := float(Time.get_ticks_usec() - start) / 1000.0
			assert(plan.has("writer"))
			assert(PlayerState.inventory == before and PlayerState.gold == gold_before, "no speculative live credit")
			var result: Dictionary = {"pending": true}
			var max_poll_ms := 0.0
			while result.get("pending", false):
				await get_tree().process_frame
				start = Time.get_ticks_usec()
				result = PlayerState.finish_prepared_loot_save(plan)
				max_poll_ms = maxf(max_poll_ms, float(Time.get_ticks_usec() - start) / 1000.0)
			assert(result.success and result.success_count == candidates.size(), str(result))
			var saved := PlayerState._read_json(path)
			assert(int(saved.gold) == PlayerState.gold and saved.inventory == JSON.parse_string(JSON.stringify(PlayerState.inventory)))
			timings.append({"scenario":mode, "prepare_ms":prepare_ms, "max_poll_ms":max_poll_ms})
			PlayerState.inventory.resize(64)
	# A newer committed transaction wins; stale preparation cannot overwrite it.
	var conflict := PlayerState.prepare_loot_save([{"gold":true,"amount":19}])
	PlayerState.gold += 3
	assert(PlayerState.save_game(false))
	var newer_bytes := FileAccess.get_file_as_bytes(path)
	assert(PlayerState.finish_prepared_loot_save(conflict, true).get("retry",false))
	assert(FileAccess.get_file_as_bytes(path) == newer_bytes)
	# A failed promotion keeps both live inventory and the previous save intact.
	var failed := PlayerState.prepare_loot_save([{"gold":true,"amount":23}])
	failed.writer.result(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(failed.writer.path))
	assert(not PlayerState.finish_prepared_loot_save(failed).get("success",true))
	assert(FileAccess.get_file_as_bytes(path) == newer_bytes)
	# A valid-but-different temporary JSON must fail exact-byte readback and
	# restore the old primary, not become a new authoritative save on restart.
	var corrupt := PlayerState.prepare_loot_save([{"gold":true,"amount":31}])
	corrupt.writer.result(true)
	var tampered: Dictionary = JSON.parse_string(newer_bytes.get_string_from_utf8())
	tampered["gold"] = 999999
	var corrupt_file := FileAccess.open(corrupt.writer.path, FileAccess.WRITE)
	corrupt_file.store_string(JSON.stringify(tampered))
	corrupt_file.close()
	assert(not PlayerState.finish_prepared_loot_save(corrupt).get("success",true))
	assert(FileAccess.get_file_as_bytes(path) == newer_bytes)
	# Cancellation never makes its private temporary document recoverable as a save.
	var cancelled := PlayerState.prepare_loot_save([{"gold":true,"amount":29}])
	cancelled.writer.cancel()
	cancelled.writer.result(true)
	assert(not FileAccess.file_exists(cancelled.writer.path))
	assert(FileAccess.get_file_as_bytes(path) == newer_bytes)
	var out := FileAccess.open("res://outputs/takeover_20260913/loot_async_timings.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(timings,"  "))
	out.close()
	PlayerState.test_mode = true
	print("LOOT_ASYNC_DURABILITY_PASS real_saves=24 conflict=PASS failure=PASS cancel=PASS no_speculative_credit=true")
	get_tree().quit()
