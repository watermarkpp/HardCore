extends Node2D

const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

const PUBLISHED_RUNTIME_MAPS := [
	"bich_province",
	"orc_tomb_1",
	"orc_tomb_2",
	"orc_tomb_3",
	"wooma_forest",
	"wooma_temple_1",
	"wooma_temple_2",
	"wooma_temple_3",
	"bich_mine_1",
	"bich_mine_2",
	"corpse_king_hall",
]
const SHAPE_ASSETS := {
	"straight_x": "orc_tomb_wall_straight_x_l3_v01",
	"straight_y": "orc_tomb_wall_straight_y_l3_v01",
	"inner_corner": "orc_tomb_wall_inner_nw_v01",
	"outer_corner": "orc_tomb_wall_outer_nw_v01",
	"seam": "orc_tomb_wall_straight_x_l3_v02",
	"door": "orc_tomb_wall_door_x_open_v01",
}

var _published_wall_assets := {}
var _published_wall_instances := 0
var _published_parts := 0
var _paired_parts := 0
var _base_only_parts := 0
var _base_only_pixels := 0
var _front_only_pixels := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MapAssetCatalogService.invalidate_cache()
	_audit_published_wall_pixels()
	var fixture := _shape_fixture()
	var commands := VisualGeometry.sorted_draw_commands(fixture.instances)
	var actor_groups := _assert_atomic_command_contract(commands)
	await _assert_world_background_graph(fixture, commands, actor_groups)
	_assert_monotonic_crossing(commands)
	print(
		(
			"WALL_ATOMIC_FOREGROUND_OCCLUSION_RUNTIME_PASS "
			+ "contract=%s published_assets=%d published_instances=%d "
			+ "published_parts=%d paired_parts=%d base_only_parts=%d "
			+ "base_only_pixels=%d front_only_pixels=%d shapes=6 "
			+ "atomic_wrappers=%d per_frame_processing=false shader=false"
		)
		% [
			VisualGeometry.OCCLUSION_SORT_CONTRACT_ID,
			_published_wall_assets.size(),
			_published_wall_instances,
			_published_parts,
			_paired_parts,
			_base_only_parts,
			_base_only_pixels,
			_front_only_pixels,
			actor_groups.size(),
		]
	)
	get_tree().quit(0)


func _audit_published_wall_pixels() -> void:
	for map_key: String in PUBLISHED_RUNTIME_MAPS:
		var loaded := MapEditorRuntimeMapService.load_runtime(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		assert(loaded.ok, "%s:%s" % [map_key, loaded.get("errors", [])])
		for instance: Dictionary in loaded.runtime.get("instances", []):
			var asset := MapAssetCatalogService.find_asset(
				str(instance.get("asset_id", ""))
			)
			if str(asset.get("asset_type", "")) != "wall_module":
				continue
			_published_wall_instances += 1
			var asset_id := str(asset.get("asset_id", ""))
			if _published_wall_assets.has(asset_id):
				continue
			_published_wall_assets[asset_id] = true
			_audit_asset_parts(asset)
	assert(_published_wall_assets.size() == 41)
	assert(_published_wall_instances == 559)
	assert(_published_parts == 116)
	assert(_paired_parts == 97)
	assert(_base_only_parts == 19)
	assert(_base_only_pixels > 0)
	assert(_front_only_pixels > 0)


func _audit_asset_parts(asset: Dictionary) -> void:
	var composite := _load_image(str(asset.get("image", "")))
	assert(composite != null, str(asset.get("asset_id", "")))
	for part: Dictionary in asset.get("render_parts", []):
		_published_parts += 1
		var base_path := str(part.get("base_image", ""))
		var front_path := str(part.get("front_image", ""))
		var shadow_path := str(part.get("shadow_image", ""))
		assert(not base_path.is_empty(), "%s lacks base" % asset.asset_id)
		var base := _load_image(base_path)
		assert(base != null and base.get_size() == composite.get_size())
		_assert_alpha_subset(base, composite, "%s base escaped composite" % asset.asset_id)
		if front_path.is_empty():
			_base_only_parts += 1
			assert(shadow_path.is_empty(), "%s base-only part retained shadow" % asset.asset_id)
			continue
		var front := _load_image(front_path)
		var shadow := _load_image(shadow_path)
		assert(front != null and front.get_size() == base.get_size())
		assert(shadow != null and shadow.get_size() == base.get_size())
		_assert_alpha_subset(front, composite, "%s front escaped composite" % asset.asset_id)
		var counts := _exclusive_alpha_counts(base, front)
		assert(int(counts.base_only) > 0, "%s lacks base-only wall pixels" % asset.asset_id)
		assert(int(counts.front_only) > 0, "%s lacks front-only wall pixels" % asset.asset_id)
		assert(_opaque_pixel_count(base) > 0, "%s base is not an opaque wall layer" % asset.asset_id)
		assert(_high_alpha_pixel_count(shadow) == 0, "%s shadow contains opaque wall pixels" % asset.asset_id)
		_paired_parts += 1
		_base_only_pixels += int(counts.base_only)
		_front_only_pixels += int(counts.front_only)


func _assert_atomic_command_contract(commands: Array[Dictionary]) -> Dictionary:
	var groups := {}
	var expected_group_images := {}
	for command: Dictionary in commands:
		assert(str(command.asset.get("asset_type", "")) == "wall_module")
		var image_pass := int(command.get("image_pass", -1))
		var domain := str(command.get("render_domain", ""))
		if image_pass == 0:
			assert(domain == VisualGeometry.RENDER_DOMAIN_STATIC_BACKGROUND)
			assert(str(command.get("actor_sort_group", "")).is_empty())
			continue
		assert(
			domain == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT,
			"wall base/front escaped actor Y-sort: %s" % command.image_path
		)
		var group_key := str(command.get("actor_sort_group", ""))
		assert(not group_key.is_empty(), "wall pass lacks atomic group: %s" % command.image_path)
		var sort_tile := Vector2(command.get("sort_tile", Vector2.ZERO))
		assert(
			Vector2(command.get("sort_baseline_tile", Vector2.ZERO)).is_equal_approx(
				sort_tile + VisualGeometry.WALL_PART_SORT_BASELINE_TILE_OFFSET
			),
			"wall group lost occupied-cell centre baseline"
		)
		var part_anchor := _part_anchor_for_command(command)
		assert(
			_array_vector2(command.get("anchor", [])).is_equal_approx(part_anchor),
			"wall command activated a different anchor coordinate space"
		)
		groups[group_key] = true
		if not expected_group_images.has(group_key):
			expected_group_images[group_key] = []
		expected_group_images[group_key].append({
			"pass": image_pass,
			"path": str(command.get("image_path", "")),
		})
	for group_key: String in expected_group_images:
		var images: Array = expected_group_images[group_key]
		images.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.pass) < int(b.pass))
		assert(int(images[0].pass) == 1, "%s does not begin with base" % group_key)
		assert(int(images[-1].pass) == 2, "%s does not end with front" % group_key)
	return groups


func _assert_world_background_graph(
	fixture: Dictionary,
	commands: Array[Dictionary],
	actor_groups: Dictionary
) -> void:
	var runtime_root := Node2D.new()
	runtime_root.name = "AtomicWallActorYSort"
	runtime_root.y_sort_enabled = true
	add_child(runtime_root)
	var background := WorldBackground.new()
	background.name = "AtomicWallBackground"
	runtime_root.add_child(background)
	background._build_editor_runtime_instances(fixture)
	await get_tree().process_frame

	var wrappers := {}
	for child: Node in runtime_root.get_children():
		if not bool(child.get_meta("editor_runtime_actor_occluder", false)):
			continue
		if not str(child.get_meta("editor_runtime_instance_id", "")).begins_with("atomic_"):
			continue
		var group_key := str(child.get_meta("editor_runtime_actor_sort_group", ""))
		assert(not group_key.is_empty(), "wall wrapper lacks atomic group metadata")
		assert(not wrappers.has(group_key), "%s created more than one wrapper" % group_key)
		assert(not child.is_processing() and not child.is_physics_processing())
		wrappers[group_key] = child
	assert(wrappers.size() == actor_groups.size())

	var expected_by_group := {}
	var expected_static := {}
	for command: Dictionary in commands:
		var path := str(command.get("image_path", ""))
		var group_key := str(command.get("actor_sort_group", ""))
		if group_key.is_empty():
			expected_static[path] = int(expected_static.get(path, 0)) + 1
			continue
		if not expected_by_group.has(group_key):
			expected_by_group[group_key] = []
		expected_by_group[group_key].append({
			"pass": int(command.get("image_pass", -1)),
			"path": path,
		})
	for group_key: String in expected_by_group:
		var wrapper: Node2D = wrappers[group_key]
		var expected: Array = expected_by_group[group_key]
		expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.pass) < int(b.pass))
		assert(wrapper.get_child_count() == expected.size())
		for index in expected.size():
			var sprite := wrapper.get_child(index) as Sprite2D
			assert(sprite != null and sprite.material == null)
			assert(str(sprite.get_meta("editor_runtime_image_path", "")) == str(expected[index].path))
			assert(str(sprite.get_meta("editor_runtime_render_domain", "")) == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
		assert(int(expected[0].pass) == 1 and int(expected[-1].pass) == 2)

	var actual_static := {}
	for child: Node in background.get_children():
		if not child is Sprite2D:
			continue
		if not str(child.get_meta("editor_runtime_instance_id", "")).begins_with("atomic_"):
			continue
		var path := str(child.get_meta("editor_runtime_image_path", ""))
		if path.is_empty():
			continue
		assert(str(child.get_meta("editor_runtime_render_domain", "")) == VisualGeometry.RENDER_DOMAIN_STATIC_BACKGROUND)
		actual_static[path] = int(actual_static.get(path, 0)) + 1
	assert(actual_static == expected_static, "shadow/static wall passes changed")
	runtime_root.queue_free()


func _assert_monotonic_crossing(commands: Array[Dictionary]) -> void:
	var sampled := {}
	for command: Dictionary in commands:
		if int(command.get("image_pass", -1)) != 1:
			continue
		var asset_id := str(command.asset.get("asset_id", ""))
		if sampled.has(asset_id):
			continue
		sampled[asset_id] = true
		var baseline := VisualGeometry.command_actor_sort_world(command, Vector2i(32, 32))
		var previous_y := -INF
		var crossed := 0
		for delta_y: float in [-12.0, -4.0, -1.0, 1.0, 4.0, 12.0]:
			var actor_y := (baseline + Vector2(0.0, delta_y)).y
			assert(actor_y > previous_y, "%s crossing is not monotonic" % asset_id)
			if actor_y > baseline.y:
				crossed += 1
			previous_y = actor_y
		assert(crossed == 3, "%s crossing changed at the occupied-cell centre" % asset_id)
	assert(sampled.size() == SHAPE_ASSETS.size())


func _shape_fixture() -> Dictionary:
	var instances: Array[Dictionary] = []
	var index := 0
	for label: String in SHAPE_ASSETS:
		var asset_id := str(SHAPE_ASSETS[label])
		var asset := MapAssetCatalogService.find_asset(asset_id)
		assert(not asset.is_empty(), asset_id)
		instances.append({
			"instance_id": "atomic_%s" % label,
			"asset_id": asset_id,
			"layer": "object_base",
			"tile": [4 + index * 6, 10],
			"footprint_tiles": asset.get("footprint_tiles", [1, 1]),
			"offset_px": [0, 0],
			"scale": [1.0, 1.0],
			"rotation_deg": 0.0,
			"occlusion": true,
		})
		index += 1
	return {
		"design": {"design_size": [64, 64]},
		"instances": instances,
	}


func _part_anchor_for_command(command: Dictionary) -> Vector2:
	var image_path := str(command.get("image_path", ""))
	for part: Dictionary in command.asset.get("render_parts", []):
		for field: String in ["shadow_image", "base_image", "front_image"]:
			if str(part.get(field, "")) == image_path:
				return _array_vector2(part.get("anchor", [0, 0]))
	assert(false, "command image does not belong to a render part: %s" % image_path)
	return Vector2.ZERO


func _load_image(path: String) -> Image:
	if path.is_empty():
		return null
	var resource_path := path if path.begins_with("res://") else "res://" + path
	var texture := load(resource_path) as Texture2D
	return texture.get_image() if texture != null else null


func _assert_alpha_subset(image: Image, composite: Image, message: String) -> void:
	assert(image.get_size() == composite.get_size())
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				assert(composite.get_pixel(x, y).a > 0.0, message)


func _exclusive_alpha_counts(base: Image, front: Image) -> Dictionary:
	var base_only := 0
	var front_only := 0
	for y in base.get_height():
		for x in base.get_width():
			var base_alpha := base.get_pixel(x, y).a
			var front_alpha := front.get_pixel(x, y).a
			if base_alpha > 0.0 and front_alpha == 0.0:
				base_only += 1
			elif front_alpha > 0.0 and base_alpha == 0.0:
				front_only += 1
	return {"base_only": base_only, "front_only": front_only}


func _opaque_pixel_count(image: Image) -> int:
	var result := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.75:
				result += 1
	return result


func _high_alpha_pixel_count(image: Image) -> int:
	var result := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.75:
				result += 1
	return result


func _array_vector2(raw: Array) -> Vector2:
	assert(raw.size() == 2)
	return Vector2(float(raw[0]), float(raw[1]))
