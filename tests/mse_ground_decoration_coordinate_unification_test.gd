extends Node

const PlacementAnchorPolicy := preload(
	"res://scripts/map_assets/map_asset_placement_anchor_policy.gd"
)
const EPSILON := 0.01
const REPRESENTATIVE_DECORATIONS := [
	"cave_dungeon.brazier_01",
	"cave_dungeon.magic_fire_blue_01",
	"cave_dungeon.rock_cluster_01",
]


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var design_size := Vector2i(38, 38)
	_assert_ground_contract(design_size)
	for asset_id: String in REPRESENTATIVE_DECORATIONS:
		_assert_decoration_contract(asset_id, design_size)
	var aligned_asset_count := _assert_all_decoration_assets(design_size)
	print(
		(
			"MSE_GROUND_DECORATION_COORDINATE_UNIFICATION_PASS "
			+ "ground=1 representatives=%d all_decorations=%d"
		)
		% [REPRESENTATIVE_DECORATIONS.size(), aligned_asset_count]
	)
	get_tree().quit(0)


func _assert_ground_contract(design_size: Vector2i) -> void:
	var tile := Vector2i(10, 10)
	var texture_rect := MapEditorCoordinate.cell_texture_rect_ground_px(
		Vector2(tile),
		design_size
	)
	var polygon := MapEditorCoordinate.cell_polygon_ground_px(tile, design_size)
	var polygon_center := Vector2.ZERO
	for point: Vector2 in polygon:
		polygon_center += point
	polygon_center /= float(polygon.size())
	assert(
		texture_rect.get_center().distance_to(polygon_center) < EPSILON,
		"ground texture and grid polygon must share one cell center"
	)
	assert(
		MapEditorCoordinate.ground_px_to_cell(polygon_center, design_size) == tile
	)


func _assert_decoration_contract(asset_id: String, design_size: Vector2i) -> void:
	var asset := MapAssetCatalogService.find_asset(asset_id)
	assert(not asset.is_empty(), asset_id)
	assert(str(asset.get("asset_type", "")) != "wall_module", asset_id)
	var document := MapEditorTypes.new_map(
		"decoration_contract_%s" % asset_id.replace(".", "_"),
		990183,
		"Decoration Coordinate Contract",
		design_size
	)
	var tile := Vector2i(10, 10)
	var placed := MapEditorInstanceService.create_instance(
		document,
		asset_id,
		"decoration",
		tile,
		"object_base"
	)
	assert(placed.ok, "%s:%s" % [asset_id, placed.get("errors", [])])
	var image_size: Array = asset.get("image_size", [1, 1])
	var geometry := MapEditorCanvasPreview.instance_visual_geometry(
		placed.instance,
		design_size,
		Vector2.ZERO,
		1.0,
		Vector2(float(image_size[0]), float(image_size[1])),
		asset
	)
	var commands := MapEditorCanvasPreview.instance_draw_commands(
		placed.instance,
		asset,
		2,
		0
	)
	assert(commands.size() == 1, asset_id)
	var command: Dictionary = commands[0]
	var raw_anchor: Array = command.get("anchor", [])
	assert(raw_anchor.is_empty(), "%s must not override its calibrated instance anchor" % asset_id)
	var draw_anchor := MapEditorCanvasPreview.draw_anchor_for_command(
		raw_anchor,
		geometry
	)
	assert(
		draw_anchor.distance_to(geometry.anchor) < EPSILON,
		"%s renderer and selection geometry must use the same anchor" % asset_id
	)
	var source_anchor_raw: Array = asset.get("anchor_px", [0, 0])
	var source_anchor := Vector2(
		float(source_anchor_raw[0]),
		float(source_anchor_raw[1])
	)
	var visible_base: Vector2 = geometry.center + (
		source_anchor - draw_anchor
	) * (geometry.visual_scale as Vector2)
	var footprint: Array = placed.instance.get("footprint_tiles", [1, 1])
	var expected_base := MapEditorCoordinate.tile_to_ground_px(
		Vector2(
			float(tile.x) + float(footprint[0]),
			float(tile.y) + float(footprint[1])
		),
		design_size
	)
	assert(
		visible_base.distance_to(expected_base) < EPSILON,
		"%s visible_base=%s expected=%s"
		% [asset_id, visible_base, expected_base]
	)


func _assert_all_decoration_assets(design_size: Vector2i) -> int:
	var aligned_count := 0
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if not PlacementAnchorPolicy.applies_to(asset):
			continue
		aligned_count += 1
		var footprint: Array = asset.get("footprint_tiles", [1, 1])
		var scale := float(asset.get("approved_scale", 1.0))
		var instance := {
			"instance_id": "contract_%s" % str(asset.get("asset_id", "")),
			"asset_id": str(asset.get("asset_id", "")),
			"tile": [10, 10],
			"footprint_tiles": footprint.duplicate(),
			"anchor_px": asset.get(
				"placement_anchor_px",
				asset.get("anchor_px", [0, 0])
			).duplicate(),
			"placement_anchor_px": asset.get(
				"placement_anchor_px",
				asset.get("anchor_px", [0, 0])
			).duplicate(),
			"scale": [scale, scale],
			"offset_px": [0, 0],
		}
		var image_size: Array = asset.get("image_size", [1, 1])
		var geometry := MapEditorCanvasPreview.instance_visual_geometry(
			instance,
			design_size,
			Vector2.ZERO,
			1.0,
			Vector2(float(image_size[0]), float(image_size[1])),
			asset
		)
		var commands := MapEditorCanvasPreview.instance_draw_commands(
			instance,
			asset,
			2,
			aligned_count
		)
		assert(commands.size() == 1, str(asset.get("asset_id", "")))
		var raw_anchor: Array = commands[0].get("anchor", [])
		assert(
			raw_anchor.is_empty(),
			"%s must use the calibrated instance anchor"
			% str(asset.get("asset_id", ""))
		)
		var draw_anchor := MapEditorCanvasPreview.draw_anchor_for_command(
			raw_anchor,
			geometry
		)
		assert(draw_anchor.distance_to(geometry.anchor) < EPSILON)
		var source_anchor_raw: Array = asset.get("anchor_px", [0, 0])
		var visible_base: Vector2 = geometry.center + (
			Vector2(
				float(source_anchor_raw[0]),
				float(source_anchor_raw[1])
			) - draw_anchor
		) * (geometry.visual_scale as Vector2)
		var expected_base := MapEditorCoordinate.tile_to_ground_px(
			Vector2(
				10.0 + float(footprint[0]),
				10.0 + float(footprint[1])
			),
			design_size
		)
		assert(
			visible_base.distance_to(expected_base) < EPSILON,
			str(asset.get("asset_id", ""))
		)
	assert(aligned_count > 0)
	return aligned_count
