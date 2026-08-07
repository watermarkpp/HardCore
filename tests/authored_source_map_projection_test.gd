extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_ID := 248
const SOURCE_SIZE := Vector2i(400, 400)
const EPSILON := 0.01

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Dictionary = Mapper.resolve_map_projection_profile(MAP_ID)
	assert(
		bool(profile.get("success", false)),
		"map 248 must resolve a formal projection profile"
	)
	assert(
		str(profile.get("policy", ""))
		== str(Mapper.PROJECTION_POLICY_AUTHORED_SOURCE_ABSOLUTE),
		"map 248 must be AUTHORED_SOURCE_ABSOLUTE"
	)
	assert(
		profile.get("source_size", Vector2i.ZERO) == SOURCE_SIZE,
		"map 248 source_size must be 400x400"
	)
	var screen_to_ground: Callable = profile.get("screen_to_ground", Callable())
	var ground_to_screen: Callable = profile.get("ground_to_screen", Callable())
	var screen: Vector2 = ground_to_screen.call(Vector2(89.0, 75.0))
	var ground: Vector2 = screen_to_ground.call(screen)
	assert(
		screen.distance_to(Vector2(448.0, -3760.0)) <= EPSILON,
		"map 248 ground (89,75) must project to screen (448,-3760)"
	)
	assert(
		ground.distance_to(Vector2(89.0, 75.0)) <= EPSILON,
		"map 248 ground->screen->ground roundtrip must be identity"
	)
	# Real authored spawn path: _load_zone -> _spawn_database_zone_content ->
	# _spawn_authored_map_content -> _spawn_enemy.
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().physics_frame
	_game.current_map_id = MAP_ID
	_game.current_zone = "洞穴一层"
	var monster := GameData.get_monster_by_id(43)
	assert(not monster.is_empty(), "monster 43 must exist for map 248")
	var enemy: EnemyActor = _game._spawn_enemy(
		monster,
		Vector2(448.0, -3760.0),
		false
	)
	assert(
		enemy != null,
		"map 248 authored enemy spawn must succeed (not rejected)"
	)
	assert(
		enemy.spatial_index_position().distance_to(Vector2(89.0, 75.0))
		<= EPSILON,
		"map 248 enemy provider must be the source-absolute ground (89,75)"
	)
	var candidates: Array = _game._combat_spatial_index.query_aabb_candidates(
		MAP_ID,
		Rect2(Vector2(89.0, 75.0) - Vector2(2, 2), Vector2(4, 4)),
		0.05
	)
	assert(
		not candidates.is_empty(),
		"map 248 spatial index must contain the authored enemy"
	)
	_game.queue_free()
	await get_tree().process_frame
	print(
		"AUTHORED_SOURCE_MAP_PROJECTION_PASS policy=%s ground=%s screen=%s"
		% [profile.get("policy", ""), ground, screen]
	)
	get_tree().quit(0)
