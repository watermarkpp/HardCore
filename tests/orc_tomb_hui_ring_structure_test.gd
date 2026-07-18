extends Node

const DOCUMENT_PATH := "res://map_editor_workspace/orc_tomb_1/orc_tomb_1.editor.json"
const STRUCTURE_ID := "orc_tomb_1.hui_ring.v1"


func _ready() -> void:
	var loaded := MapEditorLoadService.load_document(DOCUMENT_PATH)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	assert(str(document.get("map_id", "")) == "orc_tomb_1")
	var ground := MapEditorGroundService.initialize(document)
	assert(ground.ok, str(ground.get("errors", [])))
	assert(MapEditorGroundService.tile_overrides(ground.state).size() == 38 * 38)
	var structure: Dictionary = document.design.get("dungeon_structure", {})
	assert(str(structure.get("structure_id", "")) == STRUCTURE_ID)
	assert(str(structure.get("kind", "")) == "hui_ring")
	assert(str(structure.get("collision_authority", "")) == "manual_by_user")

	var walls: Array[Dictionary] = []
	var all_wall_count := 0
	var wall_instance_ids := {}
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("asset_id", "")).begins_with("orc_tomb_wall_"):
			all_wall_count += 1
			wall_instance_ids[str(instance.get("instance_id", ""))] = true
			assert(str(instance.get("collision_policy", "")) == "none")
			assert((instance.get("collision_cells", []) as Array).is_empty())
			var collision_footprint: Array = instance.get("collision_footprint_tiles", [])
			assert(collision_footprint.size() == 2)
			assert(int(collision_footprint[0]) == 0 and int(collision_footprint[1]) == 0)
		if str(instance.get("structure_id", "")) != STRUCTURE_ID:
			continue
		walls.append(instance)
		assert(str(instance.get("asset_id", "")).begins_with("orc_tomb_wall_"))
		assert(str(instance.get("collision_policy", "")) == "none")
		assert((instance.get("collision_cells", []) as Array).is_empty())
	assert(not walls.is_empty())
	assert(all_wall_count >= walls.size())
	var walkability := MapEditorCollisionService.build_walkability(document)
	for source: Dictionary in walkability.sources:
		if str(source.get("source", "")) == "instance":
			assert(not wall_instance_ids.has(str(source.get("id", ""))))
	print("ORC_TOMB_HUI_RING_STRUCTURE_PASS structure_walls=%d all_walls=%d" % [walls.size(), all_wall_count])
	get_tree().quit(0)
