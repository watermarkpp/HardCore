extends Node

## Q2-D: the formal streaming path never calls load()/ResourceLoader.load() for
## large monster resources; all loads are threaded.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var _coordinator
var _player: PlayerCharacter
var _enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_enemy = Fixtures.make_enemy(
		self,
		_player,
		Fixtures.catalog_ids()[0],
		1
	)
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 20000
	while (
		_coordinator.pending_request_count() > 0
		and Time.get_ticks_msec() < deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		_coordinator.threaded_texture_request_count() > 0,
		"formal path must issue threaded texture loads"
	)
	assert(
		int(diag.get("sync_load_count", 0)) == 0,
		"formal streaming path must never sync-load"
	)
	assert(
		(diag.get("sync_load_paths", []) as Array).is_empty(),
		"no sync load paths may be recorded"
	)
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_NO_SYNC_LOAD_PASS sync_loads=0 threaded=%d" % (
		_coordinator.threaded_texture_request_count()
	))
	get_tree().quit(0)


func _cleanup() -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
