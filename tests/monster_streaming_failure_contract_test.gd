extends Node

## Q2-D failure contract: missing resources fail once, never retry, never
## duplicate, never sync-load, never spam errors; state is explicit FAILED.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var _coordinator
var _player: PlayerCharacter


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var missing_mapping := {
		"frameSize": [160, 160],
		"footAnchor": [80, 138],
		"directionPolicy": "mir2_directional",
		"healthBarTopByDirection": [],
		"actions": {
			"idle": {"path": "res://missing_idle.png", "framesPerDirection": 4},
			"walk": {"path": "res://missing_walk.png", "framesPerDirection": 4},
			"attack": {"path": "res://missing_attack.png", "framesPerDirection": 4},
			"hit": {"path": "res://missing_hit.png", "framesPerDirection": 4},
			"death": {"path": "res://missing_death.png", "framesPerDirection": 4},
		},
	}
	_coordinator.request_client_profile(missing_mapping, -1)
	_coordinator.request_client_profile(missing_mapping, -1)
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(diag.get("failed_resource_count", 0)) >= 1,
		"missing resource must be recorded as failed"
	)
	assert(
		int(diag.get("duplicate_request_count", 0)) >= 1,
		"re-requesting the same failed key must be deduplicated"
	)
	assert(
		_coordinator.threaded_texture_request_count() == 0,
		"a missing path must never issue threaded loads"
	)
	assert(
		int(diag.get("sync_load_count", 0)) == 0,
		"failure must never fall back to a synchronous load"
	)
	# Polling must not retry or mutate the failed state.
	for _frame: int in range(10):
		_coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	var after: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(after.get("failed_resource_count", 0))
		== int(diag.get("failed_resource_count", 0)),
		"failure must not retry or grow without a new request"
	)
	assert(
		_coordinator.threaded_texture_request_count() == 0,
		"no retry threaded requests after failure"
	)
	assert(
		int(after.get("status_poll_count", 0)) == 0,
		"failed jobs must not be status-polled"
	)
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_FAILURE_CONTRACT_PASS")
	get_tree().quit(0)


func _cleanup() -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
