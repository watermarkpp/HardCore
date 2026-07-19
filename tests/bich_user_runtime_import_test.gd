extends Node

func _ready()->void:
	var runtime:=MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	assert(runtime.design.design_size==[80.0,80.0] or runtime.design.design_size==[80,80])
	assert(runtime.instances.size()==56)
	assert(runtime.semantics.monster_spawn.size()==44)
	assert(runtime.semantics.npc_points.size()==7)
	assert(runtime.semantics.door_points.size()==4)
	var expected_doors := {
		"door_000001": [4, 4],
		"door_000002": [75, 5],
		"door_000003": [75, 76],
		"door_000004": [4, 75],
	}
	var instances_by_id := {}
	for instance: Dictionary in runtime.instances:
		instances_by_id[str(instance.instance_id)] = instance
	for door: Dictionary in runtime.semantics.door_points:
		var expected_tile: Array = expected_doors.get(str(door.semantic_id), [])
		assert(Vector2i(int(expected_tile[0]), int(expected_tile[1])) == Vector2i(int(door.tile[0]), int(door.tile[1])))
		assert(str(door.portal_anchor_contract_id) == MapEditorPortalAnchorService.CONTRACT_ID)
		var linked_instance: Dictionary = instances_by_id[str(door.linked_visual_instance_id)]
		var linked_tile: Array = linked_instance.tile
		var footprint: Array = door.portal_visual_footprint_tiles
		var expected_from_visual := Vector2i(
			int(linked_tile[0]) + int(footprint[0]) / 2,
			int(linked_tile[1]) + int(footprint[1]) / 2
		)
		assert(expected_from_visual == Vector2i(int(door.tile[0]), int(door.tile[1])))
	assert(int(runtime.collision.blocked_count)==180)
	var content:=MapEditorRuntimeBridge.game_content()
	assert(content.spawns.size()==runtime.semantics.monster_spawn.size())
	assert(content.npcs.size()==7)
	assert(content.portals.size()==1)
	assert(int(content.portals[0].target_map_id)==217)
	assert(
		(content.portals[0].position as Vector2).is_equal_approx(
			MapEditorRuntimeBridge.tile_to_world(runtime, [75, 5])
		)
	)
	print("BICH_USER_RUNTIME_IMPORT_PASS")
	get_tree().quit()
