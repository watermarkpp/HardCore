extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var authored_slot_total := 0
	var projected_spawn_total := 0
	var formal_maps := _formal_authored_maps()
	assert(not formal_maps.is_empty(), "formal release registry has no playable maps")
	for authored_map: Dictionary in formal_maps:
		var map_id := int(authored_map.runtime_map_id)
		var runtime: Dictionary = authored_map.runtime
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		var expected_set := {}
		for source_layer: String in ["monster_spawn", "boss_spawn"]:
			for raw_entry: Variant in runtime.get("semantics", {}).get(source_layer, []):
				var expected_id := _assert_valid_authored_slot(raw_entry, source_layer)
				expected_set[expected_id] = true
				authored_slot_total += 1
		projected_spawn_total += (
			content.get("spawns", []).size() + content.get("bosses", []).size()
		)
		assert(
			content.get("spawns", []).size()
			== runtime.get("semantics", {}).get("monster_spawn", []).size()
		)
		assert(
			content.get("bosses", []).size()
			== runtime.get("semantics", {}).get("boss_spawn", []).size()
		)
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
	assert(authored_slot_total > 0, "formal authored spawn slots are empty")
	assert(
		projected_spawn_total == authored_slot_total,
		"runtime spawn projection diverged from independently-read authored slots"
	)
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


func _formal_authored_maps() -> Array[Dictionary]:
	assert(bool(MapEditorRuntimeBridge.registry_load_state().get("valid", false)))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		MapEditorRuntimeBridge.RELEASE_REGISTRY_PATH
	))
	assert(parsed is Dictionary)
	var registry := parsed as Dictionary
	assert(int(registry.get("schema_version", 0)) == 1)
	assert(str(registry.get("registry_contract_id", "")) == "mse.map.runtime.release.v1")
	var result: Array[Dictionary] = []
	for raw_entry: Variant in registry.get("maps", []):
		assert(raw_entry is Dictionary)
		var entry := raw_entry as Dictionary
		if str(entry.get("release_state", "")) != "implemented_playable":
			continue
		var runtime_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			str(entry.get("runtime_path", ""))
		))
		assert(runtime_value is Dictionary)
		var runtime := runtime_value as Dictionary
		assert(str(runtime.get("build_sha256", "")) == str(entry.get("approved_build_sha256", "")))
		assert(str(runtime.get("source", {}).get("map_id", "")) == str(entry.get("map_key", "")))
		assert(int(runtime.get("source", {}).get("runtime_map_id", -1)) == int(entry.get("runtime_map_id", -1)))
		result.append({
			"runtime_map_id": int(entry.get("runtime_map_id", -1)),
			"runtime": runtime,
		})
	return result


func _assert_valid_authored_slot(raw_entry: Variant, source_layer: String) -> int:
	assert(raw_entry is Dictionary)
	var entry := raw_entry as Dictionary
	var raw_id: Variant = entry.get("monster_id", null)
	assert(
		raw_id is int
		or (
			raw_id is float
			and is_finite(float(raw_id))
			and float(raw_id) == floorf(float(raw_id))
		)
	)
	var monster_id := int(raw_id)
	var runtime_monster := GameData.get_canonical_monster_entry(monster_id, "runtime")
	var editor_monster := GameData.get_canonical_monster_entry(monster_id, "editor")
	assert(not runtime_monster.is_empty() and not editor_monster.is_empty())
	var classification := GameData.canonical_monster_classification(monster_id)
	var spawn_classification := str(
		runtime_monster.get("spawn_classification", "")
	)
	var canonical_placement := str(
		editor_monster.get("editor_placement", {}).get("placement_kind", "")
	)
	assert(
		canonical_placement.is_empty() or canonical_placement == source_layer
	)
	if spawn_classification == "special_normal":
		assert(source_layer == "monster_spawn")
	elif source_layer == "boss_spawn":
		assert(classification in ["elite", "boss"])
	else:
		assert(classification not in ["elite", "boss"])
	return monster_id
