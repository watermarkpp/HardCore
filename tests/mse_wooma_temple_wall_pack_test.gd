extends Node

const FAMILY_ID := "wooma_temple_gothic_stone_u0"
const CATALOG_PATH := "res://assets/data/assets/map_wooma_temple_wall_asset_catalog.json"


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var parsed := _read_catalog()
	var assets: Array = parsed.get("assets", [])
	assert(assets.size() == 42)
	assert(parsed.get("wall_family_ids", []) == [FAMILY_ID])
	assert(str(parsed.get("collision_authority", "")) == "manual_by_user")

	var ids := {}
	var topology_counts := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(not asset_id.is_empty())
		assert(not ids.has(asset_id), "duplicate asset id: %s" % asset_id)
		ids[asset_id] = true
		assert(str(asset.get("wall_family_id", "")) == FAMILY_ID)
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
		assert(str(asset.get("palette_path", "")).begins_with(
			"洞穴与地下城/墙体模块/沃玛寺庙墙体/"
		))
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), "%s missing image" % asset_id)
		var texture := load(image_path) as Texture2D
		assert(texture != null, "%s invalid texture" % asset_id)
		var image := texture.get_image()
		assert(image != null and not image.is_empty(), "%s invalid image" % asset_id)
		assert(image.detect_alpha() != Image.ALPHA_NONE, "%s missing alpha" % asset_id)
		var topology := str(asset.get("topology", ""))
		topology_counts[topology] = int(topology_counts.get(topology, 0)) + 1
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), "%s not loaded by catalog service" % asset_id)
		assert(str(effective.get("collision_policy", "")) == "none")
		var effective_footprint: Array = effective.get("collision_footprint_tiles", [])
		assert(
			effective_footprint.size() == 2
			and int(effective_footprint[0]) == 0
			and int(effective_footprint[1]) == 0
		)

	assert(topology_counts == {
		"broken_adapter": 4,
		"door_adapter": 4,
		"end_cap": 4,
		"inner_corner": 4,
		"outer_corner": 4,
		"seam_cover": 6,
		"straight": 16,
	})
	_assert_family_menu()
	_assert_segmented_straight()
	_assert_corner_visual_baseline(assets)
	_assert_four_directional_corners(assets)
	_assert_closed_loop()
	print("MSE_WOOMA_TEMPLE_WALL_PACK_PASS assets=42 closed_loop=12x10")
	get_tree().quit(0)


func _read_catalog() -> Dictionary:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	return parsed


func _assert_family_menu() -> void:
	var found := false
	for family: Dictionary in MapEditorWallLoopService.available_families():
		if str(family.get("wall_family_id", "")) != FAMILY_ID:
			continue
		found = true
		assert(str(family.get("display_name", "")) == "沃玛寺庙哥特旧石墙")
	assert(found, "Wooma Temple wall family missing from editor menu")


func _assert_segmented_straight() -> void:
	var wall := MapAssetCatalogService.find_asset("wooma_temple_wall_straight_x_l4_v01")
	assert(not wall.is_empty())
	assert(str(wall.get("render_mode", "")) == "segmented")
	assert((wall.get("render_parts", []) as Array).size() == 4)
	var document := MapEditorTypes.new_map(
		"wooma_temple_segment_test",
		990310,
		"Wooma Temple Segment",
		Vector2i(24, 24)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		str(wall.asset_id),
		"terrain",
		Vector2i(4, 4),
		"terrain_base"
	)
	assert(placed.ok, str(placed.get("errors", [])))
	var commands := MapEditorCanvasPreview.instance_draw_commands(
		placed.instance,
		wall,
		0,
		0
	)
	assert(commands.size() == 4)
	var sort_tiles := {}
	for command: Dictionary in commands:
		var tile: Vector2i = command.sort_tile
		sort_tiles["%d,%d" % [tile.x, tile.y]] = true
	for x in range(4, 8):
		assert(sort_tiles.has("%d,4" % x))


func _assert_corner_visual_baseline(assets: Array) -> void:
	var corner := {}
	var seam_pillar := {}
	for asset: Dictionary in assets:
		match str(asset.get("asset_id", "")):
			"wooma_temple_wall_outer_ne_v01":
				corner = asset
			"wooma_temple_wall_seam_cover_01":
				seam_pillar = asset
	assert(not corner.is_empty())
	assert(not seam_pillar.is_empty())
	var corner_texture := load(
		"res://" + str(corner.get("image", ""))
	) as Texture2D
	var pillar_texture := load(
		"res://" + str(seam_pillar.get("image", ""))
	) as Texture2D
	assert(corner_texture != null and pillar_texture != null)
	var corner_image := corner_texture.get_image()
	var pillar_image := pillar_texture.get_image()
	assert(corner_image != null and not corner_image.is_empty())
	assert(pillar_image != null and not pillar_image.is_empty())
	assert(corner_image.get_data() == pillar_image.get_data())
	var corner_anchor: Array = corner.get("placement_anchor_px", [])
	var pillar_anchor: Array = seam_pillar.get("placement_anchor_px", [])
	assert(corner_anchor.size() == 2)
	assert(pillar_anchor.size() == 2)
	assert(corner_anchor == pillar_anchor)


func _assert_four_directional_corners(assets: Array) -> void:
	var corners := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		if asset_id in [
			"wooma_temple_wall_outer_nw_v01",
			"wooma_temple_wall_outer_ne_v01",
			"wooma_temple_wall_outer_se_v01",
			"wooma_temple_wall_outer_sw_v01",
		]:
			corners[asset_id] = asset
	assert(corners.size() == 4)
	var expected_bottom_by_id := {
		"wooma_temple_wall_outer_nw_v01": 96,
		"wooma_temple_wall_outer_ne_v01": 104,
		"wooma_temple_wall_outer_se_v01": 112,
		"wooma_temple_wall_outer_sw_v01": 104,
	}
	var reference_size := Vector2i.ZERO
	for asset_id: String in corners:
		var asset: Dictionary = corners[asset_id]
		var texture := load("res://" + str(asset.get("image", ""))) as Texture2D
		assert(texture != null)
		var image := texture.get_image()
		assert(image != null and not image.is_empty())
		var used_rect := image.get_used_rect()
		assert(used_rect.size.x <= 58 and used_rect.size.y <= 96)
		assert(used_rect.position.x < 48 and used_rect.end.x > 48)
		assert(used_rect.end.y == int(expected_bottom_by_id[asset_id]))
		if reference_size == Vector2i.ZERO:
			reference_size = used_rect.size
		else:
			assert(used_rect.size == reference_size)


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
		assert(instance.get("collision_cells", []) == [])
		assert(instance.get("collision_footprint_tiles", []) == [0, 0])
		assert(str(instance.get("collision_authority", "")) == "manual_by_user")
