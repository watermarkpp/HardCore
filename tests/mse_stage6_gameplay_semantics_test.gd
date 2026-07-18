extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("stage6_semantics", 990006, "Stage 6", Vector2i(64, 64))
	var npc := MapEditorGameplaySemanticService.add_entry(document, "npc", Vector2i(4, 5), {"content_id": "npc.bich_guard", "npc_id": "npc.bich_guard"})
	assert(npc.ok)
	assert(npc.entry.service_role == "dialogue")
	var spawn := MapEditorGameplaySemanticService.add_entry(document, "monster_spawn", Vector2i(10, 10), {"content_id": "monster.strawman", "monster_id": "monster.strawman", "radius_tiles": 4})
	assert(spawn.ok)
	assert(spawn.entry.respawn_seconds == 60)
	var boss := MapEditorGameplaySemanticService.add_entry(document, "boss_spawn", Vector2i(20, 20), {"content_id": "boss.skeleton_elite", "boss_id": "boss.skeleton_elite"})
	assert(boss.ok)
	assert(boss.entry.respawn_seconds == 1800)
	var invalid_door := MapEditorGameplaySemanticService.add_entry(document, "door", Vector2i(1, 1))
	assert(not invalid_door.ok)
	assert("door_target_map_required" in invalid_door.errors)
	var door := MapEditorGameplaySemanticService.add_entry(document, "door", Vector2i(2, 2), {"target_map_id": "bich_province", "target_tile": [33, 40]})
	assert(door.ok)
	var safe := MapEditorGameplaySemanticService.add_entry(document, "safe_area", Vector2i(5, 5), {"radius_tiles": 6})
	var light := MapEditorGameplaySemanticService.add_entry(document, "light", Vector2i(6, 6), {"radius_tiles": 3, "flicker": true})
	var trigger := MapEditorGameplaySemanticService.add_entry(document, "region_trigger", Vector2i(7, 7), {"radius_tiles": 2, "action": "enter_bich_gate"})
	assert(safe.ok and light.ok and trigger.ok)
	var entrance := MapEditorGameplaySemanticService.add_entry(document, "map_entrance", Vector2i(8, 8), {"display_name": "古墓一层入口"})
	var exit := MapEditorGameplaySemanticService.add_entry(document, "map_exit", Vector2i(9, 9), {"display_name": "返回森林的门"})
	assert(entrance.ok and exit.ok)
	assert(str(entrance.entry.entrance_id) == str(entrance.entry.semantic_id))
	assert(str(exit.entry.target_map_id).is_empty())
	var respawn_a := MapEditorGameplaySemanticService.add_entry(document, "respawn_point", Vector2i(11, 11), {"display_name": "旧出生点"})
	var respawn_b := MapEditorGameplaySemanticService.add_entry(document, "respawn_point", Vector2i(12, 11), {"display_name": "当前出生点"})
	assert(respawn_a.ok and respawn_b.ok)
	assert(not bool(document.layers.respawn_points[0].is_default))
	assert(bool(document.layers.respawn_points[1].is_default))
	var invalid_polygon := MapEditorGameplaySemanticService.add_entry(document, "safe_area", Vector2i(14, 14), {"shape": "polygon", "polygon_tiles": [[13, 13], [15, 13]]})
	assert(not invalid_polygon.ok)
	var safe_polygon := MapEditorGameplaySemanticService.add_entry(document, "safe_area", Vector2i(15, 15), {
		"shape": "polygon",
		"polygon_tiles": [[13, 13], [17, 13], [17, 17], [13, 17]],
		"radius_tiles": 0,
	})
	assert(safe_polygon.ok)
	var moved_polygon := MapEditorGameplaySemanticService.move_entry(document, str(safe_polygon.entry.semantic_id), Vector2i(1, 2))
	assert(moved_polygon.ok)
	assert(moved_polygon.entry.polygon_tiles[0] == [14, 15])
	var copied_polygon := MapEditorGameplaySemanticService.duplicate_entry_snapshot(
		document,
		moved_polygon.entry,
		Vector2i(25, 25)
	)
	assert(copied_polygon.ok, str(copied_polygon.get("errors", [])))
	assert(str(copied_polygon.entry.semantic_id) != str(moved_polygon.entry.semantic_id))
	assert(copied_polygon.entry.tile == [25, 25])
	assert(copied_polygon.entry.polygon_tiles[0] == [23, 23])
	assert(MapEditorGameplaySemanticService.all_entries(document).size() == 13)
	var disconnected_validation := MapEditorBuildRuntimeService.validate_for_runtime(document)
	assert("map_exit_target_map_required:%s" % exit.entry.semantic_id in disconnected_validation.errors)
	assert(MapEditorGameplaySemanticService.update_entry(document, str(exit.entry.semantic_id), {
		"target_map_id": "wooma_forest",
		"target_entrance_id": "map_entrance_000001",
	}).ok)
	var path := "user://mse_stage6_semantics_%s.editor.json" % Time.get_ticks_usec()
	var saved := MapEditorSaveService.save_document(document, path)
	assert(saved.ok, str(saved.get("errors", [])))
	var loaded := MapEditorLoadService.load_document(path)
	assert(loaded.ok, str(loaded.get("errors", [])))
	assert(MapEditorGameplaySemanticService.all_entries(loaded.document).size() == 13)
	assert(loaded.document.layers.map_entrance_points.size() == 1)
	assert(loaded.document.layers.map_exit_points.size() == 1)
	assert(loaded.document.layers.respawn_points.size() == 2)
	assert(str(loaded.document.layers.safe_area[1].shape) == "polygon")
	assert(str(loaded.document.layers.safe_area[2].shape) == "polygon")
	print("MSE_STAGE6_GAMEPLAY_SEMANTICS_PASS")
	get_tree().quit()
