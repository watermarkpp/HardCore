extends Node2D

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const WorldBackgroundScript := preload("res://scripts/world_background.gd")

const IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const RELEASE_REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const VISUAL_CONTRACT_ID := "mse.map.runtime.visual.v1"
const FORMAL_GROUND_CHUNK_ROOT := "assets/data/runtime/map_editor/formal_ground_chunks/sha256/"
const HALF_TILE_WIDTH_PX := 32.0
const HALF_TILE_HEIGHT_PX := 16.0


func _ready() -> void:
	var published_runtime_maps := _published_runtime_maps()
	var total_blocked := 0
	var total_manual := 0
	var total_erased := 0
	var covered_maps := 0
	for runtime_map_id: int in published_runtime_maps:
		var map_key := str(published_runtime_maps[runtime_map_id])
		var loaded := MapEditorRuntimeMapService.load_runtime(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		assert(loaded.ok, "%s:%s" % [map_key, loaded.get("errors", [])])
		var runtime: Dictionary = loaded.runtime
		var raw_size: Array = runtime.design.design_size
		var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var runtime_collision: Dictionary = runtime.collision
		assert(
			str(runtime_collision.get("coordinate_contract_id", ""))
			== CollisionGeometry.CONTRACT_ID,
			"%s collision contract missing" % map_key
		)
		assert(
			str(runtime_collision.get("physics_source_id", ""))
			== CollisionGeometry.PHYSICS_SOURCE_ID,
			"%s physics source contract missing" % map_key
		)
		_assert_ground_origin(runtime_map_id, map_key, design_size)
		_assert_boundary_contract(runtime_map_id, design_size)
		_assert_runtime_walkability_snapshot(map_key, runtime)
		var blocked: Array = runtime_collision.blocked_tiles
		var blocked_set := CollisionGeometry.blocked_cell_set(
			runtime_collision
		)
		_assert_blocked_runs(map_key, runtime_collision, blocked_set)
		for raw_key: Variant in blocked:
			var cell := _parse_cell(str(raw_key))
			assert(cell.x >= 0, "%s invalid blocked key %s" % [map_key, raw_key])
			var polygon := CollisionGeometry.cell_polygon_world(cell, design_size)
			var polygon_center := _polygon_center(polygon)
			var visual_center := MapEditorCoordinate.grid_cell_to_screen_position_px(
				Vector2(cell), design_size
			)
			var expected_center := _expected_world_for_tile(
				Vector2(cell) + Vector2(0.5, 0.5), design_size
			)
			assert(
				polygon_center.is_equal_approx(expected_center),
				"%s collision cell shifted from visible cell %s" % [map_key, cell]
			)
			assert(
				visual_center.is_equal_approx(expected_center),
				"%s visible cell center shifted %s" % [map_key, cell]
			)
			assert(
				CollisionGeometry.world_cell(visual_center, design_size) == cell,
				"%s cell center round-trip failed %s" % [map_key, cell]
			)
		for manual: Dictionary in runtime_collision.manual_shapes:
			var polygon := CollisionGeometry.manual_shape_polygon_world(
				manual, design_size
			)
			assert(
				polygon.size() >= 3,
				"%s manual collision missing runtime geometry: %s"
					% [map_key, manual.get("collision_id", "")]
			)
		total_blocked += blocked.size()
		for erased: Dictionary in runtime_collision.erased_cells:
			var raw_cell: Array = erased.get("tile", [])
			if raw_cell.size() != 2:
				continue
			var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
			if (
				cell.x < 0 or cell.y < 0
				or cell.x >= design_size.x or cell.y >= design_size.y
			):
				continue
			var key := "%d,%d" % [cell.x, cell.y]
			assert(not blocked_set.has(key), "%s erased cell restored %s" % [map_key, key])
			var erased_world := CollisionGeometry.cell_center_world(
				cell, design_size
			)
			# An erased authored cell remains outside the blocked-cell set. If its
			# center is within the v2 ground canvas, the erase must remain effective.
			if CollisionGeometry.visible_ground_contains_tile(
				MapEditorCoordinate.screen_position_px_to_ground_position_gu(erased_world, design_size),
				design_size
			):
				assert(
					not CollisionGeometry.blocked_cells_contain_world(
						blocked_set, erased_world, design_size
					),
					"%s software collision restored erased cell %s"
						% [map_key, key]
				)
		total_manual += (runtime_collision.manual_shapes as Array).size()
		total_erased += (runtime_collision.erased_cells as Array).size()
		covered_maps += 1
	assert(covered_maps == published_runtime_maps.size())
	assert(total_blocked > 0)
	assert(total_erased > 0)
	_assert_manual_provenance_is_not_a_second_physics_source()
	_assert_future_build_contract()
	await _assert_bich_runtime_physics()
	print(
		"MAP_ALL_PUBLISHED_COLLISION_VISUAL_ALIGNMENT_PASS "
		+ "contract=%s source=%s maps=%d blocked=%d manual=%d erased=%d"
		% [
			CollisionGeometry.CONTRACT_ID,
			CollisionGeometry.PHYSICS_SOURCE_ID,
			covered_maps,
			total_blocked,
			total_manual,
			total_erased,
		]
	)
	get_tree().quit(0)


func _assert_ground_origin(
	runtime_map_id: int,
	map_key: String,
	design_size: Vector2i
) -> void:
	var visual_path := (
		"res://assets/data/runtime/map_editor/%s.visual.json" % map_key
	)
	assert(FileAccess.file_exists(visual_path), "%s visual missing" % map_key)
	var file := FileAccess.open(visual_path, FileAccess.READ)
	assert(file != null, "%s visual unreadable" % map_key)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Dictionary, "%s visual invalid" % map_key)
	var visual: Dictionary = parsed
	assert(int(visual.get("runtime_map_id", -1)) == runtime_map_id, map_key)
	assert(str(visual.get("visual_contract_id", "")) == VISUAL_CONTRACT_ID, "%s visual contract missing" % map_key)
	assert(str(visual.get("source_authority", "")) == "user_authored_baked_ground", "%s visual authority missing" % map_key)
	assert(bool(visual.get("coverage", {}).get("complete", false)), "%s visual coverage incomplete" % map_key)
	var coverage: Dictionary = visual.get("coverage", {})
	var visual_chunks: Variant = visual.get("chunks", [])
	assert(visual_chunks is Array and not (visual_chunks as Array).is_empty(), "%s visual chunks missing" % map_key)
	assert(int(coverage.get("required_chunk_count", -1)) == (visual_chunks as Array).size(), "%s visual coverage count mismatch" % map_key)
	var chunk_store: Dictionary = visual.get("chunk_store", {})
	assert(str(chunk_store.get("contract_id", "")) == "mse.map.runtime.ground_chunk_store.sha256.v1", "%s visual chunk store contract missing" % map_key)
	assert(str(chunk_store.get("root", "")) == FORMAL_GROUND_CHUNK_ROOT.trim_suffix("/"), "%s visual chunk store root mismatch" % map_key)
	var seen_hashes := {}
	for chunk: Dictionary in visual_chunks:
		var image_path := str(chunk.get("image", ""))
		var chunk_sha := str(chunk.get("sha256", ""))
		assert(image_path.begins_with(FORMAL_GROUND_CHUNK_ROOT), "%s visual points outside formal chunk store" % map_key)
		assert(not image_path.contains("map_editor_workspace"), "%s visual leaks workspace path" % map_key)
		assert(chunk_sha.length() == 64, "%s visual chunk hash missing" % map_key)
		assert(FileAccess.file_exists("res://" + image_path), "%s formal visual chunk missing %s" % [map_key, image_path])
		assert(FileAccess.get_sha256("res://" + image_path) == chunk_sha, "%s formal visual chunk hash mismatch %s" % [map_key, image_path])
		seen_hashes[chunk_sha] = image_path
	assert(not seen_hashes.is_empty(), "%s visual chunk hash coverage missing" % map_key)
	var raw_center: Array = visual.get("ground_pixel_center", [])
	assert(raw_center.size() == 2, "%s ground center missing" % map_key)
	var ground_center := Vector2(float(raw_center[0]), float(raw_center[1]))
	var raw_pixel_size: Array = visual.get("ground_pixel_size", [])
	assert(raw_pixel_size.size() == 2, "%s ground size missing" % map_key)
	var ground_pixel_size := Vector2(
		float(raw_pixel_size[0]), float(raw_pixel_size[1])
	)
	var expected_center := _expected_ground_pixel_center(design_size)
	assert(
		ground_center.is_equal_approx(expected_center),
		"%s visual origin shifted: %s != %s"
			% [map_key, ground_center, expected_center]
	)
	assert(
		ground_pixel_size == Vector2(_expected_ground_pixel_size(design_size)),
		"%s ground canvas size mismatch: %s != %s"
			% [map_key, ground_pixel_size, _expected_ground_pixel_size(design_size)]
	)
	for cell: Vector2i in [Vector2i.ZERO, design_size - Vector2i.ONE]:
		var ground_cell_center := (
			MapEditorCoordinate.cell_center_to_ground_px(cell, design_size)
			- ground_center
		)
		var expected_cell_center := _expected_world_for_tile(
			Vector2(cell) + Vector2(0.5, 0.5), design_size
		)
		assert(
			ground_cell_center.is_equal_approx(expected_cell_center),
			"%s ground/world origin mismatch at %s" % [map_key, cell]
		)
		assert(
			MapEditorCoordinate.grid_cell_to_screen_position_px(
				cell, design_size
			).is_equal_approx(expected_cell_center),
			"%s runtime cell center mismatch at %s" % [map_key, cell]
		)
	# v2 packages the complete authored cell union. The canvas top and bottom
	# therefore use the logical vertices (0,0) and design_size.
	var visible_top_world := _expected_world_for_tile(Vector2.ZERO, design_size)
	var visible_bottom_world := _expected_world_for_tile(Vector2(design_size), design_size)
	assert(
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			Vector2.ZERO, design_size
		).is_equal_approx(visible_top_world),
		"%s visible canvas top does not match physical boundary" % map_key
	)
	assert(
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			Vector2(design_size), design_size
		).is_equal_approx(visible_bottom_world),
		"%s visible canvas bottom does not match physical boundary" % map_key
	)
	var background := WorldBackgroundScript.new()
	var runtime_fill := background.editor_runtime_ground_boundary_world(
		design_size
	)
	var expected_boundary_world := _expected_boundary_world(design_size)
	assert(
		runtime_fill == expected_boundary_world,
		"%s runtime base fill/guard diverged from fixed v2 boundary"
			% map_key
	)
	assert(
		visible_top_world.is_equal_approx(runtime_fill[0]),
		"%s runtime boundary top diverges from v2 ground canvas edge"
			% map_key
	)
	background.free()


func _assert_boundary_contract(
	runtime_map_id: int,
	design_size: Vector2i
) -> void:
	var tile_boundary := CollisionGeometry.map_inner_boundary_tile_polygon(
		design_size
	)
	var expected := PackedVector2Array([
		Vector2.ZERO,
		Vector2(float(design_size.x), 0.0),
		Vector2(design_size),
		Vector2(0.0, float(design_size.y)),
	])
	assert(tile_boundary == expected, "map %d visible edge mismatch" % runtime_map_id)
	var expected_world_boundary := _expected_boundary_world(design_size)
	var top_vertex := expected_world_boundary[0]
	assert(
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			Vector2.ZERO, design_size
		).is_equal_approx(top_vertex),
		"map %d v2 boundary origin mismatch" % runtime_map_id
	)
	var empty_collision := {"blocked_tiles": []}
	var visual_edge := _expected_world_for_tile(
		Vector2(float(design_size.x) * 0.5, 0.0), design_size
	)
	var edge_direction := expected_world_boundary[1] - expected_world_boundary[0]
	var outward := Vector2(edge_direction.y, -edge_direction.x).normalized()
	var just_outside := visual_edge + outward * 0.5
	assert(
		not CollisionGeometry.runtime_collision_contains_world(
			empty_collision, visual_edge, design_size
		),
		"map %d visible ground edge blocked" % runtime_map_id
	)
	assert(
		CollisionGeometry.runtime_collision_contains_world(
			empty_collision, just_outside, design_size
		),
		"map %d black area immediately outside visual edge not blocked"
			% runtime_map_id
	)
	var world_boundary := CollisionGeometry.map_inner_boundary_world(design_size)
	for index in expected_world_boundary.size():
		assert(
			world_boundary[index].is_equal_approx(expected_world_boundary[index]),
			"map %d boundary world mismatch at %d" % [runtime_map_id, index]
		)


func _assert_runtime_walkability_snapshot(
	map_key: String,
	runtime: Dictionary
) -> void:
	var layers := {
		"terrain_base": [],
		"terrain_front": [],
		"object_base": [],
		"object_front": [],
		"collision": runtime.collision.manual_shapes.duplicate(true),
		"collision_erase": runtime.collision.erased_cells.duplicate(true),
	}
	for instance: Dictionary in runtime.instances:
		var layer := str(instance.get("layer", "object_base"))
		if not layers.has(layer):
			layers[layer] = []
		(layers[layer] as Array).append(instance.duplicate(true))
	var document := {
		"design": runtime.design.duplicate(true),
		"layers": layers,
	}
	var rebuilt := MapEditorCollisionService.build_walkability(document)
	var published := {}
	for raw_key: Variant in runtime.collision.blocked_tiles:
		published[str(raw_key)] = true
	var rebuilt_tiles: Dictionary = rebuilt.blocked_tiles
	assert(
		rebuilt_tiles.size() == published.size(),
		"%s stale collision snapshot: rebuilt=%d published=%d"
			% [map_key, rebuilt_tiles.size(), published.size()]
	)
	for key: String in rebuilt_tiles:
		assert(published.has(key), "%s missing published blocked cell %s" % [map_key, key])


func _assert_blocked_runs(
	map_key: String,
	runtime_collision: Dictionary,
	blocked_set: Dictionary
) -> void:
	var cells_from_runs := {}
	for rect: Rect2i in CollisionGeometry.blocked_cell_runs(runtime_collision):
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var key := "%d,%d" % [x, y]
				assert(blocked_set.has(key), "%s run invented %s" % [map_key, key])
				cells_from_runs[key] = true
	assert(
		cells_from_runs.size() == blocked_set.size(),
		"%s blocked run coverage mismatch" % map_key
	)


func _assert_manual_provenance_is_not_a_second_physics_source() -> void:
	var synthetic := {
		"coordinate_contract_id": CollisionGeometry.CONTRACT_ID,
		"physics_source_id": CollisionGeometry.PHYSICS_SOURCE_ID,
		"blocked_tiles": [],
		"manual_shapes": [{
			"collision_id": "manual_provenance_only",
			"shape": "rect",
			"data": {"rect": [4, 5, 2, 2]},
		}],
		"erased_cells": [],
	}
	var design_size := Vector2i(16, 16)
	assert(
		not CollisionGeometry.runtime_collision_contains_world(
			synthetic,
			CollisionGeometry.cell_center_world(Vector2i(4, 5), design_size),
			design_size
		),
		"manual provenance must not restore erased/absent blocked cells"
	)


func _assert_future_build_contract() -> void:
	var document := MapEditorTypes.new_map(
		"collision_contract_probe", 990282, "Collision Contract Probe",
		Vector2i(8, 8)
	)
	document.editor_meta.workspace = (
		"user://collision_contract_probe_%s" % str(Time.get_ticks_usec())
	)
	var walkability := MapEditorCollisionService.build_walkability(document)
	var compiled := MapEditorBuildRuntimeService._compile(
		document, walkability, {}
	)
	assert(
		compiled.collision.coordinate_contract_id
		== CollisionGeometry.CONTRACT_ID
	)
	assert(
		compiled.collision.physics_source_id
		== CollisionGeometry.PHYSICS_SOURCE_ID
	)


func _assert_bich_runtime_physics() -> void:
	var loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/world_bich_province.runtime.json"
	)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var runtime: Dictionary = loaded.runtime
	var raw_size: Array = runtime.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var background := WorldBackgroundScript.new()
	add_child(background)
	background.set_zone_data("比奇省", {"mapId": 910001, "name": "比奇省"})
	await get_tree().physics_frame
	await get_tree().process_frame
	assert(
		background.editor_runtime_chunk_texture_count() == 13,
		"910001 must consume the 13 authored Bich visual chunks"
	)
	assert(
		not background.uses_editor_runtime_fallback_ground(),
		"910001 must not fall back to full_ground"
	)
	assert(
		str(background._editor_runtime_visual.get("map_id", ""))
		== "world_bich_province",
		"910001 visual identity must be world_bich_province"
	)
	var expected_shapes := (
		CollisionGeometry.blocked_cell_runs(runtime.collision).size() + 4
	)
	assert(
		background._source_collision_shape_count == expected_shapes,
		"Bich rebuilt manual provenance as duplicate physics: %d != %d"
			% [background._source_collision_shape_count, expected_shapes]
	)
	var blocked_cell := _parse_cell(str(runtime.collision.blocked_tiles[0]))
	var blocked_center := CollisionGeometry.cell_center_world(
		blocked_cell, design_size
	)
	assert(background._editor_runtime_blocks_world(blocked_center))
	assert(not _physics_hits(blocked_center).is_empty())
	var visual_edge := _expected_world_for_tile(
		Vector2(float(design_size.x) * 0.5, 0.0), design_size
	)
	var visual_boundary := CollisionGeometry.map_inner_boundary_world(design_size)
	var edge_direction := visual_boundary[1] - visual_boundary[0]
	var outward := Vector2(edge_direction.y, -edge_direction.x).normalized()
	var just_inside := visual_edge - outward * 0.5
	var just_outside := visual_edge + outward * 0.5
	assert(
		not background._editor_runtime_blocks_world(visual_edge),
		"Bich visible edge rejected by software collision"
	)
	assert(
		_physics_hits(just_inside).is_empty(),
		"Bich Physics2D boundary starts inside visible ground"
	)
	assert(
		background._editor_runtime_blocks_world(just_outside),
		"Bich black area immediately outside visual edge accepted by software collision"
	)
	assert(
		not _physics_hits(just_outside).is_empty(),
		"Bich black area immediately outside visual edge accepted by Physics2D"
	)
	var erased_checked := 0
	var blocked_set := CollisionGeometry.blocked_cell_set(runtime.collision)
	for erased: Dictionary in runtime.collision.erased_cells:
		var raw_cell: Array = erased.get("tile", [])
		if raw_cell.size() != 2:
			continue
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var key := "%d,%d" % [cell.x, cell.y]
		if blocked_set.has(key):
			continue
		var center := CollisionGeometry.cell_center_world(cell, design_size)
		assert(
			not background._editor_runtime_blocks_world(center),
			"Bich software collision restored erased cell %s" % key
		)
		assert(
			_physics_hits(center).is_empty(),
			"Bich Physics2D restored erased cell %s" % key
		)
		erased_checked += 1
		if erased_checked >= 12:
			break
	assert(erased_checked == 12, "Bich erased collision coverage missing")
	background.queue_free()
	await get_tree().process_frame


func _expected_ground_pixel_size(design_size: Vector2i) -> Vector2i:
	return Vector2i(
		(design_size.x + design_size.y) * int(HALF_TILE_WIDTH_PX),
		(design_size.x + design_size.y) * int(HALF_TILE_HEIGHT_PX),
	)


func _expected_ground_pixel_center(design_size: Vector2i) -> Vector2:
	return Vector2(
		float(design_size.x + design_size.y) * HALF_TILE_WIDTH_PX * 0.5,
		float(design_size.x + design_size.y - 2) * HALF_TILE_HEIGHT_PX * 0.5,
	)


func _expected_world_for_tile(tile: Vector2, design_size: Vector2i) -> Vector2:
	var center_gu := (Vector2(design_size) - Vector2.ONE) * 0.5
	var relative := tile - center_gu
	return Vector2(
		(relative.x - relative.y) * HALF_TILE_WIDTH_PX,
		(relative.x + relative.y) * HALF_TILE_HEIGHT_PX,
	)


func _expected_boundary_world(design_size: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		_expected_world_for_tile(Vector2.ZERO, design_size),
		_expected_world_for_tile(Vector2(design_size.x, 0.0), design_size),
		_expected_world_for_tile(Vector2(design_size), design_size),
		_expected_world_for_tile(Vector2(0.0, design_size.y), design_size),
	])


func _published_runtime_maps() -> Dictionary:
	var identity_file := FileAccess.open(IDENTITY_PATH, FileAccess.READ)
	assert(identity_file != null, "formal identity registry missing")
	var identity: Variant = JSON.parse_string(identity_file.get_as_text())
	identity_file.close()
	assert(identity is Dictionary, "formal identity registry invalid")
	var registry_file := FileAccess.open(RELEASE_REGISTRY_PATH, FileAccess.READ)
	assert(registry_file != null, "formal release registry missing")
	var registry: Variant = JSON.parse_string(registry_file.get_as_text())
	registry_file.close()
	assert(registry is Dictionary, "formal release registry invalid")
	var identity_ids := {}
	for entry: Dictionary in (identity as Dictionary).get("maps", []):
		identity_ids[int(entry.get("runtime_map_id", -1))] = str(entry.get("map_id", ""))
	var result := {}
	for entry: Dictionary in (registry as Dictionary).get("maps", []):
		var runtime_map_id := int(entry.get("runtime_map_id", -1))
		var map_key := str(entry.get("map_key", ""))
		assert(identity_ids.get(runtime_map_id, "") == map_key, "release registry identity mismatch %d" % runtime_map_id)
		result[runtime_map_id] = map_key
	assert(result.size() == 67, "formal release coverage must include all 67 maps")
	return result


func _physics_hits(world_position: Vector2) -> Array[Dictionary]:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_point(query, 16)


func _parse_cell(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point
	return center / float(polygon.size())
