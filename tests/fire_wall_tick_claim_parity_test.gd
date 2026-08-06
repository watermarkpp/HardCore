extends Node

## Q2-C tick/claim parity: tick timing, tick counts, claim keys and windows and
## damage counts must match the legacy controller exactly.

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

const MAP_A := 11006
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
	_tick_cadence_case("first_tick", 1.0, 60.0, [0.25])
	_tick_cadence_case("normal", 1.0, 6.0, [0.5, 0.5, 0.5, 0.5, 2.0, 1.0, 2.0])
	_tick_cadence_case("long_frame", 1.0, 10.0, [0.1, 3.0])
	_tick_cadence_case("expiry", 1.0, 2.0, [0.5, 0.5, 0.5, 0.5])
	_claim_case("same_caster", _caster_a, _caster_a, 1)
	_claim_case("different_caster", _caster_a, _caster_b, 2)
	_claim_case("different_release", _caster_a, _caster_a, 1)
	assert(_case_count == 7, "all parity cases must run")
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_TICK_CLAIM_PARITY_PASS cases=%d" % _case_count)
	get_tree().quit(0)


func _tick_cadence_case(
	label: String,
	interval: float,
	duration: float,
	deltas: Array
) -> void:
	_case_count += 1
	_fresh_world()
	_controllers.append(
		Fixtures.make_controller(
			self,
			_index,
			MAP_A,
			Vector2(0, 0),
			{
				"raw_power": 3,
				"duration_seconds": duration,
				"tick_interval_ms": interval * 1000.0,
			},
			"q2c:cadence:%s" % label,
			null,
			Callable(self, "_record_damage")
		)
	)
	_enemies.append(
		Fixtures.make_enemy(self, _index, 1, MAP_A, Vector2(0.2, 0.2))
	)
	var legacy: Dictionary = _legacy_cadence(interval, duration, deltas)
	var manager_ticks: Array[float] = []
	var elapsed := 0.0
	for raw_delta: Variant in deltas:
		var delta := float(raw_delta)
		elapsed += delta
		var before := _damage_log.size()
		_controllers[0]._physics_process(delta)
		if _damage_log.size() > before:
			manager_ticks.append(elapsed)
	var legacy_ticks: Array = legacy.get("ticks", [])
	assert(
		manager_ticks.size() == legacy_ticks.size(),
		"%s: tick count manager=%d legacy=%d"
		% [label, manager_ticks.size(), legacy_ticks.size()]
	)
	for i: int in range(legacy_ticks.size()):
		assert(
			is_equal_approx(float(manager_ticks[i]), float(legacy_ticks[i])),
			"%s: tick time %d manager=%f legacy=%f"
			% [label, i, float(manager_ticks[i]), float(legacy_ticks[i])]
		)
	assert(
		_damage_log.size() == legacy_ticks.size(),
		"%s: damage count must equal legacy tick count" % label
	)
	_cleanup_world()


func _claim_case(
	label: String,
	caster_a: Node2D,
	caster_b: Node2D,
	expected_legacy_damage: int
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
				"q2c:claim:%s:%d" % [label, i],
				caster_a if i == 0 else caster_b,
				Callable(self, "_record_damage")
			)
		)
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var legacy_count := _run_legacy()
	var legacy_keys: Array = GroundSkillEffect._runtime_tick_claims.keys()
	_restore_hp()
	_damage_log.clear()
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var manager_count := _run_manager()
	var manager_keys: Array = GroundSkillEffect._runtime_tick_claims.keys()
	assert(
		legacy_count == expected_legacy_damage,
		"%s: legacy damage %d must equal expected %d"
		% [label, legacy_count, expected_legacy_damage]
	)
	assert(
		manager_count == legacy_count,
		"%s: manager damage %d must match legacy %d"
		% [label, manager_count, legacy_count]
	)
	assert(
		legacy_keys.size() == manager_keys.size(),
		"%s: claim key set sizes must match" % label
	)
	for key: Variant in legacy_keys:
		assert(
			manager_keys.has(key),
			"%s: claim key %s must be reused verbatim" % [label, key]
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


static func _legacy_cadence(
	interval: float,
	duration: float,
	deltas: Array
) -> Dictionary:
	var elapsed := 0.0
	var timer := 0.0
	var remaining := duration
	var ticks: Array[float] = []
	var expiry_elapsed := -1.0
	for raw_delta: Variant in deltas:
		var delta := float(raw_delta)
		elapsed += delta
		remaining -= delta
		timer -= delta
		if timer <= 0.0:
			timer = interval
			ticks.append(elapsed)
		if remaining <= 0.0:
			expiry_elapsed = elapsed
			break
	return {"ticks": ticks, "expiry_elapsed": expiry_elapsed}


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
