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
		+ "maps=%d feet_reach_visual_edge=true outside_ring=blocked"
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
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(Vector2(-0.5, -0.5), design_size)
	), "%s top canvas edge mismatch" % map_key)
	assert(canvas_bottom_world.is_equal_approx(
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			Vector2(design_size) - Vector2(0.5, 0.5), design_size
		)
	), "%s bottom canvas edge mismatch" % map_key)


func _assert_physics_edge(
	runtime_map_id: int,
	design_size: Vector2i
) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var inner := CollisionGeometry.map_actor_boundary_world(design_size)
	var outer := CollisionGeometry.map_outer_boundary_world(design_size)
	for side in inner.size():
		var next := (side + 1) % inner.size()
		var shape := ConvexPolygonShape2D.new()
		shape.points = PackedVector2Array([
			outer[side], outer[next], inner[next], inner[side],
		])
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
	add_child(body)
	await get_tree().physics_frame
	var tile_x := float(design_size.x) * 0.5 - 0.5
	var visual_edge := MapEditorCoordinate.ground_position_gu_to_screen_position_px(
		Vector2(tile_x, -0.5), design_size
	)
	var visual_polygon := CollisionGeometry.map_inner_boundary_world(design_size)
	var edge_direction := visual_polygon[1] - visual_polygon[0]
	var outward := Vector2(edge_direction.y, -edge_direction.x).normalized()
	var clearance := CollisionGeometry.DEFAULT_ACTOR_BOUNDARY_CLEARANCE_PX
	var footprint := WorldSpatialRules.actor_footprint_polygon_px(clearance)
	var just_inside := visual_edge - outward * 0.5
	var just_outside := visual_edge + outward * 0.5
	var empty_collision := {"blocked_tiles": []}
	assert(not CollisionGeometry.runtime_collision_contains_world(
		empty_collision, visual_edge, design_size
	), "map %d software blocks rendered feet at ground edge" % runtime_map_id)
	assert(CollisionGeometry.runtime_collision_contains_world(
		empty_collision, just_outside, design_size
	), "map %d software accepted black area outside rendered ground" % runtime_map_id)
	assert(_physics_hits(just_inside).is_empty(),
		"map %d Physics2D starts inside rendered ground" % runtime_map_id)
	assert(not _physics_hits(just_outside).is_empty(),
		"map %d Physics2D accepted black area outside rendered ground" % runtime_map_id)

	var actor := CharacterBody2D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	var actor_shape := CollisionShape2D.new()
	actor_shape.shape = WorldSpatialRules.actor_footprint_shape_px(clearance)
	actor.add_child(actor_shape)
	add_child(actor)
	actor.global_position = visual_edge - outward * (clearance + 4.0)
	await get_tree().physics_frame
	var collision := actor.move_and_collide(outward * (clearance * 3.0))
	assert(collision != null, "map %d actor escaped hard boundary" % runtime_map_id)
	var projected := (
		CollisionGeometry.project_world_envelope_inside_visible_boundary(
			visual_edge, design_size, footprint
		)
	)
	assert(
		actor.global_position.distance_to(projected) <= 1.5,
		"map %d physics/projection coordinate drift: physics=%s projected=%s"
			% [runtime_map_id, actor.global_position, projected]
	)
	assert(
		CollisionGeometry.world_envelope_inside_visible_boundary(
			actor.global_position, design_size, footprint
		),
		"map %d actor feet overlap black area" % runtime_map_id
	)
	actor.queue_free()
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
