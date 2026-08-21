extends Node

const WALL_ASSET_ID := "wooma_temple_warm_wall_straight_x_l4_v01"


func _ready() -> void:
	var document := MapEditorTypes.new_map(
		"wooma_wall_overlap_stackable_test",
		991005,
		"Wooma Wall Overlap Stackable Test",
		Vector2i(32, 32)
	)
	var wall_asset := MapAssetCatalogService.find_asset(WALL_ASSET_ID)
	assert(not wall_asset.is_empty())
	assert(bool(wall_asset.get("placeable", false)))

	var same_tile := Vector2i(8, 8)
	var first := MapEditorInstanceService.create_instance(
		document, WALL_ASSET_ID, "terrain", same_tile, "terrain_base"
	)
	assert(first.ok, str(first.get("errors", [])))
	_assert_visual_only_wall(first.instance)

	var second := MapEditorInstanceService.create_instance(
		document, WALL_ASSET_ID, "terrain", same_tile, "terrain_base"
	)
	assert(second.ok, str(second.get("errors", [])))
	_assert_visual_only_wall(second.instance)

	var moved := MapEditorInstanceService.move_instance(
		document, str(second.instance.instance_id), same_tile
	)
	assert(moved.ok, str(moved.get("errors", [])))
	_assert_visual_only_wall(moved.instance)

	var duplicated := MapEditorInstanceService.duplicate_instance(
		document, str(first.instance.instance_id), same_tile
	)
	assert(duplicated.ok, str(duplicated.get("errors", [])))
	_assert_visual_only_wall(duplicated.instance)

	var outside := MapEditorInstanceService.create_instance(
		document, WALL_ASSET_ID, "terrain", Vector2i(-1, 8), "terrain_base"
	)
	assert(not outside.ok)
	assert((outside.get("errors", []) as Array).has("footprint_out_of_bounds"))
	assert(MapEditorInstanceService.all_instances(document).size() == 3)
	print("MSE_WOOMA_WALL_OVERLAP_STACKABLE_PASS")
	get_tree().quit(0)


func _assert_visual_only_wall(instance: Dictionary) -> void:
	assert(str(instance.get("asset_id", "")) == WALL_ASSET_ID)
	assert(str(instance.get("object_role", "")) == "terrain")
	assert(str(instance.get("placement_rule", "")) == "inside_map")
	assert(str(instance.get("collision_policy", "")) == "none")
	assert(instance.get("collision_footprint_tiles", []) == [0, 0])

