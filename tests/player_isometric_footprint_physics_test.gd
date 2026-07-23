extends Node

const DIRECTIONS := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]


class DiamondEnvironmentProvider:
	extends Node2D
	var blocked_polygon := PackedVector2Array()

	func _init(source_polygon: PackedVector2Array) -> void:
		blocked_polygon = source_polygon
		var body := StaticBody2D.new()
		body.collision_layer = WorldSpatialRules.WORLD_LAYER
		body.collision_mask = 0
		var collision := CollisionPolygon2D.new()
		collision.polygon = blocked_polygon
		body.add_child(collision)
		add_child(body)

	func is_environment_point_blocked(point: Vector2) -> bool:
		return Geometry2D.is_point_in_polygon(to_local(point), blocked_polygon)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var provider := DiamondEnvironmentProvider.new(_diamond())
	add_child(provider)
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().physics_frame

	var shape: Shape2D = player.get_node("CollisionShape2D").shape
	assert(shape is ConvexPolygonShape2D, "player must use the shared isometric footprint shape")
	assert((shape as ConvexPolygonShape2D).points == WorldSpatialRules.actor_footprint_polygon(ArtSpec.PLAYER_COLLISION_RADIUS))

	for outward: Vector2 in DIRECTIONS:
		var expected_support := 32.0 + ArtSpec.PLAYER_COLLISION_RADIUS if not is_zero_approx(outward.x) else 16.0 + ArtSpec.PLAYER_COLLISION_RADIUS * WorldSpatialRules.ACTOR_FOOTPRINT_Y_RATIO
		player.global_position = outward * 100.0
		await get_tree().physics_frame
		var collision := player.move_and_collide(-outward * 200.0)
		assert(collision != null, "Physics2D missed 64x32 diamond contact from %s" % outward)
		var contact_distance := player.global_position.dot(outward)
		assert(absf(contact_distance - expected_support) <= 1.5, "unexpected player contact from %s: %s / %s" % [outward, contact_distance, expected_support])

		var clear_position := player.global_position + outward * 3.0
		var penetrating_position := player.global_position - outward * 3.0
		assert(not WorldSpatialRules.environment_blocks_actor(provider, clear_position, ArtSpec.PLAYER_COLLISION_RADIUS), "software footprint blocks clear %s contact" % outward)
		assert(WorldSpatialRules.environment_blocks_actor(provider, penetrating_position, ArtSpec.PLAYER_COLLISION_RADIUS), "software footprint missed Physics2D penetration from %s" % outward)

		player.global_position = clear_position
		await get_tree().physics_frame
		assert(player.move_and_collide(-outward * 6.0) != null, "Physics2D accepted software-blocked %s penetration" % outward)

	print("PLAYER_ISOMETRIC_FOOTPRINT_PHYSICS_PASS rx=18 ry=9 against 64x32 diamond in four directions")
	get_tree().quit(0)


func _diamond() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -16.0),
		Vector2(32.0, 0.0),
		Vector2(0.0, 16.0),
		Vector2(-32.0, 0.0),
	])
