extends Node
## Uses real production WorldBackground convex-body builder and actual Godot
## CharacterBody2D motion. Art loading is isolated, not collision geometry.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
const Geometry := preload("res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd")
const SIZE_GU := Vector2i(12, 12)
class TestWorld:
	extends "res://scripts/world_background.gd"
	func _ready() -> void:
		visible = false
		set_process(false)
		set_physics_process(false)
var errors: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_PHYSICS: " + message)

func _ready() -> void:
	call_deferred("run")

func world_fixture(points: PackedVector2Array) -> TestWorld:
	var world := TestWorld.new()
	add_child(world)
	var index := Index.new()
	check(index.setup(SIZE_GU, [Geo.encode(points)]), "world index")
	world._editor_runtime_collision_snapshot = {"poly_index": index, "design_size": SIZE_GU,
		"boundary_world": Geometry.map_actor_boundary_world(SIZE_GU)}
	var body: CollisionObject2D = world._build_hc_polygon_part({"polygon": points, "size": SIZE_GU})
	check(is_instance_valid(body), "production convex body builder returns body")
	if is_instance_valid(body):
		check(body.is_inside_tree(), "production body registered in tree")
		check(body.collision_layer == Rules.WORLD_LAYER, "world collision layer preserved")
	var inner := Geometry.map_actor_boundary_world(SIZE_GU)
	var outer := Geometry.map_outer_boundary_world(SIZE_GU)
	for side: int in range(4):
		var following := (side + 1) % 4
		world._build_editor_boundary_side({"outer": outer[side], "outer_next": outer[following], "inner": inner[side], "inner_next": inner[following], "side": side})
	return world

func screen_delta(delta_gu: Vector2) -> Vector2:
	return Coord.ground_position_gu_to_screen_position_px(delta_gu, SIZE_GU) - Coord.ground_position_gu_to_screen_position_px(Vector2.ZERO, SIZE_GU)

func actor_fixture(point: Vector2, radius_px: float) -> CharacterBody2D:
	var actor := CharacterBody2D.new()
	actor.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	actor.collision_layer = Rules.PLAYER_LAYER
	actor.collision_mask = Rules.WORLD_MASK
	actor.safe_margin = 0.08
	actor.max_slides = 6
	var shape := CollisionShape2D.new()
	var footprint := ConvexPolygonShape2D.new()
	footprint.points = Rules.actor_footprint_polygon_px(radius_px)
	shape.shape = footprint
	actor.add_child(shape)
	actor.position = Coord.ground_position_gu_to_screen_position_px(point, SIZE_GU)
	add_child(actor)
	return actor

func run() -> void:
	var radius_px := 12.0
	var wall := Geo.decode([[5.001,0],[5.007,0],[5.007,12],[5.001,12]])
	var world := world_fixture(wall)
	var actor := actor_fixture(Vector2(2,5), radius_px)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for step: int in range(6):
		await get_tree().physics_frame
		actor.velocity = screen_delta(Vector2(800,0))
		actor.move_and_slide()
		var p := Coord.screen_position_px_to_ground_position_gu(actor.global_position, SIZE_GU)
		check(p.x < 5.001, "large swept move cannot tunnel through sub-cell wall")
		check(not world.is_environment_actor_blocked(actor.global_position, radius_px), "physical contact does not trigger old-cell rollback")
	actor.queue_free()
	world.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	## Wall along GU x=5 projects to a slanted edge on screen. Diagonal intent
	## should retain tangential movement rather than repeatedly snapping back.
	world = world_fixture(Geo.decode([[5,1],[5.1,1],[5.1,11],[5,11]]))
	actor = actor_fixture(Vector2(4.72,3), radius_px)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var initial := Coord.screen_position_px_to_ground_position_gu(actor.global_position, SIZE_GU)
	for step: int in range(60):
		await get_tree().physics_frame
		actor.velocity = screen_delta(Vector2(2,2))
		actor.move_and_slide()
		check(not world.is_environment_actor_blocked(actor.global_position, radius_px), "slanted-wall legal slide remains valid")
	var final_point := Coord.screen_position_px_to_ground_position_gu(actor.global_position, SIZE_GU)
	check(final_point.y > initial.y + .2, "nonzero tangential slide along slanted world wall")
	check(final_point.x < 5.0, "slide never crosses wall")
	var center_open := Coord.ground_position_gu_to_screen_position_px(Vector2(4.9,5), SIZE_GU)
	check(world.is_environment_actor_blocked(center_open, radius_px), "full-foot guard catches overlap, not only actor center")
	actor.queue_free()
	world.queue_free()
	await get_tree().process_frame
	if errors.is_empty():
		print("HC_POLYGON_PHYSICS_TEST_PASS checks=", checks)
	get_tree().quit(0 if errors.is_empty() else 1)
