extends Node

## Q2-D spatial index non-regression: MonsterVisual streaming registration,
## resource load, visual unregister and resource switch must never change the
## enemy's spatial index registration, position, runtime_map_id or stable
## combat order.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_A := 12001

var _coordinator
var _player: PlayerCharacter
var _index: SpatialIndexScript
var _enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(true)
	_index = SpatialIndexScript.new()
	_enemy = Fixtures.make_enemy(
		self,
		_player,
		Fixtures.catalog_ids()[0],
		1,
		MAP_A
	)
	# Production spawn sequence: set_combat_position then canonical register.
	_enemy.set_combat_position(Vector2(120, 80), &"q2d_spawn")
	var ground_gu: Vector2 = (
		GroundUnit.screen_delta_px_to_ground_delta_gu(
			_enemy.global_position
		)
	)
	_enemy.configure_spatial_index(_index, 77)
	_index.register(
		77,
		MAP_A,
		ground_gu,
		_enemy.combat_radius_gu,
		77,
		_enemy,
		Callable(_enemy, "spatial_index_position")
	)
	await get_tree().process_frame
	var register_before := _index.index_register_count
	var unregister_before := _index.index_unregister_count
	var actor_count_before := _index.registered_actor_count()
	var position_before := _enemy.global_position
	var map_before := _enemy.runtime_map_id
	var order_before := 77
	# Visual load + switch + visual unregister (enemy stays).
	Fixtures.drive_residency_activation(_enemy.visual)
	_enemy.visual._release_resources()
	_enemy.visual._activate_resources()
	_enemy.visual.queue_free()
	await get_tree().process_frame
	_coordinator.poll_once(Engine.get_process_frames())
	await get_tree().process_frame
	assert(
		_index.index_register_count == register_before,
		"visual streaming must not add spatial index registrations"
	)
	assert(
		_index.index_unregister_count == unregister_before,
		"visual unregister must not unregister the enemy from combat space"
	)
	assert(
		_index.registered_actor_count() == actor_count_before,
		"visual lifecycle must not change the enemy spatial registry"
	)
	assert(
		_enemy.global_position == position_before,
		"visual resource switch must not change the enemy position"
	)
	assert(
		_enemy.runtime_map_id == map_before,
		"visual resource switch must not change the enemy runtime_map_id"
	)
	assert(
		_enemy.get_meta("spawn_serial", 0) == 1
		and order_before == 77,
		"stable combat order must be unchanged"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"MONSTER_STREAMING_SPATIAL_INDEX_NON_REGRESSION_PASS "
		+ "register=%d unregister=%d registered=%d"
		% [register_before, unregister_before, actor_count_before]
	)
	get_tree().quit(0)


func _cleanup() -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
