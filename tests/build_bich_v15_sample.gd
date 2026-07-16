extends Node

func _ready() -> void:
	var document := MapEditorTypes.new_map_from_catalog("bich_province", "outdoor_province", 4, "比奇 V1.5 样板")
	document.ground.blank_fill_asset_id = "v1_5.a001_01"
	assert(MapEditorGroundService.initialize(document).ok)
	assert(MapEditorInstanceService.create_instance(document, "v1_5.b001_01", "obstacle", Vector2i(36, 34), "object_base").ok)
	assert(MapEditorInstanceService.create_instance(document, "v1_5.b001_04", "obstacle", Vector2i(52, 43), "object_base").ok)
	assert(MapEditorInstanceService.create_instance(document, "v1_5.b008_01", "terrain", Vector2i(20, 20), "terrain_base").ok)
	assert(MapEditorInstanceService.create_instance(document, "v1_5.b011_02", "terrain", Vector2i(74, 30), "terrain_base").ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "npc", Vector2i(32, 32), {"content_id":"npc.bich_guard", "npc_id":"npc.bich_guard"}).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "safe_area", Vector2i(32, 32), {"radius_tiles":8}).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "monster_spawn", Vector2i(66, 48), {"content_id":"monster.strawman", "monster_id":"monster.strawman", "radius_tiles":5}).ok)
	assert(MapEditorGameplaySemanticService.add_entry(document, "door", Vector2i(20, 20), {"target_map_id":"orc_tomb_entrance", "target_tile":[5,5]}).ok)
	assert(MapEditorBuildRuntimeService.approve_for_runtime(document).ok)
	var build := MapEditorBuildRuntimeService.build(document, "res://assets/data/runtime/map_editor/bich_v15_sample.runtime.json")
	assert(build.ok, str(build.get("errors", [])))
	print("BICH_V15_SAMPLE_BUILD_PASS")
	get_tree().quit()
