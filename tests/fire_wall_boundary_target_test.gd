extends Node

## Q2-C boundary targets: enemies on 2-cell and 4-cell junctions take exactly
## one damage per tick and at most one canonical exact test per candidate.

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

const MAP_A := 11007
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controller: FireWallFieldController
var _enemies: Array[EnemyActor] = []
var _damage_log: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	_controller = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:boundary:1",
		null,
		Callable(self, "_record_damage")
	)
	var positions := [
		Vector2(0.5, 0.2),
		Vector2(0.5, 0.5),
		Vector2(0.2, 0.2),
		Vector2(3.0, 3.0),
	]
	for i: int in range(positions.size()):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				positions[i]
			)
		)
	for _tick: int in range(3):
		_damage_log.clear()
		_controller._apply_field_tick()
		var diag: Dictionary = _controller.fire_wall_controller_diagnostics()
		assert(
			int(diag.get("controller_exact_test_count", 0))
			<= int(diag.get("candidate_count", 0)),
			"exact tests must never exceed candidates"
		)
		assert(
			int(diag.get("visual_cell_exact_test_count", -1)) == 0,
			"visual cells must never run exact tests"
		)
		for enemy: EnemyActor in _enemies:
			var count := _damage_log.count(enemy.get_instance_id())
			var expected := 1 if enemy != _enemies[3] else 0
			assert(
				count == expected,
				"boundary enemy must take exactly one damage per tick (got %d)"
				% count
			)
	_cleanup()
	await get_tree().process_frame
	print(
		"FIRE_WALL_BOUNDARY_TARGET_PASS ticks=3 boundary_targets=3"
	)
	get_tree().quit(0)


func _cleanup() -> void:
	if _controller != null and is_instance_valid(_controller):
		_controller.queue_free()
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
