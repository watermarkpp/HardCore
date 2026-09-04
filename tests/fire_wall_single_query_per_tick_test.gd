extends Node

## Q2-C: every FireWallFieldController runs exactly ONE broadphase query per
## tick (never one query per visual cell).

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

const MAP_A := 11001
const SKILL_ID := "wizard.fire_wall"
const TICKS := 5

var _index: SpatialIndexScript
var _controllers: Array[FireWallFieldController] = []
var _enemies: Array[EnemyActor] = []
var _damage_log: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	for i: int in range(20):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				Vector2((i % 5) * 0.7 - 1.4, (i / 5) * 0.7 - 1.4)
			)
		)
	for i: int in range(3):
		_controllers.append(
			Fixtures.make_controller(
				self,
				_index,
				MAP_A,
				Vector2(0, 0),
				{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
				"q2c:single_query:%d" % i,
				null,
				Callable(self, "_record_damage"),
				Vector2i(i * 2, 0)
			)
		)
	for _tick: int in range(TICKS):
		for controller: FireWallFieldController in _controllers:
			controller._apply_field_tick()
	for controller: FireWallFieldController in _controllers:
		var diag: Dictionary = controller.fire_wall_controller_diagnostics()
		assert(
			int(diag.get("tick_count", 0)) == TICKS,
			"controller must tick exactly %d times" % TICKS
		)
		assert(
			int(diag.get("broadphase_query_count", 0)) == TICKS,
			"one broadphase query per controller tick"
		)
		assert(
			int(diag.get("broadphase_query_count", 0))
			== int(diag.get("tick_count", 0)),
			"broadphase_query_count must equal controller_tick_count"
		)
		assert(
			int(diag.get("group_scan_count", -1)) == 0
			and int(diag.get("group_nodes_examined", -1)) == 0,
			"single-query controller must never group-scan"
		)
		assert(
			int(diag.get("visual_cell_exact_test_count", -1)) == 0,
			"visual cells must never run exact tests"
		)
	_cleanup()
	await get_tree().process_frame
	print(
		"FIRE_WALL_SINGLE_QUERY_PER_TICK_PASS controllers=%d ticks=%d"
		% [_controllers.size(), TICKS]
	)
	get_tree().quit(0)


func _cleanup() -> void:
	for controller: FireWallFieldController in _controllers:
		if is_instance_valid(controller):
			controller.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()


func _record_damage(enemy: EnemyActor, raw_power: int) -> void:
	_damage_log.append(enemy.get_instance_id())
	enemy.take_damage(raw_power, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
