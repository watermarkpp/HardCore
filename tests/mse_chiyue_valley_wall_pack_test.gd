extends Node

const FAMILY_ID := "chiyue_valley_rock_wall_u0"
const ASSET_PREFIX := "chiyue_valley_wall_"
const CATALOG_PATH := "res://assets/data/assets/map_chiyue_valley_wall_asset_catalog.json"
const PROVENANCE_PATH := "res://assets/art/maps/_shared/walls/chiyue_valley/source/chiyue_valley_wall_source_provenance.json"
const PROJECTION_CONTRACT := "isometric_cell_64x32_exact_v1"
const PLACEMENT_CONTRACT := "wall_foot_on_cell_edge_64x32_v1"
const VISUAL_PROFILE := "chiyue_valley_native_2to1_rock_wall_v1"
const EXPECTED_SELECTION_BOUNDS := {
	"iso_x_l1": [32, 8, 63, 191],
	"iso_x_l2": [32, 8, 95, 207],
	"iso_x_l3": [32, 8, 127, 223],
	"iso_x_l4": [32, 8, 159, 239],
	"iso_y_l1": [1, 8, 63, 191],
	"iso_y_l2": [1, 8, 95, 207],
	"iso_y_l3": [1, 8, 127, 223],
	"iso_y_l4": [1, 8, 159, 239],
}


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var parsed := _read_catalog()
	var assets: Array = parsed.get("assets", [])
	assert(assets.size() == 16)
	assert(parsed.get("wall_family_ids", []) == [FAMILY_ID])
	assert(str(parsed.get("corner_join_mode", "")) == "straight_overlap")
	assert(str(parsed.get("native_projection_contract_id", "")) == PROJECTION_CONTRACT)
	assert(str(parsed.get("collision_authority", "")) == "manual_by_user")
	assert(FileAccess.file_exists(PROVENANCE_PATH))
	_assert_provenance()

	var ids := {}
	var axis_counts := {"iso_x": 0, "iso_y": 0}
	var length_counts := {1: 0, 2: 0, 3: 0, 4: 0}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(asset_id.begins_with(ASSET_PREFIX))
		assert(not ids.has(asset_id), "duplicate asset id: %s" % asset_id)
		ids[asset_id] = true
		assert(str(asset.get("display_name", "")).contains("赤月洞穴岩壁"))
		assert(str(asset.get("wall_family_id", "")) == FAMILY_ID)
		assert(str(asset.get("topology", "")) == "straight")
		assert(str(asset.get("corner_join_mode", "")) == "straight_overlap")
		assert(not bool(asset.get("contains_corner_pillar", true)))
		assert(str(asset.get("native_projection_contract_id", "")) == PROJECTION_CONTRACT)
		assert(str(asset.get("placement_contract_id", "")) == PLACEMENT_CONTRACT)
		assert(str(asset.get("visual_profile_id", "")) == VISUAL_PROFILE)
		assert(str(asset.get("asset_type", "")) == "wall_module")
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(asset.get("collision_cells", []) == [])
		assert(asset.get("placement_clearance_cells", []) == [])
		assert(asset.get("collision_footprint_tiles", []) == [0, 0])
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert(bool(asset.get("manual_collision_expected", false)))
		assert(str(asset.get("collision_authority", "")) == "manual_by_user")
		assert(str(asset.get("palette_path", "")).contains("赤月峡谷墙体"))
		var axis := str(asset.get("axis", ""))
		var length := int(asset.get("length_tiles", 0))
		var expected_bounds: Array = EXPECTED_SELECTION_BOUNDS["%s_l%d" % [axis, length]]
		assert(asset.get("visible_bounds_px", []) == expected_bounds)
		assert(asset.get("selection_bounds_px", []) == expected_bounds)
		assert(axis_counts.has(axis))
		assert(length_counts.has(length))
		axis_counts[axis] += 1
		length_counts[length] += 1
		_assert_native_geometry(asset)
		_assert_image(asset)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), "%s not loaded by catalog service" % asset_id)
		assert(str(effective.get("collision_policy", "")) == "none")

	assert(axis_counts == {"iso_x": 8, "iso_y": 8})
	assert(length_counts == {1: 2, 2: 2, 3: 6, 4: 6})
	_assert_family_menu()
	_assert_closed_loop()
	print("MSE_CHIYUE_VALLEY_WALL_PACK_PASS assets=16 pngs=64 corners=0 pillars=0")
	get_tree().quit(0)


func _read_catalog() -> Dictionary:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	return parsed


func _assert_provenance() -> void:
	var file := FileAccess.open(PROVENANCE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	assert(str(parsed.get("family_id", "")) == FAMILY_ID)
	var generation: Dictionary = parsed.get("generation", {})
	assert(str(generation.get("tool", "")) == "image_gen.imagegen")
	assert(str(generation.get("session_id", "")).length() > 20)
	assert(str(generation.get("clipboard_reference_sha256", "")).length() == 64)
	assert(str(generation.get("front_output_id", "")) == "exec-a16c2c00-468a-45e3-a09e-35e7b6b63dda.png")
	assert(str(generation.get("cap_output_id", "")) == "exec-394b3c43-bf78-40ad-9aaa-d97b8e17af26.png")
	var sources: Array = parsed.get("source_files", [])
	assert(sources.size() == 8)
	for source: Dictionary in sources:
		var expected_alpha: Array = [0, 255] if str(source.get("role", "")) == "cap" else [255, 255]
		assert(source.get("alpha_extrema", []) == expected_alpha)
		assert(str(source.get("sha256", "")).length() == 64)


func _assert_native_geometry(asset: Dictionary) -> void:
	var length := int(asset.get("length_tiles", 0))
	var axis := str(asset.get("axis", ""))
	var image_size: Array = asset.get("image_size", [])
	assert(
		image_size.size() == 2
		and int(image_size[0]) == 32 * length + 64
		and int(image_size[1]) == 208 + 16 * length
	)
	var anchor: Array = asset.get("placement_anchor_px", [])
	assert(anchor.size() == 2 and int(anchor[1]) == 184)
	assert(int(anchor[0]) == (64 if axis == "iso_x" else int(image_size[0]) - 64))
	var start_seam: Array = asset.get("start_seam_px", [])
	var end_seam: Array = asset.get("end_seam_px", [])
	assert(int(start_seam[1]) == 184)
	assert(int(end_seam[1]) - int(start_seam[1]) == 16 * length)
	if axis == "iso_x":
		assert(
			Vector2i(
				int(start_seam[0]) - int(anchor[0]),
				int(start_seam[1]) - int(anchor[1])
			) == Vector2i(-32, 0)
		)
		assert(
			Vector2i(
				int(end_seam[0]) - int(anchor[0]),
				int(end_seam[1]) - int(anchor[1])
			) == Vector2i(32 * (length - 1), 16 * length)
		)
	else:
		assert(
			Vector2i(
				int(start_seam[0]) - int(anchor[0]),
				int(start_seam[1]) - int(anchor[1])
			) == Vector2i(32, 0)
		)
		assert(
			Vector2i(
				int(end_seam[0]) - int(anchor[0]),
				int(end_seam[1]) - int(anchor[1])
			) == Vector2i(-32 * (length - 1), 16 * length)
		)
	assert(asset.get("wall_cap_projection_px", []) == [32, 16])
	assert(int(asset.get("wall_cap_thickness_tiles", 0)) == 1)
	var parts: Array = asset.get("render_parts", [])
	assert(parts.size() == length)
	assert(str(asset.get("render_mode", "")) == ("single_part" if length == 1 else "segmented"))
	var source_layout: Array = asset.get("source_variant_layout", [])
	assert(source_layout.size() == length)
	for index in range(1, source_layout.size()):
		var previous: Dictionary = source_layout[index - 1]
		var current: Dictionary = source_layout[index]
		assert(int(previous.get("front_source_variant", 0)) != int(current.get("front_source_variant", 0)))
		assert(int(previous.get("cap_source_variant", 0)) != int(current.get("cap_source_variant", 0)))


func _assert_image(asset: Dictionary) -> void:
	var asset_id := str(asset.get("asset_id", ""))
	var image_path := "res://" + str(asset.get("image", ""))
	assert(FileAccess.file_exists(image_path), "%s missing image" % asset_id)
	var texture := load(image_path) as Texture2D
	assert(texture != null, "%s invalid texture" % asset_id)
	var image := texture.get_image()
	assert(image != null and not image.is_empty(), "%s invalid image" % asset_id)
	assert(image.detect_alpha() != Image.ALPHA_NONE, "%s missing alpha" % asset_id)
	assert(image.get_pixel(0, 0).a == 0.0, "%s must retain transparent canvas" % asset_id)
	var used_rect := image.get_used_rect()
	var selection_bounds: Array = asset.get("selection_bounds_px", [])
	var expected_bounds: Array = EXPECTED_SELECTION_BOUNDS[
		"%s_l%d" % [str(asset.get("axis", "")), int(asset.get("length_tiles", 0))]
	]
	assert(
		selection_bounds.size() == 4
		and int(selection_bounds[0]) == used_rect.position.x
		and int(selection_bounds[1]) == used_rect.position.y
		and int(selection_bounds[2]) == used_rect.size.x
		and int(selection_bounds[3]) == used_rect.size.y
	)
	assert(
		[
			used_rect.position.x,
			used_rect.position.y,
			used_rect.size.x,
			used_rect.size.y,
		] == expected_bounds
	)


func _assert_family_menu() -> void:
	var found := false
	for family: Dictionary in MapEditorWallLoopService.available_families():
		if str(family.get("wall_family_id", "")) != FAMILY_ID:
			continue
		found = true
		assert(str(family.get("display_name", "")).contains("赤月峡谷天然洞穴岩壁"))
	assert(found, "Chiyue Valley wall family missing from editor menu")


func _assert_closed_loop() -> void:
	var document := MapEditorTypes.new_map(
		"chiyue_valley_loop_test",
		990312,
		"Chiyue Valley Cave Loop",
		Vector2i(24, 24)
	)
	var bounds := Rect2i(3, 4, 12, 10)
	var applied := MapEditorWallLoopService.apply_closed_rectangle(
		document,
		FAMILY_ID,
		bounds,
		"outer_corner",
		"terrain_base",
		true,
		"test.chiyue_valley.closed_loop"
	)
	assert(applied.ok, str(applied.get("errors", [])))
	assert(str(applied.plan.get("corner_join_mode", "")) == "straight_overlap")
	var validation := MapEditorWallLoopService.validate_closed_rectangle(
		document,
		FAMILY_ID,
		bounds,
		str(applied.structure_id)
	)
	assert(validation.ok, str(validation.get("errors", [])))
	assert(int(validation.perimeter_cell_count) == 2 * 12 + 2 * (10 - 2))
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("structure_id", "")) != str(applied.structure_id):
			continue
		assert(str(instance.get("collision_policy", "")) == "none")
		assert(instance.get("collision_footprint_tiles", []) == [0, 0])
		assert(instance.get("collision_cells", []) == [])
