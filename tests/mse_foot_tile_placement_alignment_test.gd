extends Node

const PlacementAnchorPolicy := preload("res://scripts/map_assets/map_asset_placement_anchor_policy.gd")
const InstanceProfileService := preload("res://scripts/map_editor/map_editor_instance_profile_service.gd")
const EPSILON := 0.01


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var design_size := Vector2i(38, 38)
	var document := MapEditorTypes.new_map(
		"foot_tile_alignment_test",
		990180,
		"Foot Tile Alignment Test",
		design_size
	)

	var brazier := MapAssetCatalogService.find_asset("cave_dungeon.brazier_01")
	assert(not brazier.is_empty())
	assert(str(brazier.get("placement_anchor_policy_id", "")) == PlacementAnchorPolicy.POLICY_ID)
	assert(float(brazier.placement_anchor_px[1]) < float(brazier.anchor_px[1]))

	var placed := MapEditorInstanceService.create_instance(
		document,
		str(brazier.asset_id),
		"decoration",
		Vector2i(10, 10)
	)
	assert(placed.ok, str(placed.get("errors", [])))
	_assert_visible_base_on_footprint_bottom(placed.instance, brazier, design_size)

	var resized := MapEditorInstanceService.resize_instance(
		document,
		str(placed.instance.instance_id),
		1
	)
	assert(resized.ok, str(resized.get("errors", [])))
	assert(bool(resized.instance.get("instance_custom_scale", false)))
	_assert_visible_base_on_footprint_bottom(resized.instance, brazier, design_size)

	# Simulate a saved legacy resized instance. Profile refresh must repair only
	# its derived anchor while retaining the user's footprint, scale and offset.
	var legacy_custom: Dictionary = resized.instance.duplicate(true)
	legacy_custom["anchor_px"] = brazier.anchor_px.duplicate()
	legacy_custom["placement_anchor_px"] = brazier.anchor_px.duplicate()
	var preserved_footprint: Array = legacy_custom.footprint_tiles.duplicate()
	var preserved_scale: Array = legacy_custom.scale.duplicate()
	var preserved_offset: Array = legacy_custom.offset_px.duplicate()
	InstanceProfileService.refresh_from_asset(legacy_custom, brazier)
	assert(legacy_custom.footprint_tiles == preserved_footprint)
	assert(legacy_custom.scale == preserved_scale)
	assert(legacy_custom.offset_px == preserved_offset)
	_assert_visible_base_on_footprint_bottom(legacy_custom, brazier, design_size)

	var wall := MapAssetCatalogService.find_asset("orc_tomb_wall_straight_x_l4_v01")
	assert(not wall.is_empty())
	assert(not wall.has("placement_anchor_policy_id"))
	assert(wall.placement_anchor_px == wall.anchor_px)

	var corrected_assets := 0
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if not PlacementAnchorPolicy.applies_to(asset):
			continue
		corrected_assets += 1
		assert(str(asset.get("placement_anchor_policy_id", "")) == PlacementAnchorPolicy.POLICY_ID)
		var footprint: Array = asset.get("footprint_tiles", [1, 1])
		var scale := float(asset.get("approved_scale", 1.0))
		var expected := PlacementAnchorPolicy.placement_anchor_px(
			asset,
			footprint,
			Vector2(scale, scale)
		)
		var actual: Array = asset.get("placement_anchor_px", [])
		assert(actual.size() == 2)
		assert(Vector2(float(actual[0]), float(actual[1])).distance_to(expected) < EPSILON)
	assert(corrected_assets > 0)

	print(
		"MSE_FOOT_TILE_PLACEMENT_ALIGNMENT_PASS corrected=%d brazier_delta=%.2f"
		% [
			corrected_assets,
			float(brazier.anchor_px[1]) - float(brazier.placement_anchor_px[1]),
		]
	)
	get_tree().quit(0)


func _assert_visible_base_on_footprint_bottom(
	instance: Dictionary,
	asset: Dictionary,
	design_size: Vector2i
) -> void:
	var image_size: Array = asset.get("image_size", [1, 1])
	var geometry := MapEditorCanvasPreview.instance_visual_geometry(
		instance,
		design_size,
		Vector2.ZERO,
		1.0,
		Vector2(float(image_size[0]), float(image_size[1])),
		asset
	)
	var source_anchor: Array = asset.get("anchor_px", [0, 0])
	var placement_anchor: Vector2 = geometry.anchor
	var visual_scale: Vector2 = geometry.visual_scale
	var visible_base: Vector2 = geometry.center + Vector2(
		(float(source_anchor[0]) - placement_anchor.x) * visual_scale.x,
		(float(source_anchor[1]) - placement_anchor.y) * visual_scale.y
	)
	var tile: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get("footprint_tiles", [1, 1])
	var offset: Array = instance.get("offset_px", [0, 0])
	var expected_bottom := MapEditorCoordinate.tile_to_ground_px(
		Vector2(
			float(tile[0]) + float(footprint[0]),
			float(tile[1]) + float(footprint[1])
		),
		design_size
	) + Vector2(float(offset[0]), float(offset[1]))
	assert(
		visible_base.distance_to(expected_bottom) < EPSILON,
		"visible_base=%s expected_bottom=%s instance=%s"
		% [visible_base, expected_bottom, str(instance.get("instance_id", ""))]
	)
