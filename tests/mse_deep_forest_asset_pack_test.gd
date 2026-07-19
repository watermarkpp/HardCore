extends Node


const CATALOG_PATH := "res://assets/data/assets/map_deep_forest_asset_catalog.json"
const PACKAGE_ID := "MSE_ISO_Deep_Forest_AssetPack_56_v3_LOCAL_FREE"
const EXPECTED_COUNTS := {
	"single_trees": 10,
	"fallen_trees": 12,
	"grass_groundcover": 10,
	"stumps": 12,
}


func _ready() -> void:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var catalog: Variant = JSON.parse_string(file.get_as_text())
	assert(catalog is Dictionary)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(catalog.get("classification", "")) == "装饰物1/树木/MSE深林44")
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 44)

	var ids := {}
	var category_counts := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(asset_id.begins_with("mse.deep_forest."))
		assert(not ids.has(asset_id))
		ids[asset_id] = true
		assert(str(asset.get("object_class", "")) == "tree")
		assert(str(asset.get("category", "")) == "tree")
		assert(str(asset.get("default_object_role", "")) == "decoration")
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(str(asset.get("collision_profile_id", "")) == "none_visual")
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert(bool(asset.get("manual_collision_expected", false)))
		assert(str(asset.get("collision_authority", "")) == "manual_by_user")
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
		assert((asset.get("placement_clearance_cells", []) as Array).is_empty())
		assert(bool(asset.get("allows_edge_clipping", false)))
		assert(str(asset.get("content_layer", "")) == "personal_expansion")
		assert(str(asset.get("calibration_status", "")) == "placeable")
		assert(bool(asset.get("placeable", false)))
		assert(
			str(asset.get("palette_path", "")).begins_with(
				"装饰物1/树木/MSE深林44/"
			)
		)

		var category := str(asset.get("source_category", ""))
		category_counts[category] = int(category_counts.get(category, 0)) + 1
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)
		var anchor: Array = asset.get("anchor_px", [])
		assert(
			anchor.size() == 2
			and float(anchor[0]) >= 0.0
			and float(anchor[0]) < image.get_width()
			and float(anchor[1]) >= 0.0
			and float(anchor[1]) < image.get_height()
		)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		assert(bool(effective.get("placeable", false)), asset_id)

	assert(category_counts == EXPECTED_COUNTS)
	var document := MapEditorTypes.new_map(
		"deep_forest_asset_pack_test",
		990123,
		"Deep Forest Asset Pack Test",
		Vector2i(64, 64)
	)
	# Reproduce the real editor case: the user may place a visual tree over an
	# existing colliding prop. The tree's menu-selected default role must stay
	# decoration so its intentionally empty collision never becomes an
	# obstacle-only overlap rejection.
	document.layers.terrain_base.append({
		"instance_id": "existing_blocker",
		"asset_id": "test.existing_blocker",
		"tile": [18, 18],
		"footprint_tiles": [8, 8],
		"collision_policy": "preset",
	})
	for asset: Dictionary in assets:
		assert(
			MapEditorPlacementValidator.validate(
				document,
				str(asset.asset_id),
				Vector2i(63, 63)
			).ok,
			str(asset.asset_id)
		)
		assert(
			not MapEditorPlacementValidator.validate(
				document,
				str(asset.asset_id),
				Vector2i(64, 63)
			).ok,
			str(asset.asset_id)
		)
	var placed := MapEditorInstanceService.create_instance(
		document,
		str(assets[0].asset_id),
		str(assets[0].default_object_role),
		Vector2i(20, 20)
	)
	assert(placed.ok, str(placed.get("errors", [])))
	assert(str(placed.instance.collision_policy) == "none")
	assert(str(placed.instance.collision_authority) == "manual_by_user")
	assert((placed.instance.collision_cells as Array).is_empty())
	var resized := MapEditorInstanceService.resize_instance(
		document,
		str(placed.instance.instance_id),
		-1
	)
	assert(resized.ok, str(resized.get("errors", [])))
	assert(str(resized.instance.collision_policy) == "none")
	assert(resized.instance.collision_footprint_tiles == [0, 0])
	assert((resized.instance.collision_cells as Array).is_empty())

	print(
		"MSE_DEEP_FOREST_ASSET_PACK_PASS "
		+ "assets=44 categories=4 alpha=44 collision=none role=decoration "
		+ "forest_clusters=excluded"
	)
	get_tree().quit(0)
