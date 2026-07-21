extends Node


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var document := MapEditorTypes.new_map(
		"portal_visual_anchor_test",
		990184,
		"Portal Visual Anchor Test",
		Vector2i(80, 80)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		"user.c60c71686cf6a463",
		"terrain",
		Vector2i(71, 2),
		"object_base"
	)
	assert(placed.ok, str(placed.get("errors", [])))
	var semantic := MapEditorGameplaySemanticService.add_entry(
		document,
		"door",
		Vector2i(71, 2),
		{
			"target_map_id": 217,
			"linked_visual_instance_id": str(placed.instance.instance_id),
		}
	)
	assert(semantic.ok, str(semantic.get("errors", [])))
	var synchronized := MapEditorPortalAnchorService.synchronize_linked_semantics(
		document,
		str(placed.instance.instance_id)
	)
	assert(synchronized.ok, str(synchronized.get("errors", [])))
	assert(synchronized.tile == Vector2i(75, 5))
	var door: Dictionary = document.layers.door_points[0]
	assert(door.tile == [75, 5])
	assert(
		str(door.portal_anchor_contract_id)
		== MapEditorPortalAnchorService.CONTRACT_ID
	)
	assert(door.portal_visual_origin_tile == [71, 2])
	var portal_footprint: Array = door.portal_visual_footprint_tiles
	assert(
		Vector2i(int(portal_footprint[0]), int(portal_footprint[1]))
		== Vector2i(8, 6),
		str(portal_footprint)
	)

	var moved := MapEditorInstanceService.move_instance(
		document,
		str(placed.instance.instance_id),
		Vector2i(70, 4)
	)
	assert(moved.ok)
	assert(
		MapEditorPortalAnchorService.synchronize_linked_semantics(
			document,
			str(placed.instance.instance_id)
		).ok
	)
	door = document.layers.door_points[0]
	assert(door.tile == [74, 7])
	assert(door.portal_visual_origin_tile == [70, 4])
	print("MSE_PORTAL_VISUAL_ANCHOR_PASS initial=75,5 moved=74,7")
	get_tree().quit(0)
