extends Node

const FAMILY_ID := "wooma_temple_gothic_stone_u0"
const CATALOG_PATH := "res://assets/data/assets/map_wooma_temple_wall_asset_catalog.json"
const PROJECTION_CONTRACT := "isometric_cell_64x32_exact_v1"
const PLACEMENT_CONTRACT := "wall_foot_on_cell_edge_64x32_v1"


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var parsed := _read_catalog()
	var assets: Array = parsed.get("assets", [])
	assert(assets.size() == 16)
	assert(parsed.get("wall_family_ids", []) == [FAMILY_ID])
	assert(str(parsed.get("corner_join_mode", "")) == "straight_overlap")
	assert(str(parsed.get("native_projection_contract_id", "")) == PROJECTION_CONTRACT)
	assert(str(parsed.get("collision_authority", "")) == "manual_by_user")

	var ids := {}
	var axis_counts := {"iso_x": 0, "iso_y": 0}
	var length_counts := {1: 0, 2: 0, 3: 0, 4: 0}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(not asset_id.is_empty())
		assert(not ids.has(asset_id), "duplicate asset id: %s" % asset_id)
		ids[asset_id] = true
		assert(str(asset.get("wall_family_id", "")) == FAMILY_ID)
		assert(str(asset.get("topology", "")) == "straight")
		assert(str(asset.get("corner_join_mode", "")) == "straight_overlap")
		assert(not bool(asset.get("contains_corner_pillar", true)))
		assert(str(asset.get("native_projection_contract_id", "")) == PROJECTION_CONTRACT)
		assert(str(asset.get("placement_contract_id", "")) == PLACEMENT_CONTRACT)
		assert(
			str(asset.get("visual_profile_id", ""))
			== "wooma_temple_native_2to1_wall_v3"
		)
		assert(str(asset.get("asset_type", "")) == "wall_module")
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(asset.get("collision_cells", []) == [])
		var collision_footprint: Array = asset.get("collision_footprint_tiles", [])
		assert(
			collision_footprint.size() == 2
			and int(collision_footprint[0]) == 0
			and int(collision_footprint[1]) == 0
		)
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert(bool(asset.get("manual_collision_expected", false)))
		assert(str(asset.get("collision_authority", "")) == "manual_by_user")
		var axis := str(asset.get("axis", ""))
		var length := int(asset.get("length_tiles", 0))
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
	_assert_removed_legacy_modules()
	_assert_family_menu()
	_assert_closed_loop()
	print("MSE_WOOMA_TEMPLE_WALL_PACK_PASS assets=16 corners=0 pillars=0")
	get_tree().quit(0)


func _read_catalog() -> Dictionary:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	return parsed


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
	assert(int(start_seam[1]) - int(anchor[1]) == 0)
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
	var cap_projection: Array = asset.get("wall_cap_projection_px", [])
	assert(
		cap_projection.size() == 2
		and int(cap_projection[0]) == 32
		and int(cap_projection[1]) == 16
	)
	assert(int(asset.get("wall_cap_thickness_tiles", 0)) == 1)
	var parts: Array = asset.get("render_parts", [])
	assert(parts.size() == length)
	assert(str(asset.get("render_mode", "")) == (
		"single_part" if length == 1 else "segmented"
	))


func _assert_image(asset: Dictionary) -> void:
	var asset_id := str(asset.get("asset_id", ""))
	var image_path := "res://" + str(asset.get("image", ""))
	assert(FileAccess.file_exists(image_path), "%s missing image" % asset_id)
	var texture := load(image_path) as Texture2D
	assert(texture != null, "%s invalid texture" % asset_id)
	var image := texture.get_image()
	assert(image != null and not image.is_empty(), "%s invalid image" % asset_id)
	assert(image.detect_alpha() != Image.ALPHA_NONE, "%s missing alpha" % asset_id)
	var used_rect := image.get_used_rect()
	var selection_bounds: Array = asset.get("selection_bounds_px", [])
	assert(
		selection_bounds.size() == 4
		and int(selection_bounds[0]) == used_rect.position.x
		and int(selection_bounds[1]) == used_rect.position.y
		and int(selection_bounds[2]) == used_rect.size.x
		and int(selection_bounds[3]) == used_rect.size.y
	)


func _assert_removed_legacy_modules() -> void:
	for legacy_fragment: String in [
		"_inner_",
		"_outer_",
		"_seam_cover_",
		"_end_",
		"_door_",
		"_broken_",
	]:
		for asset: Dictionary in MapAssetCatalogService.all_assets():
			var asset_id := str(asset.get("asset_id", ""))
			if str(asset.get("wall_family_id", "")) != FAMILY_ID:
				continue
			assert(not asset_id.contains(legacy_fragment), asset_id)


func _assert_family_menu() -> void:
	var found := false
	for family: Dictionary in MapEditorWallLoopService.available_families():
		if str(family.get("wall_family_id", "")) != FAMILY_ID:
			continue
		found = true
		assert(not str(family.get("display_name", "")).is_empty())
	assert(found, "Wooma Temple wall family missing from editor menu")


func _assert_closed_loop() -> void:
	var document := MapEditorTypes.new_map(
		"wooma_temple_loop_test",
		990311,
		"Wooma Temple Loop",
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
		"test.wooma_temple.closed_loop"
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
	var corner_instance_counts := {
		Vector2i(3, 4): 0,
		Vector2i(14, 4): 0,
		Vector2i(14, 13): 0,
		Vector2i(3, 13): 0,
	}
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("structure_id", "")) != str(applied.structure_id):
			continue
		var asset := MapAssetCatalogService.find_asset(str(instance.asset_id))
		assert(str(asset.get("topology", "")) == "straight")
		assert(str(instance.get("collision_policy", "")) == "none")
		var tile_raw: Array = instance.get("tile", [0, 0])
		var footprint: Array = instance.get("footprint_tiles", [1, 1])
		for corner: Vector2i in corner_instance_counts:
			if Rect2i(
				Vector2i(int(tile_raw[0]), int(tile_raw[1])),
				Vector2i(int(footprint[0]), int(footprint[1]))
			).has_point(corner):
				corner_instance_counts[corner] += 1
	for count: int in corner_instance_counts.values():
		assert(count == 2)
