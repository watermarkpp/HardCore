extends Node

func _ready()->void:
	var runtime:=MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	assert(runtime.design.design_size==[80.0,80.0] or runtime.design.design_size==[80,80])
	assert(runtime.instances.size()==48)
	assert(runtime.semantics.monster_spawn.size()==44)
	assert(runtime.semantics.npc_points.size()==7)
	assert(runtime.semantics.door_points.size()==2)
	assert(runtime.semantics.map_exit_points.size()==2)
	var expected_doors := {
		"door_000003": [74, 73],
		"door_000004": [7, 74],
	}
	for door: Dictionary in runtime.semantics.door_points:
		var expected_tile: Array = expected_doors.get(str(door.semantic_id), [])
		assert(Vector2i(int(expected_tile[0]), int(expected_tile[1])) == Vector2i(int(door.tile[0]), int(door.tile[1])))
		assert(str(door.portal_anchor_contract_id) == MapEditorPortalAnchorService.CONTRACT_ID)
		assert(str(door.portal_trigger_policy_id) == "bich_cave_mouth_explicit_v1")
		assert(not bool(door.target_configured))
		assert(int(door.target_map_id) < 0)
	assert(int(runtime.collision.blocked_count)==180)
	var content:=MapEditorRuntimeBridge.game_content()
	assert(content.spawns.size()==runtime.semantics.monster_spawn.size())
	assert(content.npcs.size()==7)
	assert(content.portals.size()==2)
	var portals_by_target := {}
	for portal: Dictionary in content.portals:
		portals_by_target[int(portal.target_map_id)] = portal
	assert(portals_by_target.has(217) and portals_by_target.has(268))
	assert((portals_by_target[217].position as Vector2).is_equal_approx(MapEditorRuntimeBridge.cell_to_world(runtime, [72, 5])))
	assert((portals_by_target[268].position as Vector2).is_equal_approx(MapEditorRuntimeBridge.cell_to_world(runtime, [6, 5])))
	print("BICH_USER_RUNTIME_IMPORT_PASS")
	get_tree().quit()
