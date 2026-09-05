extends Node

## Q2-C hit parity: the single-query controller must produce the same hit ids,
## damage order and damage counts as the legacy per-cell traversal.

const Fixtures := preload(
	"res://tests/helpers/fire_wall_controller_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Reference := preload(
	"res://tests/helpers/fire_wall_legacy_reference_tick.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)

const MAP_A := 11004
const MAP_B := 11005
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controllers: Array[FireWallFieldController] = []
var _enemies: Array[EnemyActor] = []
var _damage_log: Array[int] = []
var _case_count := 0
var _difference_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_run_case("no_targets", [], 1)
	_run_case("single_hit", [[Vector2(0.0, 0.0), 0.25]], 1)
	_run_case(
		"multiple",
		[
			[Vector2(0.0, 0.0), 0.25],
			[Vector2(0.3, 0.0), 0.25],
			[Vector2(0.1, 0.1), 0.25],
		],
		1
	)
	_run_case("boundary_4cell", [[Vector2(0.5, 0.5), 0.25]], 1)
	_run_case("boundary_2cell", [[Vector2(0.5, 0.2), 0.25]], 1)
	_run_case("dead_target", [[Vector2(0.2, 0.2), 0.25, 1]], 1)
	_run_case("same_frame_forced_move", [[Vector2(3.0, 3.0), 0.25]], 1, Vector2(0.2, 0.2))
	_run_case("cross_map_different_coords", [[Vector2(5.0, 5.0), 0.25]], 1, Vector2.INF, MAP_B)
	_run_case("two_overlapping", [[Vector2(0.2, 0.2), 0.25]], 2)
	assert(
		_difference_count == 0,
		"new controller hit parity must match the legacy reference"
	)
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_HIT_PARITY_PASS cases=%d" % _case_count)
	get_tree().quit(0)


func _run_case(
	label: String,
	enemy_specs: Array,
	controller_count: int,
	move_to_ground_gu := Vector2.INF,
	enemy_map_id := MAP_A
) -> void:
	_case_count += 1
	var legacy_result := _run_variant(
		label,
		enemy_specs,
		controller_count,
		move_to_ground_gu,
		enemy_map_id,
		false
	)
	var manager_result := _run_variant(
		label,
		enemy_specs,
		controller_count,
		move_to_ground_gu,
		enemy_map_id,
		true
	)
	if label == "dead_target":
		_assert_dead_target_result("legacy", legacy_result)
		_assert_dead_target_result("manager", manager_result)
	var legacy_order: Array = legacy_result.get("damage_order", [])
	var manager_order: Array = manager_result.get("damage_order", [])
	if legacy_order.size() != manager_order.size():
		_difference_count += 1
		push_error(
			"parity %s: damage count legacy=%d manager=%d"
			% [label, legacy_order.size(), manager_order.size()]
		)
		return
	for i: int in range(legacy_order.size()):
		if legacy_order[i] != manager_order[i]:
			_difference_count += 1
			push_error(
				"parity %s: stable serial mismatch at %d legacy=%d manager=%d"
				% [label, i, legacy_order[i], manager_order[i]]
			)
			break


func _run_variant(
	label: String,
	enemy_specs: Array,
	controller_count: int,
	move_to_ground_gu: Vector2,
	enemy_map_id: int,
	use_manager: bool
) -> Dictionary:
	_fresh_world()
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	for i: int in range(controller_count):
		_controllers.append(
			Fixtures.make_controller(
				self,
				_index,
				MAP_A,
				Vector2(0, 0),
				{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
				"q2c:parity:%s:%d" % [label, i],
				null,
				Callable(self, "_record_damage")
			)
		)
	for i: int in range(enemy_specs.size()):
		var spec: Array = enemy_specs[i]
		var hp := int(spec[2]) if spec.size() > 2 else 10000
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				enemy_map_id,
				spec[0] as Vector2,
				float(spec[1]),
				hp
			)
		)
	if label == "dead_target" and not _enemies.is_empty():
		_enemies[0].take_damage(99999, null)
	if move_to_ground_gu.is_finite() and not _enemies.is_empty():
		_enemies[0].set_combat_position(
			GroundUnit.ground_delta_gu_to_screen_delta_px(move_to_ground_gu),
			&"q2c_parity_move"
		)
	var result := _run_manager() if use_manager else _run_legacy()
	_cleanup_world()
	return result


func _run_legacy() -> Dictionary:
	var exact_test_count := 0
	var damage_count := 0
	for controller: FireWallFieldController in _controllers:
		var testers: Array[Callable] = []
		var claim_cells: Array = []
		for cell: GroundSkillVisualCell in controller.visual_cells:
			testers.append(Callable(cell, "runtime_target_is_inside"))
			claim_cells.append(cell)
		var result: Dictionary = Reference.legacy_tick(
			testers,
			claim_cells,
			_enemies,
			Callable(self, "_record_damage"),
			true,
			true
		)
		exact_test_count += int(result.get("exact_test_count", 0))
		damage_count += int(result.get("damage_count", 0))
	assert(
		damage_count == _damage_log.size(),
		"legacy callback count must match reported damage count"
	)
	return {
		"exact_test_count": exact_test_count,
		"callback_count": _damage_log.size(),
		"damage_count": damage_count,
		"damage_order": _damage_log.duplicate(),
	}


func _run_manager() -> Dictionary:
	for controller: FireWallFieldController in _controllers:
		controller._apply_field_tick()
	var exact_test_count := 0
	var damage_count := 0
	for controller: FireWallFieldController in _controllers:
		exact_test_count += controller.controller_exact_test_count
		damage_count += controller.damage_application_count
	assert(
		damage_count == _damage_log.size(),
		"manager callback count must match reported damage count"
	)
	return {
		"exact_test_count": exact_test_count,
		"callback_count": _damage_log.size(),
		"damage_count": damage_count,
		"damage_order": _damage_log.duplicate(),
	}


func _fresh_world() -> void:
	_cleanup_world()
	_index = SpatialIndexScript.new()
	_controllers.clear()
	_enemies.clear()
	_damage_log.clear()


func _cleanup_world() -> void:
	for controller: FireWallFieldController in _controllers:
		if is_instance_valid(controller):
			controller.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_controllers.clear()
	_enemies.clear()
	_damage_log.clear()


func _cleanup() -> void:
	_cleanup_world()


func _record_damage(enemy: EnemyActor, raw_power: int) -> void:
	assert(
		enemy.spatial_actor_runtime_id > 0,
		"parity damage target must expose a stable fixture serial"
	)
	_damage_log.append(enemy.spatial_actor_runtime_id)
	enemy.take_damage(raw_power, null)


func _assert_dead_target_result(label: String, result: Dictionary) -> void:
	assert(
		int(result.get("exact_test_count", -1)) == 0,
		"%s dead target must not enter exact intersection tests" % label
	)
	assert(
		int(result.get("callback_count", -1)) == 0,
		"%s dead target must not invoke damage callbacks" % label
	)
	assert(
		int(result.get("damage_count", -1)) == 0,
		"%s dead target must not receive damage" % label
	)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
