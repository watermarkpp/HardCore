extends Node


const CATALOG_PATH := "res://assets/data/assets/map_new_throne_asset_catalog.json"
const PACKAGE_ID := "mse_new_throne_addition_6_v1"
const PALETTE_PATH := "装饰物1/王座"


func _ready() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	var catalog: Dictionary = parsed
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(catalog.get("classification", "")) == PALETTE_PATH)
	assert(int(catalog.get("source_count", 0)) == 6)
	assert(int(catalog.get("asset_count", 0)) == 6)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 6)
	assert(MapAssetCatalogService.validate_catalog().is_empty())

	var preview := MapEditorCanvasPreview.new()
	add_child(preview)
	var document := MapEditorTypes.new_map(
		"new_throne_asset_test",
		991021,
		"New Throne Asset Test",
		Vector2i(64, 64)
	)
	for index in assets.size():
		var asset: Dictionary = assets[index]
		var stable_index := index + 7
		var asset_id := "mse.new_throne.%02d" % stable_index
		assert(str(asset.get("asset_id", "")) == asset_id)
		assert(str(asset.get("package_id", "")) == PACKAGE_ID)
		assert(str(asset.get("palette_path", "")) == PALETTE_PATH)
		assert(str(asset.get("asset_type", "")) == "large_prop")
		assert(str(asset.get("anchor_mode", "")) == "foot_tile")
		assert(_int_pair(asset.get("footprint_tiles", [])) == Vector2i(6, 6))
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(bool(asset.get("manual_collision_expected", false)))
		assert(bool(asset.get("placeable", false)))
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty())
		assert(image.detect_alpha() != Image.ALPHA_NONE)
		assert(image.get_pixel(0, 0).a == 0.0)
		assert(_int_pair(asset.get("image_size", [])) == image.get_size())
		assert(preview._texture_for_asset(asset_id) != null)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty())
		var placed := MapEditorInstanceService.create_instance(
			document,
			asset_id,
			"decoration",
			Vector2i(8 + index * 7, 8),
			"object_base"
		)
		assert(placed.get("ok", false), str(placed.get("errors", [])))

	print(
		"MSE_NEW_THRONE_ASSET_PASS "
		+ "sources=6 assets=6 stable_ids=07-12 classification=装饰物1/王座"
	)
	get_tree().quit(0)


func _int_pair(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(value[0]), int(value[1]))
