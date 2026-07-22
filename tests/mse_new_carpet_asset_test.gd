extends Node


const CATALOG_PATH := "res://assets/data/assets/map_new_carpet_asset_catalog.json"
const PACKAGE_ID := "MSE_ISO_CARPETS_6_GEOMETRY_CORRECTED"
const PALETTE_PATH := "装饰物1/地毯"
const PACKAGE_ASSET_IDS := [
	"CARPET_RED_SKULL_LEFT",
	"CARPET_BLACK_ARCANE_LEFT",
	"CARPET_PURPLE_GOTHIC_LEFT",
	"CARPET_RED_SKULL_RIGHT",
	"CARPET_BLACK_ARCANE_RIGHT",
	"CARPET_PURPLE_GOTHIC_RIGHT",
]


func _ready() -> void:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var catalog: Variant = JSON.parse_string(file.get_as_text())
	assert(catalog is Dictionary)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(catalog.get("replaces_package_id", "")) == "mse_new_carpet_6_v1")
	assert(str(catalog.get("classification", "")) == PALETTE_PATH)
	assert(int(catalog.get("source_count", 0)) == 6)
	assert(int(catalog.get("asset_count", 0)) == 6)
	assert(str(catalog.get("editor_review_status", "")) == "passed")
	var geometry: Dictionary = catalog.get("geometry", {})
	assert(_int_pair(geometry.get("iso_x_vector", [])) == Vector2i(64, 32))
	assert(_int_pair(geometry.get("iso_y_vector", [])) == Vector2i(-64, 32))
	assert(bool(geometry.get("short_ends_are_seamless", false)))
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
		assert(str(asset.get("package_asset_id", "")) == PACKAGE_ASSET_IDS[index])
		assert(not ids.has(asset_id))
		ids[asset_id] = true
		assert(str(asset.get("package_id", "")) == PACKAGE_ID)
		assert(str(asset.get("palette_path", "")) == PALETTE_PATH)
		assert(str(asset.get("asset_type", "")) == "decoration")
		assert(str(asset.get("category", "")) == "decoration")
		assert(str(asset.get("object_class", "")) == "carpet")
		assert(str(asset.get("anchor_mode", "")) == "tile_center")
		assert(str(asset.get("default_object_role", "")) == "decoration")
		var expected_footprint := (
			Vector2i(10, 5) if index < 3 else Vector2i(5, 10)
		)
		assert(_int_pair(asset.get("footprint_tiles", [])) == expected_footprint)
		assert(_int_pair(asset.get("canvas_size", [])) == Vector2i(960, 480))
		assert(_int_pair(asset.get("anchor_px", [])) == Vector2i(480, 240))
		assert(str(asset.get("authored_default_layer", "")) == "ground_overlay")
		assert(str(asset.get("default_layer", "")) == "object_base")
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert(not bool(asset.get("manual_collision_expected", true)))
		assert(_int_pair(asset.get("collision_footprint_tiles", [])) == Vector2i.ZERO)
		assert((asset.get("collision_cells", []) as Array).is_empty())
		assert(not bool(asset.get("occlusion", true)))
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("calibration_status", "")) == "placeable")
		assert(
			str(asset.get("source_calibration_status", ""))
			== "generated_needs_editor_review"
		)
		assert(bool(asset.get("short_end_seamless", false)))
		assert(not bool(asset.get("runtime_rotation_required", true)))
		assert(not bool(asset.get("runtime_mirroring_required", true)))
		assert(
			str(asset.get("processing", ""))
			== "verified_geometry_corrected_package_rgba_passthrough"
		)

		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(image.get_size() == Vector2i(960, 480))
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)
		assert(image.get_pixel(0, 0).a == 0.0)
		var visible_bounds: Array = asset.get("visible_bounds_px", [])
		assert(visible_bounds.size() == 4)
		assert(int(visible_bounds[0]) >= 0 and int(visible_bounds[1]) >= 0)
		assert(int(visible_bounds[2]) <= image.get_width())
		assert(int(visible_bounds[3]) <= image.get_height())
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
		+ "sources=6 assets=6 geometry=corrected stable_ids=preserved "
		+ "classification=装饰物1/地毯 collision=none"
	)
	get_tree().quit(0)


func _int_pair(values: Array) -> Vector2i:
	assert(values.size() == 2)
	return Vector2i(int(values[0]), int(values[1]))
