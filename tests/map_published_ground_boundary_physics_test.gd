extends Node2D

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

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
	_run.call_deferred()


func _run() -> void:
	var checked := 0
	for runtime_map_id: int in PUBLISHED_RUNTIME_MAPS:
		var map_key := str(PUBLISHED_RUNTIME_MAPS[runtime_map_id])
		var loaded := MapEditorRuntimeMapService.load_runtime(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		assert(loaded.ok, "%s:%s" % [map_key, loaded.get("errors", [])])
		var runtime: Dictionary = loaded.runtime
		var raw_size: Array = runtime.design.design_size
		var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var visual := _read_json(
			"res://assets/data/runtime/map_editor/%s.visual.json" % map_key
		)
		_assert_canvas_edge(map_key, visual, design_size)
		await _assert_physics_edge(runtime_map_id, design_size)
		checked += 1
	assert(checked == PUBLISHED_RUNTIME_MAPS.size())
	print(
		"MAP_PUBLISHED_GROUND_BOUNDARY_PHYSICS_PASS "
		+ "maps=%d visible_interior=free first_black_outside=blocked"
		% checked
	)
	get_tree().quit(0)


func _assert_canvas_edge(
	map_key: String,
	visual: Dictionary,
	design_size: Vector2i
) -> void:
	var raw_center: Array = visual.get("ground_pixel_center", [])
	var raw_pixel_size: Array = visual.get("ground_pixel_size", [])
	assert(raw_center.size() == 2, "%s ground center missing" % map_key)
	assert(raw_pixel_size.size() == 2, "%s ground size missing" % map_key)
	var center := Vector2(float(raw_center[0]), float(raw_center[1]))
	var pixel_size := Vector2(
		float(raw_pixel_size[0]), float(raw_pixel_size[1])
	)
	var canvas_top_world := Vector2(center.x, 0.0) - center
	var canvas_bottom_world := Vector2(center.x, pixel_size.y) - center
	assert(canvas_top_world.is_equal_approx(
		MapEditorCoordinate.tile_to_world(Vector2(-0.5, -0.5), design_size)
	), "%s top canvas edge mismatch" % map_key)
	assert(canvas_bottom_world.is_equal_approx(
		MapEditorCoordinate.tile_to_world(
			Vector2(design_size) - Vector2(0.5, 0.5), design_size
		)
	), "%s bottom canvas edge mismatch" % map_key)


func _assert_physics_edge(
	runtime_map_id: int,
	design_size: Vector2i
) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var inner := CollisionGeometry.map_inner_boundary_tile_polygon(design_size)
	var outer := CollisionGeometry.map_outer_boundary_tile_polygon(design_size)
	for side in 4:
		var next := (side + 1) % 4
		var shape := ConvexPolygonShape2D.new()
		shape.points = CollisionGeometry.tile_polygon_world(
			PackedVector2Array([
				outer[side], outer[next], inner[next], inner[side],
			]),
			design_size
		)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
	add_child(body)
	await get_tree().physics_frame
	var tile_x := float(design_size.x) * 0.5 - 0.5
	var visible_interior := MapEditorCoordinate.tile_to_world(
		Vector2(tile_x, -0.25), design_size
	)
	var first_outside := MapEditorCoordinate.tile_to_world(
		Vector2(tile_x, -0.75), design_size
	)
	var empty_collision := {"blocked_tiles": []}
	assert(not CollisionGeometry.runtime_collision_contains_world(
		empty_collision, visible_interior, design_size
	), "map %d software blocked visible interior" % runtime_map_id)
	assert(CollisionGeometry.runtime_collision_contains_world(
		empty_collision, first_outside, design_size
	), "map %d software accepted black outside" % runtime_map_id)
	assert(_physics_hits(visible_interior).is_empty(),
		"map %d Physics2D blocked visible interior" % runtime_map_id)
	assert(not _physics_hits(first_outside).is_empty(),
		"map %d Physics2D accepted black outside" % runtime_map_id)
	body.queue_free()
	await get_tree().process_frame


func _physics_hits(world_position: Vector2) -> Array[Dictionary]:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_point(query, 8)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "%s missing" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Dictionary, "%s invalid" % path)
	return parsed
