extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var formal_spawn_total := 0
	for map_id: int in MapEditorRuntimeBridge.released_map_ids():
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		var expected_set := {}
		for layer_name: String in ["spawns", "bosses"]:
			for raw_entry: Variant in content.get(layer_name, []):
				assert(raw_entry is Dictionary)
				var expected_id := int((raw_entry as Dictionary).get("monster_id", -1))
				assert(expected_id > 0)
				expected_set[expected_id] = true
				formal_spawn_total += 1
		var monster_ids: Array[int] = game._monster_ids_for_map(map_id)
		var expected_ids: Array[int] = []
		for raw_id: Variant in expected_set.keys():
			expected_ids.append(int(raw_id))
		expected_ids.sort()
		var sorted_monster_ids := monster_ids.duplicate()
		sorted_monster_ids.sort()
		assert(sorted_monster_ids == expected_ids, "map %d prefetch IDs drifted" % map_id)
		var seen := {}
		for monster_id: int in monster_ids:
			assert(monster_id > 0 and not seen.has(monster_id))
			assert(not GameData.get_monster_by_id(monster_id).is_empty())
			seen[monster_id] = true
	assert(formal_spawn_total == 107, "formal canonical spawn total drifted")
	var source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	var covered_index := source.find("hud.loading_transition_covered")
	var prefetch_index := source.find("_streaming_coordinator.begin_map_prefetch")
	var load_index := source.find("\n\toperation.call()", prefetch_index)
	assert(covered_index >= 0 and prefetch_index > covered_index)
	assert(load_index > prefetch_index, "map loaded before monster prefetch")
	assert("_streaming_coordinator.poll_once" in source)
	assert(
		"_streaming_coordinator.poll_once(Engine.get_process_frames())" in source,
		"Q2-D: game_root must own the single formal streaming poll"
	)
	print(
		"GAME_ROOT_MONSTER_PREFETCH_PASS: map ids are unique and Loading "
		+ "covers bounded async streaming before zone spawn"
	)
	get_tree().quit(0)
