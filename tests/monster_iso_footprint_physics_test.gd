extends Node2D

const TILE_HALF_WIDTH := 32.0
const TILE_HALF_HEIGHT := 16.0


class DiamondBlocker:
	extends Node

	var polygon: PackedVector2Array

	func _init(points: PackedVector2Array) -> void:
		polygon = points

	func is_environment_point_blocked(point: Vector2) -> bool:
		return Geometry2D.is_point_in_polygon(point, polygon)


func _ready() -> void:
	var diamond_points := PackedVector2Array([
		Vector2(0.0, -TILE_HALF_HEIGHT),
		Vector2(TILE_HALF_WIDTH, 0.0),
		Vector2(0.0, TILE_HALF_HEIGHT),
		Vector2(-TILE_HALF_WIDTH, 0.0),
	])
	var body := StaticBody2D.new()
	body.name = "Real64x32DiamondObstacle"
	body.collision_layer = WorldSpatialRules.WORLD_LAYER
	body.collision_mask = 0
	var body_collision := CollisionShape2D.new()
	var diamond_shape := ConvexPolygonShape2D.new()
	diamond_shape.points = diamond_points
	body_collision.shape = diamond_shape
	body.add_child(body_collision)
	add_child(body)

	var blocker := DiamondBlocker.new(diamond_points)
	add_child(blocker)

	var enemy := EnemyActor.new()
	enemy.name = "IsometricFootprintProbe"
	enemy.position = Vector2(1024.0, 1024.0)
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame

	var footprint: Shape2D = enemy.get_node("CollisionShape2D").shape
	assert(footprint is ConvexPolygonShape2D, "runtime monster did not build the shared isometric footprint")
	var bounds := _bounds((footprint as ConvexPolygonShape2D).points)
	assert(is_equal_approx(bounds.size.x, enemy.collision_radius * 2.0), "monster footprint lost its authored horizontal radius")
	assert(is_equal_approx(bounds.size.y, enemy.collision_radius), "monster footprint is not 2:1 in world space")

	var edge_normal := Vector2(1.0, 2.0).normalized()
	var diamond_edge_support := diamond_points[1].dot(edge_normal)
	var physics_edge_support := _support((footprint as ConvexPolygonShape2D).points, edge_normal)
	var software_edge_support := _support(
		WorldSpatialRules.actor_footprint_polygon(enemy.collision_radius - 1.0),
		edge_normal
	)
	var probes := {
		"center": Vector2.ZERO,
		"horizontal_overlap": Vector2(TILE_HALF_WIDTH + enemy.collision_radius - 2.0, 0.0),
		"vertical_overlap": Vector2(0.0, TILE_HALF_HEIGHT + enemy.collision_radius * 0.5 - 2.0),
		"diagonal_overlap": edge_normal * (diamond_edge_support + software_edge_support - 2.0),
		"horizontal_clear": Vector2(TILE_HALF_WIDTH + enemy.collision_radius + 2.0, 0.0),
		"vertical_clear": Vector2(0.0, TILE_HALF_HEIGHT + enemy.collision_radius * 0.5 + 2.0),
		"diagonal_clear": edge_normal * (diamond_edge_support + physics_edge_support + 2.0),
	}
	var expected := {
		"center": true,
		"horizontal_overlap": true,
		"vertical_overlap": true,
		"diagonal_overlap": true,
		"horizontal_clear": false,
		"vertical_clear": false,
		"diagonal_clear": false,
	}
	for probe_name: String in probes:
		var position: Vector2 = probes[probe_name]
		var physics_blocked := _physics_blocks(footprint, position)
		var software_blocked := WorldSpatialRules.environment_blocks_actor(
			blocker,
			position,
			enemy.collision_radius
		)
		assert(physics_blocked == expected[probe_name], "Physics2D mismatch at %s: %s" % [probe_name, physics_blocked])
		assert(software_blocked == expected[probe_name], "software mismatch at %s: %s" % [probe_name, software_blocked])
		assert(physics_blocked == software_blocked, "Physics2D/software disagree at %s" % probe_name)

	assert(WorldSpatialRules.ACTOR_FOOTPRINT_CONTRACT_ID == "world.actor_footprint.iso_ellipse.v1")
	print("MONSTER_ISO_FOOTPRINT_PHYSICS_PASS real_tile=64x32 physics=software probes=%d" % probes.size())
	get_tree().quit(0)


func _physics_blocks(shape: Shape2D, position: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = WorldSpatialRules.WORLD_LAYER
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _bounds(points: PackedVector2Array) -> Rect2:
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _support(points: PackedVector2Array, normal: Vector2) -> float:
	var result := -INF
	for point: Vector2 in points:
		result = maxf(result, point.dot(normal))
	return result
