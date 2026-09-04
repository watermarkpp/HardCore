extends Node

## Q2-D scaling: 1/100/300 MonsterVisuals over 600 frames - per-instance global
## poll calls stay 0 and the coordinator poll count stays at 600 (never grows
## with monster count). Old behavior was monsters x frames calls.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const FRAMES := 600

var _coordinator
var _player: PlayerCharacter
var _enemies: Array[EnemyActor] = []
var _per_size_reports: Array[Dictionary] = []


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
	for report: Dictionary in _per_size_reports:
		assert(
			int(report.get("per_instance_poll_calls", -1)) == 0,
			"per-instance global poll calls must be zero"
		)
		assert(
			int(report.get("coordinator_polls", 0)) == FRAMES,
			"coordinator polls must equal the frame count"
		)
		assert(
			int(report.get("heavy_polls", 0)) <= FRAMES,
			"heavy polls must never exceed the frame count"
		)
		assert(
			int(report.get("cleanup_max_per_poll", 0))
				<= _coordinator.MAX_SUBSCRIBER_CLEANUP_VISITS_PER_POLL,
			"subscriber cleanup exceeded its fixed per-frame budget"
		)
		assert(
			int(report.get("cleanup_visits", 0))
				<= FRAMES * _coordinator.MAX_SUBSCRIBER_CLEANUP_VISITS_PER_POLL,
			"subscriber cleanup work scaled beyond frames x fixed budget"
		)
	assert(
		int(_per_size_reports[2].get("coordinator_polls", 0)) == FRAMES,
		"300-monster global poll calls must not grow (600, not 180000)"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"MONSTER_STREAMING_SCALING_PASS 1/100/300 monsters x 600 frames: "
		+ "per_instance=0 coordinator_polls=600 each"
	)
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
	_per_size_reports.append({
		"monster_count": monster_count,
		"per_instance_poll_calls": int(
			diag.get("per_instance_poll_call_count", 0)
		),
		"coordinator_polls": int(diag.get("coordinator_poll_count", 0)),
		"heavy_polls": int(diag.get("heavy_poll_execution_count", 0)),
		"cleanup_visits": int(diag.get("subscriber_cleanup_visit_count", 0)),
		"cleanup_max_per_poll": int(
			diag.get("subscriber_cleanup_max_visits_per_poll", 0)
		),
	})
	print(
		"MONSTER_STREAMING_SCALING_SIZE monsters=%d coordinator_polls=%d heavy=%d"
		% [
			monster_count,
			int(diag.get("coordinator_poll_count", 0)),
			int(diag.get("heavy_poll_execution_count", 0)),
		]
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
