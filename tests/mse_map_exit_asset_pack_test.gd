extends Node


const CATALOG_PATH := "res://assets/data/assets/map_exit_asset_catalog.json"
const REVIEW_PATH := (
	"res://assets/data/expansions/personal_expansion_001/"
	+ "map_asset_footprint_review_state.json"
)
const OVERRIDES_PATH := (
	"res://assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
)
const PACKAGE_ID := "user_map_exit_pack_20260822_v1"
const TARGET_PREFIX := "user.map_exit.20260822."


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), path)
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed


func _expected_ids() -> Array[String]:
	var result: Array[String] = []
	for sheet in range(1, 9):
		for row in range(1, 3):
			for column in range(1, 5):
				result.append(
					"%ss%02d_r%d_c%d" % [TARGET_PREFIX, sheet, row, column]
				)
	return result


func _pair_equals(left: Variant, right: Variant) -> bool:
	if not left is Array or not right is Array:
		return false
	var left_array: Array = left
	var right_array: Array = right
	if left_array.size() != right_array.size():
		return false
	for index in range(left_array.size()):
		var left_value: Variant = left_array[index]
		var right_value: Variant = right_array[index]
		var left_type := typeof(left_value)
		var right_type := typeof(right_value)
		if left_type in [TYPE_INT, TYPE_FLOAT] and right_type in [TYPE_INT, TYPE_FLOAT]:
			if int(left_value) != int(right_value):
				return false
		elif left_value != right_value:
			return false
	return true


func _ready() -> void:
	var expected_ids := _expected_ids()
	var expected_set := {}
	for asset_id in expected_ids:
		expected_set[asset_id] = true

	var catalog := _load_json(CATALOG_PATH)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 64)

	var review_doc := _load_json(REVIEW_PATH)
	var review_items: Dictionary = review_doc.get("items", {})
	assert(review_items is Dictionary)
	var override_doc := _load_json(OVERRIDES_PATH)
	var override_items: Dictionary = override_doc.get("overrides", {})
	assert(override_items is Dictionary)

	var seen := {}
	for asset_variant: Variant in assets:
		var asset: Dictionary = asset_variant
		var asset_id := str(asset.get("asset_id", ""))
		assert(expected_set.has(asset_id), asset_id)
		assert(not seen.has(asset_id), asset_id)
		seen[asset_id] = true
		assert(str(asset.get("package_id", "")) == PACKAGE_ID, asset_id)
		assert(str(asset.get("object_class", "")) == "map_entrance", asset_id)
		assert(str(asset.get("category", "")) == "map_entrance", asset_id)
		assert(str(asset.get("collision_policy", "")) == "none", asset_id)
		assert(_pair_equals(asset.get("collision_footprint_tiles", []), [0, 0]), asset_id)
		assert((asset.get("collision_cells", []) as Array).is_empty(), asset_id)
		assert(not bool(asset.get("manual_collision_expected", true)), asset_id)
		assert(bool(asset.get("placeable", false)), asset_id)

		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)

		var review_variant: Variant = review_items.get(asset_id, {})
		assert(review_variant is Dictionary, asset_id)
		var review: Dictionary = review_variant
		assert(str(review.get("status", "")) == "verified", asset_id)
		for field in [
			"display_name",
			"palette_path",
			"image",
			"source_sha256",
			"output_sha256",
		]:
			assert(review.get(field) == asset.get(field), "%s:%s" % [asset_id, field])

		var override_variant: Variant = override_items.get(asset_id, {})
		assert(override_variant is Dictionary, asset_id)
		var override: Dictionary = override_variant
		assert(_pair_equals(override.get("anchor_px", []), review.get("anchor_px", [])), asset_id)
		assert(
			_pair_equals(override.get("footprint_tiles", []), review.get("footprint_tiles", [])),
			asset_id
		)
		assert(
			_pair_equals(override.get("visual_footprint_tiles", []), review.get("footprint_tiles", [])),
			asset_id
		)
		assert(
			_pair_equals(override.get("occupancy_footprint_tiles", []), review.get("footprint_tiles", [])),
			asset_id
		)
		assert(
			_pair_equals(override.get("base_footprint_tiles", []), review.get("footprint_tiles", [])),
			asset_id
		)
		assert(_pair_equals(override.get("collision_footprint_tiles", []), [0, 0]), asset_id)
		assert((override.get("collision_cells", []) as Array).is_empty(), asset_id)
		assert(str(override.get("collision_policy", "")) == "none", asset_id)
		assert(str(override.get("collision_profile_id", "")) == "none_visual", asset_id)
		assert(str(override.get("navigation_policy", "")) == "ignore", asset_id)
		assert(not bool(override.get("manual_collision_expected", true)), asset_id)
		assert(bool(override.get("placeable", false)), asset_id)
		assert(str(override.get("calibration_status", "")) == "placeable", asset_id)
		assert(str(override.get("content_layer", "")) == "personal_expansion", asset_id)

		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		assert(_pair_equals(effective.get("anchor_px", []), review.get("anchor_px", [])), asset_id)
		assert(
			_pair_equals(effective.get("footprint_tiles", []), review.get("footprint_tiles", [])),
			asset_id
		)
		assert(_pair_equals(effective.get("collision_footprint_tiles", []), [0, 0]), asset_id)
		assert((effective.get("collision_cells", []) as Array).is_empty(), asset_id)
		assert(str(effective.get("collision_policy", "")) == "none", asset_id)
		assert(bool(effective.get("placeable", false)), asset_id)

	assert(seen.size() == expected_ids.size())

	var document := MapEditorTypes.new_map(
		"map_exit_asset_pack_test",
		990122,
		"Map Exit Asset Pack Test",
		Vector2i(64, 64)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		expected_ids[0],
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
		+ "assets=64 package=user_map_exit_pack_20260822_v1 "
		+ "review=verified overrides=64 collision=none placeable=true"
	)
	get_tree().quit(0)
