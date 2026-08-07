extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const MAP_ID := 338
const EPSILON := 0.01

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Dictionary = Mapper.resolve_map_projection_profile(MAP_ID)
	assert(
		bool(profile.get("success", false)),
		"map 338 must resolve a formal projection profile"
	)
	assert(
		str(profile.get("policy", ""))
		== str(Mapper.PROJECTION_POLICY_AUTHORED_CENTERED_ABSOLUTE),
		"map 338 must be AUTHORED_CENTERED_ABSOLUTE (explicit policy, not identity fallback)"
	)
	var screen_to_ground: Callable = profile.get("screen_to_ground", Callable())
	var ground_to_screen: Callable = profile.get("ground_to_screen", Callable())
	var authored_screen := Vector2(-390.0, -200.0)
	var ground: Vector2 = screen_to_ground.call(authored_screen)
	var roundtrip: Vector2 = ground_to_screen.call(ground)
	assert(
		roundtrip.distance_to(authored_screen) <= EPSILON,
		"map 338 authored screen -> ground -> screen roundtrip must be identity"
	)
	# Real authored spawn path.
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_game.current_map_id = MAP_ID
	_game.current_zone = "毒蛇山谷"
	var monster := GameData.get_monster_by_id(92)
	assert(not monster.is_empty(), "monster 92 must exist for map 338")
	var enemy: EnemyActor = _game._spawn_enemy(monster, authored_screen, false)
	assert(
		enemy != null,
		"map 338 authored centered enemy spawn must succeed"
	)
	assert(
		enemy.spatial_index_position().distance_to(ground) <= EPSILON,
		"map 338 enemy provider must match the centered map-global ground"
	)
	var candidates: Array = _game._combat_spatial_index.query_aabb_candidates(
		MAP_ID,
		Rect2(ground - Vector2(2, 2), Vector2(4, 4)),
		0.05
	)
	assert(
		not candidates.is_empty(),
		"map 338 spatial index must contain the authored centered enemy"
	)
	_game.queue_free()
	await get_tree().process_frame
	print(
		"AUTHORED_CENTERED_MAP_PROJECTION_PASS policy=%s screen=%s ground=%s"
		% [profile.get("policy", ""), authored_screen, ground]
	)
	get_tree().quit(0)
