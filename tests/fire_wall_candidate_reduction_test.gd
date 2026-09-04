extends Node

## Q2-C candidate reduction on the fixed sparse fixture: 16 FireWalls x 256
## enemies x 60 ticks. The shared-index broadphase must cut exact tests by at
## least 60% versus the legacy full-group scan and never group-scan.

const Fixtures := preload(
	"res://tests/helpers/fire_wall_controller_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)

const MAP_A := 11012
const SKILL_ID := "wizard.fire_wall"
const CONTROLLER_COUNT := 16
const ENEMY_COUNT := 256
const TICK_COUNT := 60

var _index: SpatialIndexScript
var _controllers: Array[FireWallFieldController] = []
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	for i: int in range(ENEMY_COUNT):
		var center := Vector2(
			(i % 64) * 2.0 - 63.0,
			(i / 64) * 2.0 - 3.0
		)
		_enemies.append(
			Fixtures.make_enemy(self, _index, i + 1, MAP_A, center, 0.25)
		)
	for i: int in range(CONTROLLER_COUNT):
		var center := Vector2(
			(i % 4) * 16.0 - 24.0,
			(i / 4) * 2.0 - 3.0
		)
		_controllers.append(
			Fixtures.make_controller(
				self,
				_index,
				MAP_A,
				center,
				{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
				"q2c:reduction:%d" % i,
				null,
				Callable(self, "_noop_damage")
			)
		)
	for _tick: int in range(TICK_COUNT):
		for controller: FireWallFieldController in _controllers:
			controller._apply_field_tick()

	var legacy_examined := CONTROLLER_COUNT * ENEMY_COUNT * TICK_COUNT
	var legacy_exact_tests := legacy_examined
	var candidates := 0
	var exact_tests := 0
	var group_scans := 0
	var group_nodes := 0
	var cell_exact := 0
	var max_candidates := 0
	var broadphase_queries := 0
	for controller: FireWallFieldController in _controllers:
		var diag: Dictionary = controller.fire_wall_controller_diagnostics()
		candidates += int(diag.get("candidate_count", 0))
		exact_tests += int(diag.get("controller_exact_test_count", 0))
		group_scans += int(diag.get("group_scan_count", 0))
		group_nodes += int(diag.get("group_nodes_examined", 0))
		cell_exact += int(diag.get("visual_cell_exact_test_count", 0))
		broadphase_queries += int(diag.get("broadphase_query_count", 0))
		max_candidates = maxi(
			max_candidates,
			int(diag.get("max_candidate_count", 0))
		)
	var reduction_percent := 0.0
	if legacy_exact_tests > 0:
		reduction_percent = (
			100.0 * float(legacy_exact_tests - exact_tests)
			/ float(legacy_exact_tests)
		)
	assert(
		group_scans == 0 and group_nodes == 0,
		"fire wall production path must never group-scan enemies"
	)
	assert(
		cell_exact == 0,
		"visual cells must never run exact tests"
	)
	assert(
		broadphase_queries == CONTROLLER_COUNT * TICK_COUNT,
		"exactly one broadphase query per controller per tick"
	)
	assert(
		candidates < legacy_examined,
		"candidates must be fewer than legacy examined nodes"
	)
	assert(
		exact_tests < legacy_exact_tests,
		"exact tests must be reduced below legacy"
	)
	assert(
		reduction_percent >= 60.0,
		"exact test reduction must be at least 60 percent, got %.1f"
		% reduction_percent
	)
	var summary := (
		"FIRE_WALL_CANDIDATE_REDUCTION_PASS legacy_examined=%d candidates=%d "
		+ "max_candidates=%d exact_tests=%d reduction=%.1f%% "
		+ "group_scans=%d cell_exact=%d broadphase_queries=%d"
	) % [
		legacy_examined,
		candidates,
		max_candidates,
		exact_tests,
		reduction_percent,
		group_scans,
		cell_exact,
		broadphase_queries,
	]
	print(summary)
	_cleanup()
	await get_tree().process_frame
	get_tree().quit(0)


func _cleanup() -> void:
	for controller: FireWallFieldController in _controllers:
		if is_instance_valid(controller):
			controller.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()


func _noop_damage(_enemy: EnemyActor, _raw_power: int) -> void:
	pass


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
