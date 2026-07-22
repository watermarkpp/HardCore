extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	for map_id: int in [4, 217, 218, 221, 268]:
		var monster_ids: Array[int] = game._monster_ids_for_map(map_id)
		assert(not monster_ids.is_empty(), "map %d has no prefetch ids" % map_id)
		var seen := {}
		for monster_id: int in monster_ids:
			assert(monster_id >= 0 and not seen.has(monster_id))
			assert(not GameData.get_monster_by_id(monster_id).is_empty())
			seen[monster_id] = true
	var source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	var covered_index := source.find("hud.loading_transition_covered")
	var prefetch_index := source.find("MonsterVisualScript.begin_map_prefetch")
	var load_index := source.find("\n\toperation.call()", prefetch_index)
	assert(covered_index >= 0 and prefetch_index > covered_index)
	assert(load_index > prefetch_index, "map loaded before monster prefetch")
	assert("MonsterVisualScript.poll_streaming" in source)
	print(
		"GAME_ROOT_MONSTER_PREFETCH_PASS: map ids are unique and Loading "
		+ "covers bounded async streaming before zone spawn"
	)
	get_tree().quit(0)
