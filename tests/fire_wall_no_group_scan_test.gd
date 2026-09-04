extends Node

## Q2-C: the formal FireWall hot path never calls get_nodes_in_group("enemies")
## and never group-examines enemies; damage comes from the controller only.

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

const MAP_A := 11013
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controllers: Array[FireWallFieldController] = []
var _enemies: Array[EnemyActor] = []
var _damage_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	for i: int in range(4):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				Vector2(0.2 + float(i) * 0.2, 0.2)
			)
		)
	for i: int in range(4):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 5,
				MAP_A,
				Vector2(8.0 + float(i), 8.0)
			)
		)
	for i: int in range(2):
		_controllers.append(
			Fixtures.make_controller(
				self,
				_index,
				MAP_A,
				Vector2(0, 0),
				{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
				"q2c:no_scan:%d" % i,
				null,
				Callable(self, "_record_damage")
			)
		)
	for _tick: int in range(2):
		for controller: FireWallFieldController in _controllers:
			controller._apply_field_tick()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	for controller: FireWallFieldController in _controllers:
		var diag: Dictionary = controller.fire_wall_controller_diagnostics()
		assert(
			int(diag.get("group_scan_count", -1)) == 0
			and int(diag.get("group_nodes_examined", -1)) == 0,
			"controller must never group-scan enemies"
		)
		assert(
			int(diag.get("visual_cell_exact_test_count", -1)) == 0,
			"visual cells must never exact-test"
		)
	assert(
		_damage_count == 2 * 2 * 4,
		"damage must be exactly two ticks x two controllers x four inside enemies"
	)
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_NO_GROUP_SCAN_PASS damage=%d" % _damage_count)
	get_tree().quit(0)


func _cleanup() -> void:
	for controller: FireWallFieldController in _controllers:
		if is_instance_valid(controller):
			controller.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()


func _record_damage(enemy: EnemyActor, raw_power: int) -> void:
	_damage_count += 1
	enemy.take_damage(raw_power, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
