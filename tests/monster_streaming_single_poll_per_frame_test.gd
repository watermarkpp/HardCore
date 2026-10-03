extends Node

## Q2-D: MonsterVisual instances never call the global streaming poll; the
## coordinator runs exactly one poll per frame regardless of monster count.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var _coordinator
var _player: PlayerCharacter
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_coordinator = Fixtures.make_coordinator()
	_player = Fixtures.make_player(self)
	MonsterVisual.set_synchronous_loading_for_tests(true)
	await _run_size(1, 600)
	await _run_size(100, 180)
	await _run_size(300, 120)
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_SINGLE_POLL_PER_FRAME_PASS")
	get_tree().quit(0)


func _run_size(monster_count: int, frames: int) -> void:
	for i: int in range(monster_count):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_player,
				Fixtures.catalog_ids()[i % Fixtures.catalog_ids().size()],
				i + 1
			)
		)
	print("STREAMING_SINGLE_POLL_SETUP "+JSON.stringify({"monsters":monster_count,"process_epoch":Engine.get_process_frames(),"budget":Budget.snapshot()}))
	# Startup's necessary save is charged to the same real epoch. Begin
	# measurement only after an actual epoch transition, never by resetting
	# the ledger or inventing frame IDs. Keep all original 900 sample frames.
	var previous_epoch := Engine.get_process_frames()
	for _frame: int in range(frames):
		while Engine.get_process_frames() == previous_epoch:
			await get_tree().process_frame
		var frame_id := Engine.get_process_frames()
		var before_poll: int = _coordinator.coordinator_poll_count
		_coordinator.poll_once(frame_id)
		assert(_coordinator.coordinator_poll_count == before_poll+1,
			"a fresh actual epoch admits one formal poll without a second budget")
		_coordinator.poll_once(frame_id)
		assert(_coordinator.coordinator_poll_count == before_poll+1,
			"a same-epoch repeated call cannot execute a second heavy poll")
		previous_epoch = frame_id
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	print("STREAMING_SINGLE_POLL_RESULT "+JSON.stringify({"monsters":monster_count,"expected_frames":frames,"process_epoch":Engine.get_process_frames(),"diagnostics":diag,"budget":Budget.snapshot()}))
	assert(
		int(diag.get("per_instance_poll_call_count", -1)) == 0,
		"MonsterVisual must never call the global streaming poll"
	)
	assert(
		int(diag.get("coordinator_poll_count", 0)) == frames,
		"coordinator must poll exactly once per frame"
	)
	assert(
		int(diag.get("heavy_poll_execution_count", 0)) <= frames,
		"heavy poll executions must never exceed frame count"
	)
	print(
		"MONSTER_STREAMING_SINGLE_POLL_SIZE monsters=%d coordinator_polls=%d"
		% [monster_count, int(diag.get("coordinator_poll_count", 0))]
	)
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	await get_tree().process_frame
	_coordinator.reset_for_tests()


func _cleanup() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	MonsterVisual.reset_client_resource_cache()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
