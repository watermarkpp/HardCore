extends Node


const CATALOG_PATH := (
	"res://assets/data/assets/map_new_ground_pillar_throne_asset_catalog.json"
)
const PACKAGE_ID := "mse_new_ground_pillar_throne_42_v1"
const EXPECTED_COUNTS := {"地面": 12, "立柱": 24, "王座": 6}


func _ready() -> void:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var catalog: Variant = JSON.parse_string(file.get_as_text())
	assert(catalog is Dictionary)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(int(catalog.get("source_count", 0)) == 6)
	assert(int(catalog.get("asset_count", 0)) == 42)
	var catalog_counts: Dictionary = catalog.get("group_counts", {})
	for source_group: String in EXPECTED_COUNTS:
		assert(
			int(catalog_counts.get(source_group, 0))
			== int(EXPECTED_COUNTS[source_group])
		)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 42)
	var catalog_errors := MapAssetCatalogService.validate_catalog()
	assert(catalog_errors.is_empty(), str(catalog_errors))

	var ids := {}
	var counts := {"地面": 0, "立柱": 0, "王座": 0}
	var preview := MapEditorCanvasPreview.new()
	add_child(preview)
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(not asset_id.is_empty())
		assert(not ids.has(asset_id), asset_id)
		ids[asset_id] = true
		assert(str(asset.get("package_id", "")) == PACKAGE_ID)
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("calibration_status", "")) == "placeable")
		assert(str(asset.get("content_layer", "")) == "personal_expansion")
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert((asset.get("collision_cells", []) as Array).is_empty())
		assert(
			_int_pair(asset.get("collision_footprint_tiles", []))
			== Vector2i.ZERO
		)
		var source_group := str(asset.get("source_group", ""))
		assert(counts.has(source_group), source_group)
		counts[source_group] = int(counts[source_group]) + 1

		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)
		assert(image.get_pixel(0, 0).a == 0.0, image_path)
		var visible_bounds: Array = asset.get("visible_bounds_px", [])
		assert(visible_bounds.size() == 4)
		assert(int(visible_bounds[0]) == 4 and int(visible_bounds[1]) == 4)
		assert(int(visible_bounds[2]) == image.get_width() - 4)
		assert(int(visible_bounds[3]) == image.get_height() - 4)
		assert(preview._texture_for_asset(asset_id) != null, asset_id)

		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		assert(str(effective.get("palette_path", "")) == str(asset.palette_path))
		if source_group == "地面":
			_assert_ground_asset(asset, effective)
		else:
			_assert_decoration_asset(asset, effective, source_group)

	for source_group: String in EXPECTED_COUNTS:
		assert(
			int(counts.get(source_group, 0))
			== int(EXPECTED_COUNTS[source_group])
		)
	_assert_decoration_placement(assets)
	print(
		"MSE_NEW_GROUND_PILLAR_THRONE_ASSET_PASS "
		+ "sources=6 assets=42 ground=12 pillars=24 thrones=6"
	)
	get_tree().quit(0)


func _assert_ground_asset(asset: Dictionary, effective: Dictionary) -> void:
	assert(str(asset.get("asset_type", "")) == "ground_brush")
	assert(str(asset.get("category", "")) == "ground")
	assert(str(asset.get("object_class", "")) == "ground")
	assert(str(asset.get("palette_path", "")) == "地面/新增石板地面")
	assert(_int_pair(asset.get("footprint_tiles", [])) == Vector2i.ONE)
	assert(str(asset.get("anchor_mode", "")) == "tile_center")
	assert(bool(asset.get("paintable", false)))
	assert(not bool(asset.get("manual_collision_expected", true)))
	assert(
		_int_pair(effective.get("canvas_size", []))
		== Vector2i(64, 32)
	)
	assert(
		_int_pair(effective.get("anchor_px", []))
		== Vector2i(32, 16)
	)
	var normalized := MapEditorGroundService.normalized_ground_image(
		str(asset.asset_id)
	)
	assert(normalized != null and not normalized.is_empty())
	assert(normalized.get_size() == Vector2i(64, 32))
	assert(normalized.get_pixel(0, 0).a == 0.0)
	assert(normalized.get_pixel(63, 0).a == 0.0)


func _assert_decoration_asset(
	asset: Dictionary,
	effective: Dictionary,
	source_group: String
) -> void:
	assert(str(asset.get("asset_type", "")) == "large_prop")
	assert(str(asset.get("category", "")) == "decoration")
	assert(str(asset.get("object_class", "")) == "decoration")
	assert(str(asset.get("anchor_mode", "")) == "foot_tile")
	assert(str(asset.get("default_object_role", "")) == "decoration")
	assert(bool(asset.get("manual_collision_expected", false)))
	assert(str(asset.get("collision_authority", "")) == "manual_by_user")
	assert(
		str(asset.get("palette_path", ""))
		== "装饰物1/%s" % source_group
	)
	var expected_footprint := [3, 3] if source_group == "立柱" else [6, 6]
	assert(
		_int_pair(asset.get("footprint_tiles", []))
		== _int_pair(expected_footprint)
	)
	assert(
		str(effective.get("placement_anchor_policy_id", ""))
		== MapAssetPlacementAnchorPolicy.POLICY_ID
	)


func _assert_decoration_placement(assets: Array) -> void:
	var document := MapEditorTypes.new_map(
		"new_ground_pillar_throne_asset_test",
		990191,
		"New Ground Pillar Throne Asset Test",
		Vector2i(64, 64)
	)
	for source_group: String in ["立柱", "王座"]:
		var candidates := assets.filter(
			func(candidate: Dictionary) -> bool:
				if str(candidate.get("source_group", "")) != source_group:
					return false
				return bool(
					MapAssetCatalogService.find_asset(
						str(candidate.get("asset_id", ""))
					).get("placeable", false)
				)
		)
		# A user may intentionally remove every asset in an old group from the
		# palette. The package data remains valid, but deleted entries must not
		# be used for a placement assertion.
		if candidates.is_empty():
			continue
		var asset: Dictionary = candidates[0]
		var placed := MapEditorInstanceService.create_instance(
			document,
			str(asset.asset_id),
			"decoration",
			Vector2i(20, 20),
			"object_base"
		)
		assert(placed.ok, str(placed.get("errors", [])))
		assert(str(placed.instance.collision_policy) == "none")
		assert((placed.instance.collision_cells as Array).is_empty())


func _int_pair(values: Array) -> Vector2i:
	assert(values.size() == 2)
	return Vector2i(int(values[0]), int(values[1]))
