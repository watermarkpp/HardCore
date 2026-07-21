extends Node


const WALL_ASSET_IDS := [
	"user.e2f623a6d2ab8030",
	"user.50eeffae6614c9a2",
]


func _ready() -> void:
	var document := MapEditorTypes.new_map(
		"placement_boundary_anchor",
		990121,
		"Placement Boundary Anchor",
		Vector2i(56, 56)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		WALL_ASSET_IDS[0],
		"terrain",
		Vector2i(20, 20)
	)
	assert(placed.ok, str(placed.get("errors", [])))
	var instance_id := str(placed.instance.instance_id)
	for wall_asset_id: String in WALL_ASSET_IDS:
		var wall_asset := MapAssetCatalogService.find_asset(wall_asset_id)
		assert(str(wall_asset.get("object_class", "")) == "wall")
		assert(
			MapEditorPlacementValidator._is_within_map_bounds(
				wall_asset,
				Vector2i(53, 53),
				Vector2i(5, 5),
				Vector2i(56, 56)
			),
			"沃玛森林城墙必须允许视觉越过右下边缘：%s" % wall_asset_id
		)
		assert(
			not MapEditorPlacementValidator._is_within_map_bounds(
				wall_asset,
				Vector2i(54, 53),
				Vector2i(5, 5),
				Vector2i(56, 56)
			),
			"沃玛森林城墙锚点不得越过右下边缘：%s" % wall_asset_id
		)

	var upper_left := MapEditorInstanceService.move_instance(
		document,
		instance_id,
		Vector2i(0, 0)
	)
	assert(upper_left.ok, str(upper_left.get("errors", [])))
	var negative := MapEditorInstanceService.move_instance(
		document,
		instance_id,
		Vector2i(-1, 0)
	)
	assert(
		not negative.ok and "footprint_out_of_bounds" in negative.errors,
		"素材锚点不得离开地图左上边界"
	)

	# This 5x5 wall uses tile + footprint / 2 as its placement anchor.
	# At 53,53 that anchor is 55.5,55.5: still inside a 56x56 map even
	# though the visual rectangle and part of its logical footprint overhang.
	var lower_right := MapEditorInstanceService.move_instance(
		document,
		instance_id,
		Vector2i(53, 53)
	)
	assert(lower_right.ok, str(lower_right.get("errors", [])))
	assert(lower_right.instance.tile == [53, 53])
	var past_anchor := MapEditorInstanceService.move_instance(
		document,
		instance_id,
		Vector2i(54, 53)
	)
	assert(
		not past_anchor.ok and "footprint_out_of_bounds" in past_anchor.errors,
		"素材摆放锚点不得越过地图右下边界"
	)

	# Movement must validate the instance's resized footprint rather than
	# silently falling back to the catalog's default footprint.
	var located := MapEditorInstanceService._locate(document, instance_id)
	located.instance["footprint_tiles"] = [7, 7]
	MapEditorInstanceService._located_replace(
		document,
		located,
		located.instance
	)
	var resized_edge := MapEditorInstanceService.move_instance(
		document,
		instance_id,
		Vector2i(52, 52)
	)
	assert(resized_edge.ok, str(resized_edge.get("errors", [])))
	var resized_past_anchor := MapEditorInstanceService.move_instance(
		document,
		instance_id,
		Vector2i(53, 52)
	)
	assert(not resized_past_anchor.ok)

	# Ground cells keep their strict, cell-contained map boundary.
	var ground_outside := MapEditorPlacementValidator.validate(
		document,
		"ground.dark_grass.001",
		Vector2i(56, 0)
	)
	assert(
		not ground_outside.ok
		and "footprint_out_of_bounds" in ground_outside.errors
	)
	var edge_clipping_asset := {}
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if bool(asset.get("allows_edge_clipping", false)):
			edge_clipping_asset = asset
			break
	assert(not edge_clipping_asset.is_empty())
	assert(
		MapEditorPlacementValidator.validate(
			document,
			str(edge_clipping_asset.asset_id),
			Vector2i(55, 55)
		).ok
	)
	assert(
		not MapEditorPlacementValidator.validate(
			document,
			str(edge_clipping_asset.asset_id),
			Vector2i(56, 55)
		).ok
	)

	print("MSE_PLACEMENT_BOUNDARY_ANCHOR_PASS")
	get_tree().quit(0)
