extends Node2D

const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const RELEASE_REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const F1_OVERLAY_HASH := (
	"521215ee6a2a29f0741908c7b6abc07a48b15f0af33296b6455a53b63f6cdf30"
)
const MULTI_DECOR_FIXTURE_HASH := (
	"fd131e6eebd139e6be5ee5a137af7e182918d8224d0791cc9aad68c7b5b5886c"
)
const MAX_F1_SCANNED_OBJECT_PIXELS := 111084
const MAX_BRIDGE_BUILD_USEC := 1000000
const EXPECTED_PUBLISHED_DECOR_PAIRS := 7178

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
	_assert_bridge_does_not_expand_geometry_contract()
	_audit_published_wall_pixels()
	_audit_all_published_bridge_pairs()
	await _assert_static_authored_bridge_fixture()
	await _assert_orc_tomb_f1_real_bridge()
	await _assert_named_real_png_overlap_preservation()
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


func _audit_all_published_bridge_pairs() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(RELEASE_REGISTRY_PATH)
	)
	assert(parsed is Dictionary, "release registry is not a dictionary")
	var registry: Dictionary = parsed
	var entries: Array = registry.get("maps", [])
	assert(not entries.is_empty(), "release registry contains no published maps")
	var texture_size_cache := {}
	var covered_maps := 0
	var maps_with_walls := 0
	var maps_with_pairs := 0
	var total_wall_groups := 0
	var total_static_commands := 0
	var total_pairs := 0
	var total_preserved_pairs := 0
	var total_reversals := 0
	var total_terrain_floor_shadow_rejections := 0
	var maximum_map_pairs := 0
	for entry: Dictionary in entries:
		if str(entry.get("release_state", "")) != "implemented_playable":
			continue
		var runtime_path := str(entry.get("runtime_path", ""))
		var loaded := MapEditorRuntimeMapService.load_runtime(runtime_path)
		assert(loaded.ok, "%s: %s" % [runtime_path, loaded.get("errors", [])])
		var runtime: Dictionary = loaded.runtime
		var raw_size: Array = runtime.get("design", {}).get(
			"design_size", [64, 64]
		)
		var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var commands := VisualGeometry.sorted_draw_commands(
			runtime.get("instances", [])
		)
		var before_geometry_hash := VisualGeometry.geometry_sha256(runtime.instances)
		var before_sequence := _eligible_static_command_sequence(commands)
		var wall_groups := {}
		var static_records: Array[Dictionary] = []
		for command: Dictionary in commands:
			if (
				str(command.get("render_domain", ""))
					== VisualGeometry.RENDER_DOMAIN_STATIC_BACKGROUND
				and VisualGeometry.command_is_terrain_floor_or_shadow(command)
			):
				total_terrain_floor_shadow_rejections += 1
			if (
				not VisualGeometry.is_atomic_wall_pass(command)
				and not VisualGeometry.is_static_authored_wall_bridge_candidate(command)
			):
				continue
			var image_path := str(command.get("image_path", ""))
			var resource_path := (
				image_path if image_path.begins_with("res://")
				else "res://" + image_path
			)
			if not texture_size_cache.has(resource_path):
				var texture := load(resource_path) as Texture2D
				assert(texture != null, "bridge audit texture missing: %s" % resource_path)
				texture_size_cache[resource_path] = texture.get_size()
			var texture_size: Vector2 = texture_size_cache[resource_path]
			var transform := VisualGeometry.command_texture_transform(
				command, design_size, texture_size
			)
			var aabb := VisualGeometry.transformed_texture_aabb(
				transform, texture_size
			)
			if VisualGeometry.is_atomic_wall_pass(command):
				var group_key := str(command.get("actor_sort_group", ""))
				if not wall_groups.has(group_key):
					wall_groups[group_key] = {
						"base_command": {},
						"aabb": aabb,
					}
				var group: Dictionary = wall_groups[group_key]
				var group_aabb: Rect2i = group.aabb
				group.aabb = group_aabb.merge(aabb)
				if int(command.get("image_pass", -1)) == 1:
					group.base_command = command
			else:
				static_records.append({"command": command, "aabb": aabb})
		var map_pairs := 0
		for record: Dictionary in static_records:
			for group_key: String in wall_groups:
				var group: Dictionary = wall_groups[group_key]
				assert(
					not group.base_command.is_empty(),
					"atomic wall group lacks base: %s:%s" % [runtime_path, group_key]
				)
				if VisualGeometry.static_wall_bridge_pair_is_candidate(
					record.command, group.base_command, design_size,
					record.aabb, group.aabb
				):
					map_pairs += 1
		# The bridge may inspect every eligible command, but it must never mutate
		# the authored sort inputs or reorder even one decoration-decoration pair.
		var after_commands := VisualGeometry.sorted_draw_commands(
			runtime.get("instances", [])
		)
		assert(
			VisualGeometry.geometry_sha256(runtime.instances) == before_geometry_hash,
			"%s bridge audit changed geometry payload" % runtime_path
		)
		var after_sequence := _eligible_static_command_sequence(after_commands)
		assert(
			after_sequence == before_sequence,
			"%s changed eligible static command sequence" % runtime_path
		)
		var after_positions := {}
		for after_index in after_sequence.size():
			after_positions[str(after_sequence[after_index][0])] = after_index
		var map_preserved_pairs := 0
		var map_reversals := 0
		for before_index in before_sequence.size():
			for later_index in range(before_index + 1, before_sequence.size()):
				var first_key := str(before_sequence[before_index][0])
				var second_key := str(before_sequence[later_index][0])
				map_preserved_pairs += 1
				if int(after_positions[first_key]) >= int(after_positions[second_key]):
					map_reversals += 1
		assert(map_reversals == 0, "%s decor pair reversals=%d" % [runtime_path, map_reversals])
		covered_maps += 1
		if not wall_groups.is_empty():
			maps_with_walls += 1
		if map_pairs > 0:
			maps_with_pairs += 1
		total_wall_groups += wall_groups.size()
		total_static_commands += static_records.size()
		total_pairs += map_pairs
		total_preserved_pairs += map_preserved_pairs
		total_reversals += map_reversals
		maximum_map_pairs = maxi(maximum_map_pairs, map_pairs)
		print(
			(
				"STATIC_WALL_BRIDGE_MAP_AUDIT map=%s walls=%d static=%d pairs=%d "
				+ "decor_pairs=%d reversals=%d"
			)
			% [
				str(entry.get("map_key", "")), wall_groups.size(),
				static_records.size(), map_pairs, map_preserved_pairs, map_reversals,
			]
		)
	assert(covered_maps == entries.size())
	assert(maps_with_walls > 0 and maps_with_pairs > 0)
	assert(total_wall_groups > 0 and total_static_commands > 0 and total_pairs > 0)
	assert(total_preserved_pairs == EXPECTED_PUBLISHED_DECOR_PAIRS)
	assert(total_reversals == 0)
	assert(total_terrain_floor_shadow_rejections > 0)
	print(
		(
			"STATIC_WALL_BRIDGE_ALL_PUBLISHED_PASS maps=%d maps_with_walls=%d "
			+ "maps_with_pairs=%d wall_groups=%d static_commands=%d pairs=%d "
			+ "max_map_pairs=%d decor_pairs=%d reversals=%d "
			+ "terrain_floor_shadow_rejected=%d textures=%d"
		)
		% [
			covered_maps, maps_with_walls, maps_with_pairs, total_wall_groups,
			total_static_commands, total_pairs, maximum_map_pairs,
			total_preserved_pairs, total_reversals,
			total_terrain_floor_shadow_rejections, texture_size_cache.size(),
		]
	)


func _assert_bridge_does_not_expand_geometry_contract() -> void:
	var asset := MapAssetCatalogService.find_asset("cave_dungeon.wood_crate_01")
	assert(not asset.is_empty())
	var ordinary := {
		"instance_id": "geometry_contract",
		"asset_id": str(asset.asset_id),
		"layer": "object_base",
		"tile": [3, 4],
		"footprint_tiles": asset.get("footprint_tiles", [1, 1]),
		"offset_px": [7, -3],
		"scale": [1.25, 0.75],
		"rotation_deg": 17.0,
		"occlusion": false,
	}
	var legacy_flip_fields := ordinary.duplicate(true)
	legacy_flip_fields.flip_x = true
	legacy_flip_fields.flip_y = true
	var texture := load("res://" + str(asset.image)) as Texture2D
	assert(texture != null)
	var ordinary_command := VisualGeometry.sorted_draw_commands([ordinary])[0]
	var flip_command := VisualGeometry.sorted_draw_commands([legacy_flip_fields])[0]
	var ordinary_geometry := VisualGeometry.runtime_command_geometry(
		ordinary_command, Vector2i(32, 32), texture.get_size()
	)
	var flip_geometry := VisualGeometry.runtime_command_geometry(
		flip_command, Vector2i(32, 32), texture.get_size()
	)
	assert(
		ordinary_geometry == flip_geometry,
		"bridge must not make dormant flip fields alter existing runtime geometry"
	)


func _eligible_static_command_sequence(commands: Array[Dictionary]) -> Array:
	var result := []
	for command: Dictionary in commands:
		if not VisualGeometry.is_static_authored_wall_bridge_candidate(command):
			continue
		var instance: Dictionary = command.get("instance", {})
		# sequence is the stable command identity before sorting. Every field that
		# participates in the existing draw order is retained in this payload.
		result.append([
			int(command.get("sequence", -1)),
			int(command.get("command_index", -1)),
			str(instance.get("instance_id", "")),
			str(command.get("image_path", "")),
			MapEditorInstanceService.material_layer_order(instance),
			Vector2i(command.get("sort_tile", Vector2i.ZERO)),
			int(command.get("layer_index", -1)),
			int(command.get("image_pass", -1)),
			int(command.get("part_order", -1)),
			str(command.get("render_domain", "")),
		])
	return result


func _assert_named_real_png_overlap_preservation() -> void:
	var parsed: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(RELEASE_REGISTRY_PATH)
	)
	var image_cache := {}
	var required_found := {
		"zuma_pavilion_carpet": false,
		"unknown_palace_carpet": false,
		"chiyue_rock_mushroom": false,
		"wooma_carpet_brazier": false,
	}
	var preserved_visible_pairs := 0
	var checked_maps := 0
	for entry: Dictionary in parsed.get("maps", []):
		if str(entry.get("release_state", "")) != "implemented_playable":
			continue
		var map_key := str(entry.get("map_key", ""))
		if not (
			map_key == "mengzhong_zuma_pavilion"
			or map_key == "snake_unknown_dark_palace"
			or map_key.begins_with("chiyue_")
			or map_key.begins_with("wooma_temple_")
		):
			continue
		var runtime_path := str(entry.get("runtime_path", ""))
		var loaded := MapEditorRuntimeMapService.load_runtime(runtime_path)
		assert(loaded.ok, "%s: %s" % [runtime_path, loaded.get("errors", [])])
		var runtime: Dictionary = loaded.runtime
		var raw_size: Array = runtime.get("design", {}).get("design_size", [64, 64])
		var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var commands := VisualGeometry.sorted_draw_commands(runtime.instances)
		var wall_overlap_hashes := _visible_decor_wall_overlap_hashes(
			commands, design_size, image_cache, map_key
		)
		var map_matches_required := false
		for pair_key: String in wall_overlap_hashes:
			var lower := pair_key.to_lower()
			if map_key == "mengzhong_zuma_pavilion" and "carpet" in lower:
				required_found.zuma_pavilion_carpet = true
				map_matches_required = true
			if map_key == "snake_unknown_dark_palace" and "carpet" in lower:
				required_found.unknown_palace_carpet = true
				map_matches_required = true
			if (
				map_key.begins_with("chiyue_")
				and ("rock" in lower or "岩石" in lower)
				and ("蘑菇" in pair_key or "mush" in lower)
			):
				required_found.chiyue_rock_mushroom = true
				map_matches_required = true
			if (
				map_key.begins_with("wooma_temple_")
				and "carpet" in lower
				and "brazier" in lower
			):
				required_found.wooma_carpet_brazier = true
				map_matches_required = true
		if not map_matches_required:
			continue
		preserved_visible_pairs += wall_overlap_hashes.size()
		checked_maps += 1
		print(
			(
				"STATIC_DECOR_ORDER_REPRESENTATIVE_MAP_PASS map=%s "
				+ "representative_pairs=%d hashes=%s"
			)
			% [map_key, wall_overlap_hashes.size(), _aggregate_hash(wall_overlap_hashes)]
		)
	for required_key: String in required_found:
		assert(required_found[required_key], "missing real PNG overlap: %s" % required_key)
	assert(checked_maps > 0 and preserved_visible_pairs > 0)
	print(
		"STATIC_DECOR_ORDER_REPRESENTATIVE_ALL_PASS maps=%d representative_pairs=%d reversals=0"
		% [checked_maps, preserved_visible_pairs]
	)
	await get_tree().process_frame


func _visible_decor_wall_overlap_hashes(
	commands: Array[Dictionary],
	design_size: Vector2i,
	image_cache: Dictionary,
	map_key: String
) -> Dictionary:
	var records: Array[Dictionary] = []
	var wall_bases: Array[Dictionary] = []
	for command: Dictionary in commands:
		if (
			not VisualGeometry.is_static_authored_wall_bridge_candidate(command)
			and not (
				VisualGeometry.is_atomic_wall_pass(command)
				and int(command.get("image_pass", -1)) == 1
			)
		):
			continue
		var record := _decor_pixel_record(command, design_size, image_cache)
		assert(not record.is_empty(), "missing decor pixels: %s" % command.get("image_path", ""))
		if VisualGeometry.is_atomic_wall_pass(command):
			wall_bases.append(record)
		else:
			records.append(record)
	var result := {}
	for first_index in records.size():
		var first: Dictionary = records[first_index]
		for second_index in range(first_index + 1, records.size()):
			var second: Dictionary = records[second_index]
			if not _is_named_overlap_pair(map_key, first.command, second.command):
				continue
			var overlap: Rect2i = first.aabb.intersection(second.aabb)
			if overlap.size.x <= 0 or overlap.size.y <= 0:
				continue
			var context := HashingContext.new()
			context.start(HashingContext.HASH_SHA256)
			var decor_overlap_pixels := 0
			var order_sensitive_pixels := 0
			for world_y in range(overlap.position.y, overlap.end.y):
				for world_x in range(overlap.position.x, overlap.end.x):
					var world_pixel := Vector2i(world_x, world_y)
					var bottom := _sample_decor_pixel(first, world_pixel)
					var top := _sample_decor_pixel(second, world_pixel)
					if bottom.a <= 0.0 or top.a <= 0.0:
						continue
					decor_overlap_pixels += 1
					var composite := VisualGeometry.static_wall_bridge_compose_ordered_colors(
						[bottom, top]
					)
					var swapped := VisualGeometry.static_wall_bridge_compose_ordered_colors(
						[top, bottom]
					)
					if composite.to_rgba32() != swapped.to_rgba32():
						order_sensitive_pixels += 1
					context.update(
						(
							"D:%d,%d:%08x:%08x:%08x;"
							% [
								world_x, world_y, bottom.to_rgba32(),
								top.to_rgba32(), composite.to_rgba32(),
							]
						).to_utf8_buffer()
					)
			if decor_overlap_pixels <= 0:
				continue
			var first_wall_pixels := 0
			var second_wall_pixels := 0
			var shared_wall_pixels := 0
			for wall_base: Dictionary in wall_bases:
				var first_front := VisualGeometry.static_authored_command_is_in_front_of_wall(
					first.command, wall_base.command, design_size
				)
				var second_front := VisualGeometry.static_authored_command_is_in_front_of_wall(
					second.command, wall_base.command, design_size
				)
				if not first_front and not second_front:
					continue
				var pair_bounds: Rect2i = first.aabb.merge(second.aabb)
				var wall_overlap := pair_bounds.intersection(wall_base.aabb)
				if wall_overlap.size.x <= 0 or wall_overlap.size.y <= 0:
					continue
				for world_y in range(wall_overlap.position.y, wall_overlap.end.y):
					for world_x in range(wall_overlap.position.x, wall_overlap.end.x):
						var world_pixel := Vector2i(world_x, world_y)
						var bottom := _sample_decor_pixel(first, world_pixel)
						var top := _sample_decor_pixel(second, world_pixel)
						var wall := _sample_decor_pixel(wall_base, world_pixel)
						if wall.a <= 0.0:
							continue
						var colors: Array[Color] = []
						if first_front and bottom.a > 0.0:
							first_wall_pixels += 1
							colors.append(bottom)
						if second_front and top.a > 0.0:
							second_wall_pixels += 1
							colors.append(top)
						if colors.is_empty():
							continue
						if colors.size() == 2:
							shared_wall_pixels += 1
						var wall_composite := VisualGeometry.static_wall_bridge_compose_ordered_colors(
							colors
						)
						context.update(
							(
								"W:%d,%d:%d:%08x;"
								% [
									world_x, world_y,
									int(wall_base.command.get("command_index", -1)),
									wall_composite.to_rgba32(),
								]
							).to_utf8_buffer()
						)
			if (
				first_wall_pixels + second_wall_pixels <= 0
				and not map_key.begins_with("wooma_temple_")
			):
				continue
			assert(
				order_sensitive_pixels > 0,
				"representative decor pair is not order-sensitive: %s" % map_key
			)
			var first_command: Dictionary = first.command
			var second_command: Dictionary = second.command
			var pair_key := "%s|%s||%s|%s" % [
				str(first_command.get("instance", {}).get("instance_id", "")),
				str(first_command.get("image_path", "")),
				str(second_command.get("instance", {}).get("instance_id", "")),
				str(second_command.get("image_path", "")),
			]
			result[pair_key] = "%d:%d:%d:%d:%d:%s" % [
				decor_overlap_pixels, order_sensitive_pixels,
				first_wall_pixels, second_wall_pixels, shared_wall_pixels,
				context.finish().hex_encode()
			]
			# One real, order-sensitive representative is sufficient for each named
			# map family; the all-published gate above already covers every pair.
			return result
	return result


func _is_named_overlap_pair(
	map_key: String,
	first_command: Dictionary,
	second_command: Dictionary
) -> bool:
	var first_path := str(first_command.get("image_path", ""))
	var second_path := str(second_command.get("image_path", ""))
	var lower := (first_path + "|" + second_path).to_lower()
	if map_key in ["mengzhong_zuma_pavilion", "snake_unknown_dark_palace"]:
		return "carpet" in lower
	if map_key.begins_with("chiyue_"):
		return (
			("rock" in lower or "岩石" in first_path or "岩石" in second_path)
			and ("mush" in lower or "蘑菇" in first_path or "蘑菇" in second_path)
		)
	if map_key.begins_with("wooma_temple_"):
		return "carpet" in lower and "brazier" in lower
	return false


func _decor_pixel_record(
	command: Dictionary,
	design_size: Vector2i,
	image_cache: Dictionary
) -> Dictionary:
	var image_path := str(command.get("image_path", ""))
	var resource_path := image_path if image_path.begins_with("res://") else "res://" + image_path
	var image: Image = image_cache.get(resource_path) as Image
	var texture_size := Vector2.ZERO
	if image == null:
		var texture := load(resource_path) as Texture2D
		if texture == null:
			return {}
		image = texture.get_image()
		texture_size = texture.get_size()
		image_cache[resource_path] = image
	else:
		texture_size = Vector2(image.get_size())
	var transform := VisualGeometry.command_texture_transform(
		command, design_size, texture_size
	)
	return {
		"command": command,
		"image": image,
		"inverse": transform.affine_inverse(),
		"aabb": VisualGeometry.transformed_texture_aabb(transform, texture_size),
	}


func _sample_decor_pixel(record: Dictionary, world_pixel: Vector2i) -> Color:
	var source: Vector2 = record.inverse * (Vector2(world_pixel) + Vector2(0.5, 0.5))
	var pixel := Vector2i(floori(source.x), floori(source.y))
	var image: Image = record.image
	if (
		pixel.x < 0 or pixel.y < 0
		or pixel.x >= image.get_width() or pixel.y >= image.get_height()
	):
		return Color(0, 0, 0, 0)
	return image.get_pixelv(pixel)


func _aggregate_hash(values: Dictionary) -> String:
	var keys := values.keys()
	keys.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for key: String in keys:
		context.update((key + "=" + str(values[key]) + "\n").to_utf8_buffer())
	return context.finish().hex_encode()


func _assert_static_authored_bridge_fixture() -> void:
	var wall_asset := MapAssetCatalogService.find_asset(
		"orc_tomb_wall_straight_x_l3_v01"
	)
	var object_asset := MapAssetCatalogService.find_asset(
		"cave_dungeon.wood_crate_01"
	)
	var second_object_asset := MapAssetCatalogService.find_asset(
		"cave_dungeon.pottery_cluster_01"
	)
	assert(
		not wall_asset.is_empty()
		and not object_asset.is_empty()
		and not second_object_asset.is_empty()
	)
	var fixture := {
		"design": {"design_size": [32, 32]},
		"instances": [
			{
				"instance_id": "bridge_wall",
				"asset_id": str(wall_asset.asset_id),
				"layer": "object_base",
				"tile": [10, 10],
				"footprint_tiles": wall_asset.get("footprint_tiles", [1, 1]),
				"offset_px": [0, 0],
				"scale": [1.0, 1.0],
				"rotation_deg": 0.0,
				"occlusion": true,
				"material_layer_order": 0,
			},
			{
				"instance_id": "bridge_crate",
				"asset_id": str(object_asset.asset_id),
				"layer": "object_base",
				"tile": [10, 10],
				"footprint_tiles": object_asset.get("footprint_tiles", [1, 1]),
				"offset_px": [0, 0],
				"scale": [1.0, 1.0],
				"rotation_deg": 0.0,
				"occlusion": false,
				"material_layer_order": 1,
			},
			{
				"instance_id": "bridge_pottery",
				"asset_id": str(second_object_asset.asset_id),
				"layer": "object_base",
				"tile": [10, 10],
				"footprint_tiles": second_object_asset.get("footprint_tiles", [1, 1]),
				"offset_px": [0, 0],
				"scale": [1.0, 1.0],
				"rotation_deg": 0.0,
				"occlusion": false,
				"material_layer_order": 2,
			},
		],
	}
	var runtime_root := Node2D.new()
	runtime_root.y_sort_enabled = true
	add_child(runtime_root)
	var background := WorldBackground.new()
	runtime_root.add_child(background)
	background.clear_environment()
	background._build_editor_runtime_instances(fixture)
	var stats := background.static_wall_bridge_stats()
	print("STATIC_BRIDGE_FIXTURE_STATS ", stats)
	assert(int(stats.candidate_pairs) > 0)
	assert(int(stats.scanned_pixels) > 0)
	assert(int(stats.overlay_count) > 0)
	_assert_bridge_build_metrics(stats)
	var fixture_order_proof := _assert_actual_overlay_matches_original_static_order(
		VisualGeometry.sorted_draw_commands(fixture.instances),
		Vector2i(32, 32), runtime_root, true
	)
	assert(str(fixture_order_proof.hash) == MULTI_DECOR_FIXTURE_HASH)
	print("STATIC_BRIDGE_MULTI_DECOR_FIXTURE_PASS ", fixture_order_proof)
	runtime_root.queue_free()
	await get_tree().process_frame

	# A static-only map takes the metadata fast path before any bridge texture is
	# hydrated. Sprite construction may load its normal texture, but the bridge
	# itself must decode zero Images.
	var no_wall_root := Node2D.new()
	add_child(no_wall_root)
	var no_wall_background := WorldBackground.new()
	no_wall_root.add_child(no_wall_background)
	no_wall_background.clear_environment()
	no_wall_background._build_editor_runtime_instances({
		"design": fixture.design,
		"instances": [fixture.instances[1], fixture.instances[2]],
	})
	var no_wall_stats := no_wall_background.static_wall_bridge_stats()
	assert(int(no_wall_stats.candidate_pairs) == 0)
	assert(int(no_wall_stats.scanned_pixels) == 0)
	assert(int(no_wall_stats.hydrated_textures) == 0)
	assert(int(no_wall_stats.hydrated_bytes) == 0)
	assert(int(no_wall_stats.build_usec) <= MAX_BRIDGE_BUILD_USEC)
	print("STATIC_BRIDGE_NO_WALL_FAST_PATH_PASS ", no_wall_stats)
	no_wall_root.queue_free()
	await get_tree().process_frame

	# Production builds the same commands through staged descriptors. This also
	# locks the base/front wrapper cache: one wall part must not split into two
	# roots merely because its passes arrive as separate build items.
	var staged_root := Node2D.new()
	staged_root.y_sort_enabled = true
	add_child(staged_root)
	var staged_background := WorldBackground.new()
	staged_root.add_child(staged_background)
	staged_background.clear_environment()
	var descriptors: Array = []
	staged_background._append_instance_descriptors(descriptors, fixture, -1)
	for descriptor: Dictionary in descriptors:
		staged_background.build_one_map_item(descriptor)
	staged_background.finish_map_build()
	var staged_stats := staged_background.static_wall_bridge_stats()
	assert(int(staged_stats.overlay_count) == int(stats.overlay_count))
	var staged_groups := {}
	for child: Node in staged_root.get_children():
		if not bool(child.get_meta("editor_runtime_actor_occluder", false)):
			continue
		if str(child.get_meta("editor_runtime_instance_id", "")) != "bridge_wall":
			continue
		var group_key := str(child.get_meta("editor_runtime_actor_sort_group", ""))
		assert(not staged_groups.has(group_key), "%s split in staged build" % group_key)
		staged_groups[group_key] = true
	assert(not staged_groups.is_empty())
	staged_root.queue_free()


func _assert_orc_tomb_f1_real_bridge() -> void:
	var loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/orc_tomb_1.runtime.json"
	)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var commands := VisualGeometry.sorted_draw_commands(loaded.runtime.instances)
	var original_payload := []
	for command: Dictionary in commands:
		original_payload.append([
			int(command.command_index),
			str(command.get("instance", {}).get("instance_id", "")),
			str(command.render_domain),
			int(command.image_pass),
			MapEditorInstanceService.material_layer_order(command.instance),
		])
	var runtime_root := Node2D.new()
	runtime_root.y_sort_enabled = true
	add_child(runtime_root)
	var background := WorldBackground.new()
	runtime_root.add_child(background)
	background.clear_environment()
	background._build_editor_runtime_instances(loaded.runtime)
	var stats := background.static_wall_bridge_stats()
	assert(int(stats.candidate_pairs) > 0)
	assert(int(stats.scanned_pixels) > 0)
	assert(int(stats.scanned_pixels) <= MAX_F1_SCANNED_OBJECT_PIXELS)
	assert(int(stats.overlay_count) > 0)
	_assert_bridge_build_metrics(stats)
	var original_static_indices := _original_static_command_indices(background)
	for command: Dictionary in commands:
		if VisualGeometry.is_static_authored_wall_bridge_candidate(command):
			assert(
				original_static_indices.has(int(command.command_index)),
				"bridge moved original static command %d" % int(command.command_index)
			)
	var source_ids := {}
	var overlay_pixels := {}
	for wrapper: Node in runtime_root.get_children():
		if not bool(wrapper.get_meta("editor_runtime_actor_occluder", false)):
			continue
		var first_front := -1
		for child_index in wrapper.get_child_count():
			var child := wrapper.get_child(child_index)
			if int(child.get_meta("editor_runtime_image_pass", -1)) == 2:
				first_front = child_index
				break
		for child_index in wrapper.get_child_count():
			var child := wrapper.get_child(child_index)
			if not bool(child.get_meta("static_authored_wall_bridge", false)):
				continue
			assert(first_front < 0 or child_index < first_front)
			for instance_id: String in child.get_meta(
				"static_wall_bridge_source_instance_ids", []
			):
				source_ids[instance_id] = true
			var rect: Rect2i = child.get_meta("static_wall_bridge_world_rect")
			var image := (child as Sprite2D).texture.get_image()
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x, y).a <= 0.0:
						continue
					var world_pixel := rect.position + Vector2i(x, y)
					assert(
						not overlay_pixels.has(world_pixel),
						"adjacent wall seam owns one overlay pixel twice"
					)
					overlay_pixels[world_pixel] = true
	# These are the real authored F1 crate/bone/corpse/pottery instances whose
	# alpha intersects a wall base after their original static command.
	print("STATIC_AUTHORED_WALL_BRIDGE_F1_SOURCES ", source_ids.keys())
	for required_id: String in [
		"inst_000097", "inst_000100", "inst_000101",
		"inst_000103", "inst_000105", "inst_000106",
	]:
		assert(source_ids.has(required_id), "%s did not bridge in Orc Tomb F1" % required_id)
	assert(
		not source_ids.has("inst_000102"),
		"the behind-wall F1 corpse incorrectly escaped through a bridge overlay"
	)
	var raw_size: Array = loaded.runtime.design.get("design_size", [64, 64])
	var overlay_order_proof := _assert_actual_overlay_matches_original_static_order(
		commands,
		Vector2i(int(raw_size[0]), int(raw_size[1])),
		runtime_root,
		false
	)
	assert(str(overlay_order_proof.hash) == F1_OVERLAY_HASH)
	var after_payload := []
	for command: Dictionary in VisualGeometry.sorted_draw_commands(loaded.runtime.instances):
		after_payload.append([
			int(command.command_index),
			str(command.get("instance", {}).get("instance_id", "")),
			str(command.render_domain),
			int(command.image_pass),
			MapEditorInstanceService.material_layer_order(command.instance),
		])
	assert(after_payload == original_payload, "bridge mutated authored command ordering")
	var stats_before_frame := background.static_wall_bridge_stats()
	await get_tree().process_frame
	assert(
		background.static_wall_bridge_stats() == stats_before_frame,
		"bridge counters grew after the build frame"
	)
	print(
		(
			"STATIC_AUTHORED_WALL_BRIDGE_F1_STATS candidates=%d scanned=%d "
			+ "overlays=%d pixels=%d compared=%d multi_decor_pixels=%d hash=%s "
			+ "record_usec=%d raster_usec=%d upload_usec=%d build_usec=%d "
			+ "wall_alpha_samples=%d stack_hits=%d stack_misses=%d "
			+ "duplicate_stacks=%d hydrated_textures=%d hydrated_bytes=%d"
		)
		% [
			int(stats.candidate_pairs), int(stats.scanned_pixels),
			int(stats.overlay_count), overlay_pixels.size(),
			int(overlay_order_proof.compared_pixels),
			int(overlay_order_proof.multi_decor_pixels),
			str(overlay_order_proof.hash),
			int(stats.record_usec), int(stats.raster_usec),
			int(stats.upload_usec), int(stats.build_usec),
			int(stats.wall_alpha_samples), int(stats.wall_stack_cache_hits),
			int(stats.wall_stack_cache_misses),
			int(stats.wall_stack_duplicate_builds),
			int(stats.hydrated_textures), int(stats.hydrated_bytes),
		]
	)
	runtime_root.queue_free()


func _assert_bridge_build_metrics(stats: Dictionary) -> void:
	assert(int(stats.record_usec) >= 0)
	assert(int(stats.raster_usec) >= 0)
	assert(int(stats.upload_usec) >= 0)
	assert(int(stats.build_usec) <= MAX_BRIDGE_BUILD_USEC)
	assert(int(stats.wall_alpha_samples) > 0)
	assert(int(stats.wall_stack_cache_misses) > 0)
	assert(int(stats.wall_stack_cache_hits) >= 0)
	assert(int(stats.wall_stack_duplicate_builds) == 0)
	assert(int(stats.hydrated_textures) > 0)
	assert(int(stats.hydrated_bytes) > 0)


func _assert_actual_overlay_matches_original_static_order(
	commands: Array[Dictionary],
	design_size: Vector2i,
	runtime_root: Node,
	require_multi_decor_pixel: bool
) -> Dictionary:
	var image_cache := {}
	var wall_records: Array[Dictionary] = []
	var static_records: Array[Dictionary] = []
	var base_by_group := {}
	for command: Dictionary in commands:
		if (
			not VisualGeometry.is_atomic_wall_pass(command)
			and not VisualGeometry.is_static_authored_wall_bridge_candidate(command)
		):
			continue
		var record := _decor_pixel_record(command, design_size, image_cache)
		assert(not record.is_empty())
		record.command_index = int(command.command_index)
		record.group_key = str(command.get("actor_sort_group", ""))
		record.image_pass = int(command.get("image_pass", -1))
		if VisualGeometry.is_atomic_wall_pass(command):
			wall_records.append(record)
			if int(command.get("image_pass", -1)) == 1:
				base_by_group[record.group_key] = record
		else:
			static_records.append(record)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var compared_pixels := 0
	var multi_decor_pixels := 0
	var compared_overlays := 0
	var quantizer := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	for wrapper: Node in runtime_root.get_children():
		var wrapper_group := str(wrapper.get_meta("editor_runtime_actor_sort_group", ""))
		if wrapper_group.is_empty():
			continue
		for child: Node in wrapper.get_children():
			if not bool(child.get_meta("static_authored_wall_bridge", false)):
				continue
			compared_overlays += 1
			var rect: Rect2i = child.get_meta("static_wall_bridge_world_rect")
			var actual_image := (child as Sprite2D).texture.get_image()
			for local_y in actual_image.get_height():
				for local_x in actual_image.get_width():
					var world_pixel := rect.position + Vector2i(local_x, local_y)
					var ordered_colors: Array[Color] = []
					var ordered_source_ids := []
					var owner := _expected_wall_owner(world_pixel, wall_records)
					if (
						not owner.is_empty()
						and str(owner.group_key) == wrapper_group
						and base_by_group.has(wrapper_group)
					):
						var owner_base: Dictionary = base_by_group[wrapper_group]
						for static_record: Dictionary in static_records:
							var source := _sample_decor_pixel(static_record, world_pixel)
							if source.a <= 0.0:
								continue
							var top_base := _expected_top_base_for_static(
								world_pixel, static_record.command,
								design_size, wall_records
							)
							if (
								top_base.is_empty()
								or not VisualGeometry.static_authored_command_is_in_front_of_wall(
									static_record.command, owner_base.command, design_size
								)
							):
								continue
							ordered_colors.append(source)
							ordered_source_ids.append(str(
								static_record.command.get("instance", {}).get("instance_id", "")
							))
					var expected := VisualGeometry.static_wall_bridge_compose_ordered_colors(
						ordered_colors
					)
					quantizer.set_pixel(0, 0, expected)
					expected = quantizer.get_pixel(0, 0)
					var actual := actual_image.get_pixel(local_x, local_y)
					assert(
						expected.to_rgba32() == actual.to_rgba32(),
						(
							"actual overlay differs at %s group=%s expected=%08x "
							+ "actual=%08x sources=%s owner=%s"
						)
						% [
							world_pixel, wrapper_group, expected.to_rgba32(),
							actual.to_rgba32(), ordered_source_ids,
							str(owner.get("group_key", "")),
						]
					)
					compared_pixels += 1
					if ordered_colors.size() >= 2 and actual.a > 0.0:
						multi_decor_pixels += 1
					context.update(
						("%d,%d:%08x;" % [world_pixel.x, world_pixel.y, actual.to_rgba32()]).to_utf8_buffer()
					)
	assert(compared_overlays > 0 and compared_pixels > 0)
	if require_multi_decor_pixel:
		assert(
			multi_decor_pixels > 0,
			"multi-decoration fixture lacks an overlapping wall overlay pixel"
		)
	return {
		"compared_overlays": compared_overlays,
		"compared_pixels": compared_pixels,
		"multi_decor_pixels": multi_decor_pixels,
		"hash": context.finish().hex_encode(),
	}


func _expected_wall_owner(
	world_pixel: Vector2i,
	wall_records: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in wall_records:
		var aabb: Rect2i = record.aabb
		if not aabb.has_point(world_pixel):
			continue
		if _sample_decor_pixel(record, world_pixel).a <= 0.0:
			continue
		if result.is_empty() or int(record.command_index) > int(result.command_index):
			result = record
	return result


func _expected_top_base_for_static(
	world_pixel: Vector2i,
	static_command: Dictionary,
	design_size: Vector2i,
	wall_records: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in wall_records:
		if (
			int(record.image_pass) != 1
			or not VisualGeometry.static_authored_command_is_in_front_of_wall(
				static_command, record.command, design_size
			)
		):
			continue
		var aabb: Rect2i = record.aabb
		if not aabb.has_point(world_pixel):
			continue
		if _sample_decor_pixel(record, world_pixel).a <= 0.0:
			continue
		if result.is_empty() or int(record.command_index) > int(result.command_index):
			result = record
	return result


func _original_static_command_indices(root: Node) -> Dictionary:
	var result := {}
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		if (
			bool(node.get_meta("editor_runtime_instance", false))
			and str(node.get_meta("editor_runtime_render_domain", ""))
				== VisualGeometry.RENDER_DOMAIN_STATIC_BACKGROUND
		):
			result[int(node.get_meta("editor_runtime_command_index", -1))] = true
	return result


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
