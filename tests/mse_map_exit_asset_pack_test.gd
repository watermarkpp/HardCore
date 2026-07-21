extends Node


const CATALOG_PATH := "res://assets/data/assets/map_exit_asset_catalog.json"
const PACKAGE_ID := "mse_iso_map_exit_assets_64_v1"


func _ready() -> void:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var catalog: Variant = JSON.parse_string(file.get_as_text())
	assert(catalog is Dictionary)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 64)

	var ids := {}
	var theme_counts := {}
	var set_counts := {}
	var opening_visible_count := 0
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(asset_id.begins_with("mse.map_exit."))
		assert(not ids.has(asset_id))
		ids[asset_id] = true
		assert(str(asset.get("object_class", "")) == "map_entrance")
		assert(str(asset.get("category", "")) == "map_entrance")
		assert(str(asset.get("collision_policy", "")) == "none")
		var collision_footprint: Array = asset.get(
			"collision_footprint_tiles",
			[]
		)
		assert(
			collision_footprint.size() == 2
			and int(collision_footprint[0]) == 0
			and int(collision_footprint[1]) == 0
		)
		assert((asset.get("collision_cells", []) as Array).is_empty())
		assert(not bool(asset.get("manual_collision_expected", true)))
		assert(bool(asset.get("allows_edge_clipping", false)))
		assert(str(asset.get("semantic_role", "")) == "map_portal")
		assert(bool(asset.get("trigger_on_enter", false)))
		assert(str(asset.get("content_layer", "")) == "personal_expansion")
		assert(str(asset.get("calibration_status", "")) == "placeable")
		assert(
			str(asset.get("palette_path", "")).begins_with(
				"装饰物1/地图出入口/MSE固定64/"
			)
		)
		assert(not bool(asset.get("requires_runtime_rotation", true)))
		assert(not bool(asset.get("allow_flip", true)))

		var theme := str(asset.get("theme", ""))
		var set_id := str(asset.get("set_id", ""))
		theme_counts[theme] = int(theme_counts.get(theme, 0)) + 1
		set_counts["%s/%s" % [theme, set_id]] = (
			int(set_counts.get("%s/%s" % [theme, set_id], 0)) + 1
		)
		if bool(asset.get("opening_visible", false)):
			opening_visible_count += 1

		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		assert(bool(effective.get("placeable", false)), asset_id)

	assert(theme_counts.size() == 4)
	for theme: String in ["deep_forest", "desert_cave", "shrine", "temple"]:
		assert(int(theme_counts.get(theme, 0)) == 16)
		for set_id: String in ["A", "B"]:
			assert(int(set_counts.get("%s/%s" % [theme, set_id], 0)) == 8)
	assert(opening_visible_count == 40)

	var document := MapEditorTypes.new_map(
		"map_exit_asset_pack_test",
		990122,
		"Map Exit Asset Pack Test",
		Vector2i(64, 64)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		str(assets[0].asset_id),
		"terrain",
		Vector2i(20, 20)
	)
	assert(placed.ok, str(placed.get("errors", [])))
	assert(str(placed.instance.collision_policy) == "none")
	assert(
		int(placed.instance.collision_footprint_tiles[0]) == 0
		and int(placed.instance.collision_footprint_tiles[1]) == 0
	)
	assert((placed.instance.collision_cells as Array).is_empty())

	print(
		"MSE_MAP_EXIT_ASSET_PACK_PASS "
		+ "assets=64 themes=4 sets=8 alpha=64 collision=none"
	)
	get_tree().quit(0)
