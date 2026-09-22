extends Node


const CATALOG_PATH := "res://assets/data/assets/map_small_decoration_asset_catalog.json"
const REVIEW_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
const OVERRIDES_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
const PACKAGE_ID := "mse_small_decoration_pack_20260822_v1"


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed


func _assert_int_array(actual: Variant, expected: Array, label: String) -> void:
	assert(actual is Array and (actual as Array).size() == expected.size(), label)
	for index: int in expected.size():
		assert(int((actual as Array)[index]) == int(expected[index]), label)


func _ready() -> void:
	var expected_ids := {}
	for index: int in 48:
		expected_ids["mse.small_decor.%03d" % (index + 1)] = true

	var catalog := _read_json(CATALOG_PATH)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID, "catalog_package")
	var raw_by_id := {}
	for raw: Dictionary in catalog.get("assets", []):
		if str(raw.get("package_id", "")) != PACKAGE_ID:
			continue
		var asset_id := str(raw.get("asset_id", ""))
		assert(expected_ids.has(asset_id), asset_id + ":unexpected_catalog_id")
		assert(not raw_by_id.has(asset_id), asset_id + ":duplicate_catalog_id")
		raw_by_id[asset_id] = raw
	assert(raw_by_id.size() == 48, "catalog_package_count")

	var review := _read_json(REVIEW_PATH)
	var review_items: Dictionary = review.get("items", {})
	var override_payload := _read_json(OVERRIDES_PATH)
	var overrides: Dictionary = override_payload.get("overrides", {})
	var small_override_ids := {}
	for asset_id: String in overrides:
		if asset_id.begins_with("mse.small_decor."):
			small_override_ids[asset_id] = true
	assert(small_override_ids == expected_ids, "override_exact_small_id_set")

	MapAssetCatalogService.invalidate_cache()
	var effective_package_ids := {}
	for effective: Dictionary in MapAssetCatalogService.all_assets():
		if str(effective.get("package_id", "")) != PACKAGE_ID:
			continue
		var asset_id := str(effective.get("asset_id", ""))
		assert(expected_ids.has(asset_id), asset_id + ":unexpected_effective_id")
		assert(not effective_package_ids.has(asset_id), asset_id + ":duplicate_effective_id")
		effective_package_ids[asset_id] = true
	assert(effective_package_ids == expected_ids, "effective_package_ids")

	for asset_id: String in expected_ids:
		assert(review_items.has(asset_id), asset_id + ":missing_verified_review")
		var raw: Dictionary = raw_by_id[asset_id]
		var review_item: Dictionary = review_items[asset_id]
		var override: Dictionary = overrides[asset_id]
		assert(str(review_item.get("status", "")) == "verified", asset_id + ":review_status")
		assert(str(review_item.get("image", "")) == str(raw.get("image", "")), asset_id + ":review_image")
		assert(str(review_item.get("source_sha256", "")) == str(raw.get("source_sha256", "")), asset_id + ":review_source_sha")
		assert(str(review_item.get("output_sha256", "")) == str(raw.get("output_sha256", "")), asset_id + ":review_output_sha")
		_assert_int_array(override.get("anchor_px", []), review_item.get("anchor_px", []), asset_id + ":override_anchor")
		for field: String in ["footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles", "base_footprint_tiles"]:
			_assert_int_array(override.get(field, []), review_item.get("footprint_tiles", []), asset_id + ":override_" + field)
		_assert_int_array(override.get("collision_footprint_tiles", []), [0, 0], asset_id + ":override_collision_footprint")
		assert(str(override.get("collision_policy", "")) == "none", asset_id + ":override_collision_policy")
		assert(str(override.get("collision_profile_id", "")) == "none_visual", asset_id + ":override_collision_profile")
		assert(str(override.get("navigation_policy", "")) == "ignore", asset_id + ":override_navigation")
		assert(bool(override.get("placeable", false)), asset_id + ":override_placeable")
		assert(str(override.get("calibration_status", "")) == "placeable", asset_id + ":override_calibration")
		assert(str(override.get("content_layer", "")) == "personal_expansion", asset_id + ":override_content_layer")

		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id + ":missing_effective")
		_assert_int_array(effective.get("anchor_px", []), review_item.get("anchor_px", []), asset_id + ":effective_anchor")
		for field: String in ["footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles", "base_footprint_tiles"]:
			_assert_int_array(effective.get(field, []), review_item.get("footprint_tiles", []), asset_id + ":effective_" + field)
		_assert_int_array(effective.get("collision_footprint_tiles", []), [0, 0], asset_id + ":effective_collision_footprint")
		assert(str(effective.get("collision_policy", "")) == "none", asset_id + ":effective_collision_policy")
		assert(str(effective.get("collision_profile_id", "")) == "none_visual", asset_id + ":effective_collision_profile")
		assert(str(effective.get("navigation_policy", "")) == "ignore", asset_id + ":effective_navigation")
		assert(bool(effective.get("placeable", false)), asset_id + ":effective_placeable")
		assert(str(effective.get("calibration_status", "")) == "placeable", asset_id + ":effective_calibration")

	print("MSE_SMALL_DECORATION_REVIEW_PROMOTION_PASS assets=48 effective=48 verified=48 collision=none review_authority=manual")
	get_tree().quit(0)
