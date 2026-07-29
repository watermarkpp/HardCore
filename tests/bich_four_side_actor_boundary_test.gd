extends Node2D

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const SIDE_NAMES := [
	"upper_right",
	"lower_right",
	"lower_left",
	"upper_left",
]
const EDGE_ERROR_LIMIT_PX := 1.5


func _ready() -> void:
	var loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/bich_province.runtime.json"
	)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var raw_size: Array = loaded.runtime.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var visual_boundary := CollisionGeometry.map_inner_boundary_world(design_size)
	var actor_boundary := CollisionGeometry.map_actor_boundary_world(design_size)
	var outer_boundary := CollisionGeometry.map_outer_boundary_world(design_size)
	assert(visual_boundary.size() == 4)
	assert(actor_boundary.size() == 4)
	assert(outer_boundary.size() == 4)

	var boundary_body := StaticBody2D.new()
	boundary_body.collision_layer = WorldSpatialRules.WORLD_LAYER
	boundary_body.collision_mask = 0
	for side in visual_boundary.size():
		var following := (side + 1) % visual_boundary.size()
		var shape := ConvexPolygonShape2D.new()
		shape.points = PackedVector2Array([
			outer_boundary[side],
			outer_boundary[following],
			actor_boundary[following],
			actor_boundary[side],
		])
		var collision := CollisionShape2D.new()
		collision.name = "MapBoundary%d" % side
		collision.shape = shape
		boundary_body.add_child(collision)
	add_child(boundary_body)
	await get_tree().physics_frame

	var measured_errors := {}
	for side in visual_boundary.size():
		var following := (side + 1) % visual_boundary.size()
		var edge_start := visual_boundary[side]
		var edge_end := visual_boundary[following]
		var edge_midpoint := edge_start.lerp(edge_end, 0.5)
		var edge_direction := edge_end - edge_start
		var outward := Vector2(edge_direction.y, -edge_direction.x).normalized()
		var player := PlayerCharacter.new()
		add_child(player)
		await get_tree().physics_frame
		player.global_position = (
			edge_midpoint
			- outward * (ArtSpec.PLAYER_COLLISION_RADIUS + 4.0)
		)
		var collision := player.move_and_collide(outward * 160.0)
		assert(collision != null, "%s boundary allowed player escape" % SIDE_NAMES[side])
		var signed_error := (
			player.global_position - edge_midpoint
		).dot(outward)
		measured_errors[SIDE_NAMES[side]] = signed_error
		assert(
			absf(signed_error) <= EDGE_ERROR_LIMIT_PX,
			"%s foot point differs from visible edge by %.3fpx"
				% [SIDE_NAMES[side], signed_error]
		)
		player.queue_free()
		await get_tree().process_frame

	var left_difference := absf(
		float(measured_errors.lower_left)
		- float(measured_errors.upper_left)
	)
	var opposite_max_difference := maxf(
		absf(
			float(measured_errors.upper_left)
			- float(measured_errors.lower_right)
		),
		absf(
			float(measured_errors.lower_left)
			- float(measured_errors.upper_right)
		)
	)
	assert(
		left_difference <= 0.05,
		"left edge foot-point errors are asymmetric: %s" % measured_errors
	)
	assert(
		opposite_max_difference <= 0.05,
		"opposite edge foot-point errors are asymmetric: %s" % measured_errors
	)
	print(
		"BICH_FOUR_SIDE_ACTOR_BOUNDARY_PASS "
		+ "contract=%s errors=%s"
		% [CollisionGeometry.ACTOR_BOUNDARY_CONTRACT_ID, measured_errors]
	)
	get_tree().quit(0)
