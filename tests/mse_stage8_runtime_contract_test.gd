extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("stage8_runtime", 990008, "Stage 8", Vector2i(32, 32))
	assert(MapEditorGroundService.initialize(document).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "npc", Vector2i(2, 2), {"content_id": "npc.bich_guard", "npc_id": "npc.bich_guard"}).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "door", Vector2i(3, 3), {"target_map_id": "bich_province", "target_tile": [7, 7]}).ok)
	var palisade := MapEditorInstanceService.create_instance(document, "terrain.palisade_wall_01", "terrain", Vector2i(8, 8), "terrain_base")
	assert(palisade.ok)
	var palisade_collision_origin := MapEditorCollisionService._collision_origin(palisade.instance)
	assert(MapEditorCollisionService.paint_collision_cell(document, Vector2i(1, 1)).ok)
	assert(MapEditorCollisionService.erase_collision_cell(document, Vector2i(1, 1)).ok)
	assert(MapEditorBuildRuntimeService.approve_for_runtime(document).ok)
	var path := "user://stage8_runtime.runtime.json"
	assert(MapEditorBuildRuntimeService.build(document, path).ok)
	var loaded := MapEditorRuntimeMapService.load_runtime(path)
	assert(loaded.ok, str(loaded.get("errors", [])))
	assert(MapEditorRuntimeMapService.is_blocked(loaded.runtime, palisade_collision_origin))
	assert(not MapEditorRuntimeMapService.is_blocked(loaded.runtime, Vector2i(0, 0)))
	assert(not MapEditorRuntimeMapService.is_blocked(loaded.runtime, Vector2i(1, 1)))
	assert(loaded.runtime.collision.erased_cells.size() == 1)
	assert(MapEditorRuntimeMapService.entries_at(loaded.runtime, Vector2i(2, 2), "npc").size() == 1)
	assert(MapEditorRuntimeMapService.entries_at(loaded.runtime, Vector2i(3, 3), "door")[0].target_map_id == "bich_province")
	var tampered: Dictionary = (loaded.runtime as Dictionary).duplicate(true)
	tampered.collision.blocked_tiles.append("1,1")
	assert("runtime_checksum_invalid" in MapEditorRuntimeMapService.validate_runtime(tampered))
	print("MSE_STAGE8_RUNTIME_CONTRACT_PASS")
	get_tree().quit()
