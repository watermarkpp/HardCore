extends Node


const CATALOG_PATH := "res://assets/data/assets/map_asset_catalog.json"
const REVIEW_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
const PROCESSING := "tree_roadblock_explicit_grid_v1"
const EXPECTED_TOTAL := 128
const EXPECTED_TREE := 128
const EXPECTED_ROADBLOCK := 0
const EXPECTED_OLD_TREE := 118


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed


func _is_positive_integer(value: Variant) -> bool:
	if value is bool or not (value is int or value is float):
		return false
	var numeric := float(value)
	return numeric > 0.0 and is_equal_approx(numeric, round(numeric))


func _is_nonnegative_integer(value: Variant) -> bool:
	if value is bool or not (value is int or value is float):
		return false
	var numeric := float(value)
	return numeric >= 0.0 and is_equal_approx(numeric, round(numeric))


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var catalog := _read_json(CATALOG_PATH)
	var review_state := _read_json(REVIEW_PATH)
	var review_items: Dictionary = review_state.get("items", {})
	var selected: Array[Dictionary] = []
	for raw: Dictionary in catalog.get("assets", []):
		if str(raw.get("processing", "")) == PROCESSING:
			selected.append(raw)
	assert(selected.size() == EXPECTED_TOTAL)
	assert(review_items.size() >= EXPECTED_TOTAL)

	var ids := {}
	var tree_count := 0
	var roadblock_count := 0
	var out_of_image_anchor_count := 0
	for asset: Dictionary in selected:
		var asset_id := str(asset.get("asset_id", ""))
		assert(not asset_id.is_empty())
		assert(not ids.has(asset_id), asset_id)
		ids[asset_id] = true
		var item_variant: Variant = review_items.get(asset_id, {})
		assert(item_variant is Dictionary, asset_id)
		var review: Dictionary = item_variant
		assert(str(review.get("status", "")) == "verified", asset_id)
		for fingerprint_field: String in ["image", "source_sha256", "output_sha256"]:
			assert(
				str(review.get(fingerprint_field, "")) == str(asset.get(fingerprint_field, "")),
				asset_id + ":" + fingerprint_field
			)
		var footprint: Variant = review.get("footprint_tiles", [])
		assert(
			footprint is Array
			and footprint.size() == 2
			and _is_positive_integer(footprint[0])
			and _is_positive_integer(footprint[1]),
			asset_id
		)
		var anchor: Variant = review.get("anchor_px", [])
		assert(
			anchor is Array
			and anchor.size() == 2
			and _is_nonnegative_integer(anchor[0])
			and _is_nonnegative_integer(anchor[1]),
			asset_id
		)
		var image := Image.load_from_file(
			ProjectSettings.globalize_path("res://" + str(asset.get("image", "")))
		)
		assert(image != null and not image.is_empty(), asset_id)
		if int(anchor[0]) >= image.get_width() or int(anchor[1]) >= image.get_height():
			out_of_image_anchor_count += 1

		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		assert(bool(effective.get("placeable", false)), asset_id)
		assert(str(effective.get("calibration_status", "")) == "placeable", asset_id)
		assert(str(effective.get("content_layer", "")) == "personal_expansion", asset_id)
		assert(effective.get("anchor_px", []) == anchor, asset_id + ":anchor")
		for geometry_field: String in [
			"footprint_tiles",
			"visual_footprint_tiles",
			"occupancy_footprint_tiles",
			"base_footprint_tiles",
		]:
			assert(effective.get(geometry_field, []) == footprint, asset_id + ":" + geometry_field)
		var collision: Array = effective.get("collision_footprint_tiles", [])
		if str(effective.get("collision_policy", "")) == "none":
			assert(
				collision.size() == 2
				and int(collision[0]) == 0
				and int(collision[1]) == 0,
				asset_id + ":nonblocking_collision"
			)
		else:
			assert(
				collision.size() == 2
				and int(collision[0]) == int(footprint[0])
				and int(collision[1]) == int(footprint[1]),
				asset_id + ":blocking_collision"
			)

		var palette_path := str(asset.get("palette_path", ""))
		if palette_path.begins_with("装饰物1/树木/新增/"):
			tree_count += 1
		elif palette_path.begins_with("装饰物1/路障/新增"):
			roadblock_count += 1

	assert(tree_count == EXPECTED_TREE)
	assert(roadblock_count == EXPECTED_ROADBLOCK)
	assert(out_of_image_anchor_count == 8)

	var old_tree_ids := {}
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		var image_path := str(asset.get("image", "")).replace("\\", "/")
		if image_path.contains("/trees/") and not image_path.contains("/trees/新增/"):
			old_tree_ids[str(asset.get("asset_id", ""))] = true
	assert(old_tree_ids.size() == EXPECTED_OLD_TREE)
	for old_id: String in old_tree_ids:
		var old_effective := MapAssetCatalogService.find_asset(old_id)
		assert(not old_effective.is_empty(), old_id)
		assert(not bool(old_effective.get("placeable", false)), old_id)

	print(
		"MSE_TREE_ROADBLOCK_VERIFIED_CALIBRATION_PASS "
		+ "assets=128 trees=128 roadblocks=0 verified=128 "
		+ "out_of_image_anchor_count=8 old_tree_placeable_false=118"
	)
	get_tree().quit(0)
