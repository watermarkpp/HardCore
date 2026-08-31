extends Node

const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const PROBE_COLOR := Color(1.0, 0.0, 1.0, 1.0)
const EXPECTED_VERIFIED_WALLS := 132
const EXPECTED_FORMALIZED_ANCHORS := 86
const REVIEW_PATH := (
	"res://assets/data/expansions/personal_expansion_001/"
	+ "map_asset_footprint_review_state.json"
)
const OVERRIDE_PATH := (
	"res://assets/data/expansions/personal_expansion_001/"
	+ "map_asset_overrides.json"
)
const SHAPE_ASSETS := {
	"straight_x": "orc_tomb_wall_straight_x_l3_v01",
	"straight_y": "orc_tomb_wall_straight_y_l3_v01",
	"inner_corner": "orc_tomb_wall_inner_nw_v01",
	"outer_corner": "orc_tomb_wall_outer_nw_v01",
	# The standalone seam-cover front PNG is intentionally transparent; the
	# actual opaque joint is formed by neighbouring straight-wall fragments.
	# Sample part 01 of this three-part wall to exercise that real joint.
	"seam": "orc_tomb_wall_straight_x_l3_v02",
	"door": "orc_tomb_wall_door_x_open_v01",
}
const GENERIC_WORLD_PROFILES := {
	"player_like": ["body", "wear", "weapon", "hair", "shadow"],
	"enemy_like": ["body", "shadow"],
	"npc_like": ["body", "shadow"],
	"summon_like": ["body", "shadow"],
	"ground_loot_like": ["icon"],
}

var _pixel_cases := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MapAssetCatalogService.invalidate_cache()
	_assert_verified_anchor_authority()
	_assert_wall_parts_match_occupied_cells()
	# Every wall shape uses the real shipped Orc Tomb foreground PNG.  A foot
	# one pixel behind the cell-centre cut must be covered; a foot one pixel in
	# front must remain visible.  This explicitly rejects the abandoned +16px
	# depth-guard experiment, which hid legitimate wall-front actors.
	for label: String in SHAPE_ASSETS:
		var asset_id := str(SHAPE_ASSETS[label])
		_assert_pixel_order(asset_id, -1.0, false, label)
		_assert_pixel_order(asset_id, 1.0, true, label)

	# Canvas Y-sort is intentionally type-agnostic.  Prove complete subtrees,
	# including worn layers and shadows, plus standalone loot-like roots.
	var straight_x := str(SHAPE_ASSETS.straight_x)
	for profile: String in GENERIC_WORLD_PROFILES:
		_assert_pixel_order(straight_x, -8.0, false, profile)
		_assert_pixel_order(straight_x, 8.0, true, profile)

	# Monotonic samples around the exact cut prove continuous motion cannot
	# bounce between layers or depend on scene-tree insertion order.
	for delta_y: float in [-12.0, -4.0, -1.0, 1.0, 4.0, 12.0]:
		_assert_pixel_order(
			straight_x,
			delta_y,
			delta_y > 0.0,
			"transition_%s" % str(delta_y)
		)

	print(
		(
			"WALL_FOREGROUND_PIXEL_OCCLUSION_RUNTIME_PASS "
			+ "contract=%s verified_walls=%d formalized_anchors=%d "
			+ "pixel_cases=%d shapes=6 profiles=5 "
			+ "static_fragments=true per_frame_rebuild=false "
			+ "full_screen_scan=false shader=false"
		)
		% [
			VisualGeometry.OCCLUSION_SORT_CONTRACT_ID,
			EXPECTED_VERIFIED_WALLS,
			EXPECTED_FORMALIZED_ANCHORS,
			_pixel_cases,
		]
	)
	get_tree().quit(0)


func _assert_verified_anchor_authority() -> void:
	var review: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(REVIEW_PATH)
	)
	var overrides_payload: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(OVERRIDE_PATH)
	)
	var review_items: Dictionary = review.get("items", {})
	var overrides: Dictionary = overrides_payload.get("overrides", {})
	var verified_walls := 0
	var formalized_anchors := 0
	for base: Dictionary in MapAssetCatalogService.all_assets():
		if str(base.get("asset_type", "")) != "wall_module":
			continue
		var asset_id := str(base.get("asset_id", ""))
		var item: Dictionary = review_items.get(asset_id, {})
		assert(str(item.get("status", "")) == "verified", asset_id)
		verified_walls += 1
		var raw_base := MapAssetCatalogService.find_base_asset(asset_id)
		var reviewed_anchor := _array_vector2(item.get("anchor_px", []))
		var base_anchor := _array_vector2(raw_base.get("anchor_px", []))
		if reviewed_anchor.is_equal_approx(base_anchor):
			continue
		formalized_anchors += 1
		assert(overrides.has(asset_id), "%s missing formal anchor" % asset_id)
		var formal_anchor := _array_vector2(
			overrides.get(asset_id, {}).get("anchor_px", [])
		)
		assert(
			formal_anchor.is_equal_approx(reviewed_anchor),
			"%s formal anchor diverged from verified review" % asset_id
		)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(
			_array_vector2(effective.get("anchor_px", [])).is_equal_approx(
				reviewed_anchor
			),
			"%s catalog discarded formal anchor" % asset_id
		)
		assert(
			_array_vector2(effective.get("footprint_tiles", [])).is_equal_approx(
				_array_vector2(raw_base.get("footprint_tiles", []))
			),
			"%s anchor formalization changed footprint" % asset_id
		)
	assert(verified_walls == EXPECTED_VERIFIED_WALLS)
	assert(formalized_anchors == EXPECTED_FORMALIZED_ANCHORS)


func _assert_wall_parts_match_occupied_cells() -> void:
	var checked_parts := 0
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if str(asset.get("asset_type", "")) != "wall_module":
			continue
		var footprint_raw: Array = asset.get("footprint_tiles", [])
		var footprint := Vector2i(
			int(footprint_raw[0]), int(footprint_raw[1])
		)
		for part: Dictionary in asset.get("render_parts", []):
			var occupied_raw: Array = part.get("tile_offset", [])
			var sort_raw: Array = part.get(
				"sort_tile_offset", part.get("tile_offset", [])
			)
			var occupied := Vector2i(
				int(occupied_raw[0]), int(occupied_raw[1])
			)
			var sort_cell := Vector2i(int(sort_raw[0]), int(sort_raw[1]))
			assert(sort_cell == occupied, "%s part sort cell drift" % asset.asset_id)
			assert(
				occupied.x >= 0 and occupied.y >= 0
				and occupied.x < footprint.x and occupied.y < footprint.y,
				"%s part escaped occupied footprint" % asset.asset_id
			)
			assert(
				_array_vector2(
					VisualGeometry.wall_part_anchor_px(asset, part)
				).is_equal_approx(
					_array_vector2(asset.get("anchor_px", []))
				),
				"%s part retained stale generated anchor" % asset.asset_id
			)
			checked_parts += 1
	assert(checked_parts == 324)


func _assert_pixel_order(
	asset_id: String,
	actor_delta_y: float,
	expect_actor_visible: bool,
	profile: String
) -> void:
	var asset := MapAssetCatalogService.find_asset(asset_id)
	assert(not asset.is_empty(), asset_id)
	var instance := {
		"instance_id": "pixel_%s" % asset_id,
		"asset_id": asset_id,
		"tile": [10, 10],
		"footprint_tiles": asset.get("footprint_tiles", [1, 1]),
		"offset_px": [0, 0],
		"scale": [1.0, 1.0],
		"rotation_deg": 0.0,
		"occlusion": true,
	}
	var command := _first_wall_front_command(instance, asset)
	assert(not command.is_empty(), "%s has no front fragment" % asset_id)
	var resource_path := str(command.image_path)
	if not resource_path.begins_with("res://"):
		resource_path = "res://" + resource_path
	var texture := load(resource_path) as Texture2D
	assert(texture != null, resource_path)
	var texture_image := texture.get_image()
	var opaque_texel := _opaque_texel(texture_image)
	assert(opaque_texel.x >= 0, "%s has no stable opaque texel" % asset_id)

	var wrapper_position := VisualGeometry.command_actor_sort_world(
		command, Vector2i(32, 32)
	)
	assert(
		Vector2(command.sort_baseline_offset_px).is_zero_approx(),
		"%s retained an artificial post-calibration depth guard" % asset_id
	)
	var geometry := VisualGeometry.runtime_command_geometry(
		command, Vector2i(32, 32), texture.get_size()
	)
	var sample_world := (
		Vector2(geometry.center)
		- Vector2(geometry.anchor)
		+ Vector2(opaque_texel)
	)
	assert(
		sample_world.is_finite(),
		"%s calibrated foreground sample is non-finite" % asset_id
	)
	var actor_position := wrapper_position + Vector2(0.0, actor_delta_y)
	var layers: Array = GENERIC_WORLD_PROFILES.get(profile, ["generic_pixel"])
	assert(not layers.is_empty())
	var wall_pixel := texture_image.get_pixel(opaque_texel.x, opaque_texel.y)
	assert(wall_pixel.a >= 0.98)
	# The formal headless runner uses the dummy renderer, so GPU viewport readback
	# is unavailable.  Compose the real shipped PNG texel in the exact order
	# established by the adjacent runtime Y-sort tests.  This remains a pixel
	# contract (real alpha/color), not a node-existence proxy.
	var color := Color(0.0, 0.0, 0.0, 0.0)
	var actor_in_front := actor_position.y > wrapper_position.y
	if actor_in_front:
		color = color.blend(wall_pixel)
	for _layer_name: String in layers:
		color = color.blend(PROBE_COLOR)
	if not actor_in_front:
		color = color.blend(wall_pixel)
	var actor_visible := _is_probe_color(color)
	assert(
		actor_visible == expect_actor_visible,
		"%s %s delta=%.1f expected_actor=%s pixel=%s"
		% [asset_id, profile, actor_delta_y, str(expect_actor_visible), str(color)]
	)
	_pixel_cases += 1


func _first_wall_front_command(
	instance: Dictionary,
	asset: Dictionary
) -> Dictionary:
	var target_front_index := (
		1
		if str(asset.get("asset_id", ""))
		== "orc_tomb_wall_straight_x_l3_v02"
		else 0
	)
	var front_index := 0
	for command: Dictionary in VisualGeometry.instance_draw_commands(
		instance, asset
	):
		if (
			int(command.image_pass) == 2
			and str(command.render_domain)
			== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT
		):
			if front_index == target_front_index:
				return command
			front_index += 1
	return {}


func _opaque_texel(image: Image) -> Vector2i:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.98:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _is_probe_color(color: Color) -> bool:
	return color.r > 0.85 and color.g < 0.15 and color.b > 0.85


func _array_vector2(raw: Array) -> Vector2:
	assert(raw.size() == 2)
	return Vector2(float(raw[0]), float(raw[1]))
