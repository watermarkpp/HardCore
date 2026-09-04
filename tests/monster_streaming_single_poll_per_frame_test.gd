extends Node

## Q2-D: MonsterVisual instances never call the global streaming poll; the
## coordinator runs exactly one poll per frame regardless of monster count.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const FRAMES := 600

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
	await _run_size(1)
	await _run_size(100)
	await _run_size(300)
	_cleanup()
	await get_tree().process_frame
	print("MONSTER_STREAMING_SINGLE_POLL_PER_FRAME_PASS")
	get_tree().quit(0)


func _run_size(monster_count: int) -> void:
	for i: int in range(monster_count):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_player,
				Fixtures.catalog_ids()[i % Fixtures.catalog_ids().size()],
				i + 1
			)
		)
	var frame_id := 0
	for _frame: int in range(FRAMES):
		frame_id += 1
		_coordinator.poll_once(frame_id)
		await get_tree().process_frame
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(diag.get("per_instance_poll_call_count", -1)) == 0,
		"MonsterVisual must never call the global streaming poll"
	)
	assert(
		int(diag.get("coordinator_poll_count", 0)) == FRAMES,
		"coordinator must poll exactly once per frame"
	)
	assert(
		int(diag.get("heavy_poll_execution_count", 0)) <= FRAMES,
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
