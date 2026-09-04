extends Node

## Q2-C stacking parity: overlapping FireWalls keep the legacy claim/stacking
## behavior (same caster shares one claim window; different casters stack).

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

const MAP_A := 11008
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controllers: Array[FireWallFieldController] = []
var _enemies: Array[EnemyActor] = []
var _damage_log: Array[int] = []
var _caster_a: Node2D
var _caster_b: Node2D
var _case_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_caster_a = Node2D.new()
	_caster_a.name = "Q2CCasterA"
	add_child(_caster_a)
	_caster_b = Node2D.new()
	_caster_b.name = "Q2CCasterB"
	add_child(_caster_b)
	_stacking_case("same_caster_same_skill", _caster_a, _caster_a, "r1", "r2", 1)
	_stacking_case("different_casters", _caster_a, _caster_b, "r1", "r2", 2)
	_stacking_case("same_release_duplicate", _caster_a, _caster_a, "dup", "dup", 1)
	_stacking_case("different_releases", _caster_a, _caster_a, "rel_a", "rel_b", 1)
	assert(_case_count == 4, "all stacking cases must run")
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_STACKING_PARITY_PASS cases=%d" % _case_count)
	get_tree().quit(0)


func _stacking_case(
	label: String,
	caster_a: Node2D,
	caster_b: Node2D,
	release_a: String,
	release_b: String,
	expected_damage: int
) -> void:
	_case_count += 1
	_fresh_world()
	_enemies.append(
		Fixtures.make_enemy(self, _index, 1, MAP_A, Vector2(0.2, 0.2))
	)
	for i: int in range(2):
		_controllers.append(
			Fixtures.make_controller(
				self,
				_index,
				MAP_A,
				Vector2(0, 0),
				{
					"raw_power": 3,
					"duration_seconds": 60.0,
					"tick_interval_ms": 5000,
				},
				release_a if i == 0 else release_b,
				caster_a if i == 0 else caster_b,
				Callable(self, "_record_damage")
			)
		)
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var legacy_count := _run_legacy()
	_restore_hp()
	_damage_log.clear()
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var manager_count := _run_manager()
	assert(
		legacy_count == expected_damage,
		"%s: legacy damage %d must equal expected %d"
		% [label, legacy_count, expected_damage]
	)
	assert(
		manager_count == legacy_count,
		"%s: manager damage %d must match legacy %d"
		% [label, manager_count, legacy_count]
	)
	_cleanup_world()


func _run_legacy() -> int:
	var total := 0
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
		total += int(result.get("damage_count", 0))
	return total


func _run_manager() -> int:
	for controller: FireWallFieldController in _controllers:
		controller._apply_field_tick()
	return _damage_log.size()


func _fresh_world() -> void:
	_cleanup_world()
	_index = SpatialIndexScript.new()
	_controllers.clear()
	_enemies.clear()
	_damage_log.clear()


func _restore_hp() -> void:
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.current_hp = 10000


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
	if _caster_a != null and is_instance_valid(_caster_a):
		_caster_a.queue_free()
	if _caster_b != null and is_instance_valid(_caster_b):
		_caster_b.queue_free()


func _record_damage(enemy: EnemyActor, raw_power: int) -> void:
	_damage_log.append(enemy.get_instance_id())
	enemy.take_damage(raw_power, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
