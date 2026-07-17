extends Node

func _ready()->void:
	var runtime:=MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	assert(runtime.design.design_size==[80.0,80.0] or runtime.design.design_size==[80,80])
	assert(runtime.instances.size()==56)
	assert(runtime.semantics.monster_spawn.size()==44)
	assert(runtime.semantics.npc_points.size()==5)
	assert(runtime.semantics.door_points.size()==4)
	var expected_doors := {
		"door_000001": [4, 4],
		"door_000002": [75, 5],
		"door_000003": [75, 75],
		"door_000004": [3, 76],
	}
	var instances_by_id := {}
	for instance: Dictionary in runtime.instances:
		instances_by_id[str(instance.instance_id)] = instance
	for door: Dictionary in runtime.semantics.door_points:
		var expected_tile: Array = expected_doors.get(str(door.semantic_id), [])
		assert(Vector2i(int(expected_tile[0]), int(expected_tile[1])) == Vector2i(int(door.tile[0]), int(door.tile[1])))
		var linked_tile: Array = instances_by_id[str(door.linked_visual_instance_id)].tile
		assert(Vector2i(int(linked_tile[0]), int(linked_tile[1])) == Vector2i(int(door.tile[0]), int(door.tile[1])))
	assert(int(runtime.collision.blocked_count)==398)
	var content:=MapEditorRuntimeBridge.game_content()
	assert(content.spawns.size()==runtime.semantics.monster_spawn.size())
	assert(content.npcs.size()==5)
	assert(content.portals.is_empty())
	print("BICH_USER_RUNTIME_IMPORT_PASS")
	get_tree().quit()
