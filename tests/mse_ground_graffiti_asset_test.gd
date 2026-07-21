extends Node


const CATALOG_PATH := "res://assets/data/assets/map_ground_graffiti_asset_catalog.json"
const PACKAGE_ID := "mse_ground_graffiti_8_dual_size_v1"
const VARIANTS := {
	"3x3": {"count": 8, "footprint": [3, 3], "canvas": [192, 96]},
	"10x10": {"count": 8, "footprint": [10, 10], "canvas": [640, 320]},
}


func _ready() -> void:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var catalog: Variant = JSON.parse_string(file.get_as_text())
	assert(catalog is Dictionary)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(catalog.get("classification", "")) == "装饰物1/地面涂鸦")
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 16)

	var ids := {}
	var variant_counts := {}
	var source_variants := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(asset_id.begins_with("mse.ground_graffiti."))
		assert(not ids.has(asset_id))
		ids[asset_id] = true
		assert(str(asset.get("object_class", "")) == "ground_graffiti")
		assert(str(asset.get("category", "")) == "ground_graffiti")
		assert(str(asset.get("asset_type", "")) == "decoration")
		assert(str(asset.get("default_object_role", "")) == "decoration")
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert(not bool(asset.get("manual_collision_expected", true)))
		assert((asset.get("collision_cells", []) as Array).is_empty())
		assert(
			_int_pair(asset.get("collision_footprint_tiles", []))
			== Vector2i.ZERO
		)
		assert(bool(asset.get("allows_edge_clipping", false)))
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("anchor_mode", "")) == "tile_center")

		var variant_id := str(asset.get("size_variant", ""))
		assert(VARIANTS.has(variant_id), variant_id)
		var expected: Dictionary = VARIANTS[variant_id]
		assert(
			_int_pair(asset.get("footprint_tiles", []))
			== _int_pair(expected.footprint)
		)
		assert(
			_int_pair(asset.get("canvas_size", []))
			== _int_pair(expected.canvas)
		)
		var label := str(asset.get("size_label", ""))
		assert(
			str(asset.get("palette_path", ""))
			== "装饰物1/地面涂鸦/%s" % label
		)
		variant_counts[variant_id] = int(variant_counts.get(variant_id, 0)) + 1
		var source_key := str(asset.get("source_index", 0))
		source_variants[source_key] = int(source_variants.get(source_key, 0)) + 1

		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(
			image.get_width() == int(expected.canvas[0])
			and image.get_height() == int(expected.canvas[1])
		)
		assert(image.detect_alpha() != Image.ALPHA_NONE)
		assert(image.get_pixel(0, 0).a == 0.0)
		var anchor: Array = asset.get("anchor_px", [])
		assert(
			_int_pair(anchor)
			== Vector2i(
				int(expected.canvas[0]) / 2,
				int(expected.canvas[1]) / 2
			)
		)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)

	for variant_id: String in VARIANTS:
		assert(
			int(variant_counts.get(variant_id, 0))
			== int(VARIANTS[variant_id].count)
		)
	assert(source_variants.size() == 8)
	for count: int in source_variants.values():
		assert(count == 2)

	var document := MapEditorTypes.new_map(
		"ground_graffiti_asset_test",
		990124,
		"Ground Graffiti Asset Test",
		Vector2i(64, 64)
	)
	for asset: Dictionary in assets:
		var placed := MapEditorInstanceService.create_instance(
			document,
			str(asset.asset_id),
			"decoration",
			Vector2i(20, 20),
			"object_base"
		)
		assert(placed.ok, str(placed.get("errors", [])))
		assert(str(placed.instance.collision_policy) == "none")
		assert(
			_int_pair(placed.instance.collision_footprint_tiles)
			== Vector2i.ZERO
		)
		assert((placed.instance.collision_cells as Array).is_empty())

	var three_by_three: Dictionary = assets.filter(
		func(asset: Dictionary) -> bool:
			return str(asset.size_variant) == "3x3"
	)[0]
	var placed_three := MapEditorInstanceService.create_instance(
		document,
		str(three_by_three.asset_id),
		"decoration",
		Vector2i(30, 30),
		"object_base"
	)
	assert(placed_three.ok)
	var resized := MapEditorInstanceService.resize_instance(
		document,
		str(placed_three.instance.instance_id),
		-1
	)
	assert(resized.ok, str(resized.get("errors", [])))
	assert(str(resized.instance.collision_policy) == "none")
	assert(
		_int_pair(resized.instance.collision_footprint_tiles)
		== Vector2i.ZERO
	)

	print(
		"MSE_GROUND_GRAFFITI_ASSET_PASS "
		+ "sources=8 assets=16 variants=3x3,10x10 collision=none"
	)
	get_tree().quit(0)


func _int_pair(values: Array) -> Vector2i:
	assert(values.size() == 2)
	return Vector2i(int(values[0]), int(values[1]))
