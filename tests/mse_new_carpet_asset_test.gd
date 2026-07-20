extends Node


const CATALOG_PATH := "res://assets/data/assets/map_new_carpet_asset_catalog.json"
const PACKAGE_ID := "mse_new_carpet_6_v1"
const PALETTE_PATH := "装饰物1/地毯"


func _ready() -> void:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var catalog: Variant = JSON.parse_string(file.get_as_text())
	assert(catalog is Dictionary)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(catalog.get("classification", "")) == PALETTE_PATH)
	assert(int(catalog.get("source_count", 0)) == 6)
	assert(int(catalog.get("asset_count", 0)) == 6)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 6)
	var catalog_errors := MapAssetCatalogService.validate_catalog()
	assert(catalog_errors.is_empty(), str(catalog_errors))

	var preview := MapEditorCanvasPreview.new()
	add_child(preview)
	var document := MapEditorTypes.new_map(
		"new_carpet_asset_test",
		990192,
		"New Carpet Asset Test",
		Vector2i(64, 64)
	)
	var ids := {}
	for index in assets.size():
		var asset: Dictionary = assets[index]
		var asset_id := str(asset.get("asset_id", ""))
		assert(asset_id == "mse.new_carpet.%02d" % (index + 1))
		assert(not ids.has(asset_id))
		ids[asset_id] = true
		assert(str(asset.get("package_id", "")) == PACKAGE_ID)
		assert(str(asset.get("palette_path", "")) == PALETTE_PATH)
		assert(str(asset.get("asset_type", "")) == "decoration")
		assert(str(asset.get("category", "")) == "decoration")
		assert(str(asset.get("object_class", "")) == "carpet")
		assert(str(asset.get("anchor_mode", "")) == "tile_center")
		assert(str(asset.get("default_object_role", "")) == "decoration")
		assert(_int_pair(asset.get("footprint_tiles", [])) == Vector2i(8, 8))
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert(not bool(asset.get("manual_collision_expected", true)))
		assert(_int_pair(asset.get("collision_footprint_tiles", [])) == Vector2i.ZERO)
		assert((asset.get("collision_cells", []) as Array).is_empty())
		assert(not bool(asset.get("occlusion", true)))
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("calibration_status", "")) == "placeable")

		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)
		assert(image.get_pixel(0, 0).a == 0.0)
		var visible_bounds: Array = asset.get("visible_bounds_px", [])
		assert(visible_bounds.size() == 4)
		assert(int(visible_bounds[0]) == 4 and int(visible_bounds[1]) == 4)
		assert(int(visible_bounds[2]) == image.get_width() - 4)
		assert(int(visible_bounds[3]) == image.get_height() - 4)
		assert(preview._texture_for_asset(asset_id) != null, asset_id)

		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		assert(str(effective.get("palette_path", "")) == PALETTE_PATH)
		assert(
			not effective.has("placement_anchor_policy_id"),
			asset_id
		)
		var placed := MapEditorInstanceService.create_instance(
			document,
			asset_id,
			"decoration",
			Vector2i(20, 20),
			"object_base"
		)
		assert(placed.ok, str(placed.get("errors", [])))
		assert(str(placed.instance.collision_policy) == "none")
		assert((placed.instance.collision_cells as Array).is_empty())

	print(
		"MSE_NEW_CARPET_ASSET_PASS "
		+ "sources=6 assets=6 classification=装饰物1/地毯 collision=none"
	)
	get_tree().quit(0)


func _int_pair(values: Array) -> Vector2i:
	assert(values.size() == 2)
	return Vector2i(int(values[0]), int(values[1]))
