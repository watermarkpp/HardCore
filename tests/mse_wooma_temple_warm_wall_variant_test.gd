extends Node

const STANDARD_CATALOG_PATH := (
	"res://assets/data/assets/map_wooma_temple_wall_asset_catalog.json"
)
const WARM_CATALOG_PATH := (
	"res://assets/data/assets/map_wooma_temple_warm_wall_asset_catalog.json"
)
const STANDARD_FAMILY_ID := "wooma_temple_gothic_stone_u0"
const WARM_FAMILY_ID := "wooma_temple_floor_warm_stone_u0"
const COLOR_MATCH_CONTRACT_ID := "wooma_floor_weighted_palette_match_v1"


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var standard := _read_json(STANDARD_CATALOG_PATH)
	var warm := _read_json(WARM_CATALOG_PATH)
	var standard_assets: Array = standard.get("assets", [])
	var warm_assets: Array = warm.get("assets", [])
	assert(standard_assets.size() == 16)
	assert(warm_assets.size() == 16)
	assert(str(warm.get("color_match_contract_id", "")) == COLOR_MATCH_CONTRACT_ID)
	assert(str(warm.get("ground_reference_map_id", "")) == "wooma_temple_1")
	var target_rgb: Array = warm.get("ground_weighted_median_rgb", [])
	assert(target_rgb.size() == 3)
	assert(int(target_rgb[0]) == 148)
	assert(int(target_rgb[1]) == 136)
	assert(int(target_rgb[2]) == 112)

	var standard_by_id := {}
	for asset: Dictionary in standard_assets:
		standard_by_id[str(asset.get("asset_id", ""))] = asset
	var representative_standard: Dictionary = {}
	var representative_warm: Dictionary = {}
	for asset: Dictionary in warm_assets:
		_assert_warm_asset(asset, standard_by_id)
		if str(asset.get("asset_id", "")).ends_with("straight_x_l1_v01"):
			representative_warm = asset
			representative_standard = standard_by_id[
				str(asset.get("source_standard_asset_id", ""))
			]
	assert(not representative_standard.is_empty())
	assert(not representative_warm.is_empty())
	_assert_color_transfer(representative_standard, representative_warm)

	var families := {}
	for family: Dictionary in MapEditorWallLoopService.available_families():
		families[str(family.get("wall_family_id", ""))] = str(
			family.get("display_name", "")
		)
	assert(families.has(STANDARD_FAMILY_ID))
	assert(families.has(WARM_FAMILY_ID))
	assert(str(families[STANDARD_FAMILY_ID]).contains("标准"))
	assert(str(families[WARM_FAMILY_ID]).contains("沃玛寺庙"))
	print(
		"MSE_WOOMA_TEMPLE_WARM_WALL_VARIANT_PASS "
		+ "standard=16 warm=16 target_rgb=148,136,112"
	)
	get_tree().quit(0)


func _assert_warm_asset(asset: Dictionary, standard_by_id: Dictionary) -> void:
	var warm_id := str(asset.get("asset_id", ""))
	var standard_id := str(asset.get("source_standard_asset_id", ""))
	assert(warm_id.begins_with("wooma_temple_warm_wall_"))
	assert(standard_by_id.has(standard_id), warm_id)
	var standard: Dictionary = standard_by_id[standard_id]
	assert(str(asset.get("wall_family_id", "")) == WARM_FAMILY_ID)
	assert(str(asset.get("color_match_contract_id", "")) == COLOR_MATCH_CONTRACT_ID)
	for field: String in [
		"image_size",
		"anchor_px",
		"placement_anchor_px",
		"start_seam_px",
		"end_seam_px",
		"footprint_tiles",
		"wall_cap_projection_px",
	]:
		assert(asset.get(field, null) == standard.get(field, null), "%s:%s" % [warm_id, field])
	assert(str(asset.get("corner_join_mode", "")) == "straight_overlap")
	assert(str(asset.get("collision_policy", "")) == "none")
	assert(asset.get("collision_cells", []) == [])
	var collision_footprint: Array = asset.get(
		"collision_footprint_tiles", []
	)
	assert(collision_footprint.size() == 2)
	assert(int(collision_footprint[0]) == 0)
	assert(int(collision_footprint[1]) == 0)
	assert(str(asset.get("navigation_policy", "")) == "ignore")
	var effective := MapAssetCatalogService.find_asset(warm_id)
	assert(not effective.is_empty(), "%s missing from editor catalog" % warm_id)


func _assert_color_transfer(standard: Dictionary, warm: Dictionary) -> void:
	var standard_image := _load_image(str(standard.get("image", "")))
	var warm_image := _load_image(str(warm.get("image", "")))
	assert(standard_image.get_size() == warm_image.get_size())
	assert(standard_image.get_used_rect() == warm_image.get_used_rect())
	standard_image.resize(
		maxi(1, standard_image.get_width() / 4),
		maxi(1, standard_image.get_height() / 4),
		Image.INTERPOLATE_NEAREST
	)
	warm_image.resize(
		maxi(1, warm_image.get_width() / 4),
		maxi(1, warm_image.get_height() / 4),
		Image.INTERPOLATE_NEAREST
	)
	var standard_stats := _opaque_stats(standard_image)
	var warm_stats := _opaque_stats(warm_image)
	assert(
		abs(int(standard_stats.pixel_count) - int(warm_stats.pixel_count)) <= 1
	)
	assert(float(warm_stats.mean_red) > float(standard_stats.mean_red) + 18.0)
	assert(
		float(warm_stats.mean_red) - float(warm_stats.mean_green)
		> float(standard_stats.mean_red) - float(standard_stats.mean_green) + 8.0
	)


func _read_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	return parsed


func _load_image(path: String) -> Image:
	var image := Image.load_from_file(
		ProjectSettings.globalize_path("res://" + path)
	)
	assert(image != null and not image.is_empty(), path)
	return image


func _opaque_stats(image: Image) -> Dictionary:
	var count := 0
	var red_total := 0.0
	var green_total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.25:
				continue
			count += 1
			red_total += color.r * 255.0
			green_total += color.g * 255.0
	assert(count > 0)
	return {
		"pixel_count": count,
		"mean_red": red_total / float(count),
		"mean_green": green_total / float(count),
	}
