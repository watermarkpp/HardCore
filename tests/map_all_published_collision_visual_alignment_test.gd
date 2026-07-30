extends Node2D

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const WorldBackgroundScript := preload("res://scripts/world_background.gd")

const PUBLISHED_RUNTIME_MAPS := {
	4: "bich_province",
	217: "orc_tomb_1",
	218: "orc_tomb_2",
	221: "orc_tomb_3",
	268: "wooma_forest",
	313: "wooma_temple_1",
	314: "wooma_temple_2",
	315: "wooma_temple_3",
	406: "bich_mine_1",
	408: "bich_mine_2",
	1578: "corpse_king_hall",
}


func _ready() -> void:
	var total_blocked := 0
	var total_manual := 0
	var total_erased := 0
	var covered_maps := 0
	for runtime_map_id: int in PUBLISHED_RUNTIME_MAPS:
		var map_key := str(PUBLISHED_RUNTIME_MAPS[runtime_map_id])
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
			var visual_center := MapEditorCoordinate.cell_center_to_world(
				Vector2(cell), design_size
			)
			assert(
				polygon_center.is_equal_approx(visual_center),
				"%s collision cell shifted from visible cell %s" % [map_key, cell]
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
			# Cell centers remain inside the logical 0..size visible diamond.
			# The packaged canvas adds transparent half-cell padding and must not
			# redefine whether an authored cell is walkable.
			if CollisionGeometry.visible_ground_contains_tile(
				MapEditorCoordinate.world_to_tile(erased_world, design_size),
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
	assert(covered_maps == PUBLISHED_RUNTIME_MAPS.size())
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
	var raw_center: Array = visual.get("ground_pixel_center", [])
	assert(raw_center.size() == 2, "%s ground center missing" % map_key)
	var ground_center := Vector2(float(raw_center[0]), float(raw_center[1]))
	var raw_pixel_size: Array = visual.get("ground_pixel_size", [])
	assert(raw_pixel_size.size() == 2, "%s ground size missing" % map_key)
	var ground_pixel_size := Vector2(
		float(raw_pixel_size[0]), float(raw_pixel_size[1])
	)
	var expected_center := Vector2(
		MapEditorCoordinate.ground_image_size(design_size)
	) * 0.5
	assert(
		ground_center.is_equal_approx(expected_center),
		"%s visual origin shifted: %s != %s"
			% [map_key, ground_center, expected_center]
	)
	for cell: Vector2i in [Vector2i.ZERO, design_size - Vector2i.ONE]:
		var ground_cell_center := (
			MapEditorCoordinate.cell_center_to_ground_px(cell, design_size)
			- ground_center
		)
		var world_cell_center := MapEditorCoordinate.cell_center_to_world(
			cell, design_size
		)
		assert(
			ground_cell_center.is_equal_approx(world_cell_center),
			"%s ground/world origin mismatch at %s" % [map_key, cell]
		)
	var visible_top_world := Vector2(ground_center.x, 0.0) - ground_center
	var visible_bottom_world := (
		Vector2(ground_center.x, ground_pixel_size.y) - ground_center
	)
	assert(
		visible_top_world.is_equal_approx(MapEditorCoordinate.tile_to_world(
			Vector2(-0.5, -0.5), design_size
		)),
		"%s transparent canvas top padding mismatch" % map_key
	)
	assert(
		visible_bottom_world.is_equal_approx(MapEditorCoordinate.tile_to_world(
			Vector2(design_size) - Vector2(0.5, 0.5), design_size
		)),
		"%s transparent canvas bottom padding mismatch" % map_key
	)
	var background := WorldBackgroundScript.new()
	var runtime_fill := background.editor_runtime_ground_boundary_world(
		design_size
	)
	assert(
		runtime_fill == CollisionGeometry.map_inner_boundary_world(design_size),
		"%s runtime base fill/guard diverged from chunk and collision edge"
			% map_key
	)
	var logical_top := MapEditorCoordinate.tile_to_world(
		Vector2.ZERO, design_size
	)
	assert(
		logical_top.is_equal_approx(runtime_fill[0]),
		"%s physical boundary does not use the visible logical diamond tip"
			% map_key
	)
	assert(
		is_equal_approx(logical_top.y - visible_top_world.y, 16.0),
		"%s canvas padding was incorrectly promoted to walkable ground" % map_key
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
	var top_vertex := MapEditorCoordinate.tile_to_world(
		Vector2.ZERO, design_size
	)
	var empty_collision := {"blocked_tiles": []}
	var visual_edge := MapEditorCoordinate.tile_to_world(
		Vector2(float(design_size.x) * 0.5, 0.0),
		design_size
	)
	var edge_direction := (
		MapEditorCoordinate.tile_to_world(
			Vector2(float(design_size.x), 0.0), design_size
		) - top_vertex
	)
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
	for index in expected.size():
		assert(
			world_boundary[index].is_equal_approx(
				MapEditorCoordinate.tile_to_world(expected[index], design_size)
			),
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
		document, walkability
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
		"res://assets/data/runtime/map_editor/bich_province.runtime.json"
	)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var runtime: Dictionary = loaded.runtime
	var raw_size: Array = runtime.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var background := WorldBackgroundScript.new()
	background.zone_data = {"mapId": 4}
	add_child(background)
	await get_tree().physics_frame
	await get_tree().process_frame
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
	var visual_edge := MapEditorCoordinate.tile_to_world(
		Vector2(float(design_size.x) * 0.5, 0.0),
		design_size
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
