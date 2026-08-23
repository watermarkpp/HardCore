extends Node

## Q2-D: with every MonsterVisual destroyed, the coordinator must continue
## processing (or safely cancel) pending requests - never a permanent LOADING
## queue with zero subscribers.

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
	assert(
		_coordinator.pending_request_count() > 0,
		"a threaded request must be pending"
	)
	_enemy.queue_free()
	_enemy = null
	await get_tree().process_frame
	assert(
		_coordinator.registered_visual_count() == 0,
		"all visuals are unregistered"
	)
	var deadline := Time.get_ticks_msec() + 20000
	while (
		_coordinator.pending_request_count() > 0
		and Time.get_ticks_msec() < deadline
	):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	assert(
		_coordinator.pending_request_count() == 0,
		"the no-visual queue must complete (or cancel), never stay LOADING"
	)
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		_coordinator.cached_client_profile_count() >= 1,
		"the shared resource must still enter the cache for later reuse"
	)
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_NO_VISUAL_QUEUE_PASS")
	get_tree().quit(0)


func _cleanup() -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.queue_free()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
