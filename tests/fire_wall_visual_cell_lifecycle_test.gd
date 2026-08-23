extends Node

## Q2-C visual cell lifecycle: early cell destruction never changes the damage
## range; natural expiry, manual cancel, caster death, map/generation clear and
## controller teardown leave no orphan cells and no post-expiry damage.

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

const MAP_A := 11011
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controller: FireWallFieldController
var _caster: Node2D
var _enemies: Array[EnemyActor] = []
var _damage_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cell_early_free_case()
	_natural_expiry_case()
	_manual_cancel_case()
	_caster_death_case()
	_map_generation_clear_case()
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_VISUAL_CELL_LIFECYCLE_PASS")
	get_tree().quit(0)


func _cell_early_free_case() -> void:
	_fresh_world()
	_controller = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:lifecycle:cell_free",
		null,
		Callable(self, "_record_damage")
	)
	_enemies.append(
		Fixtures.make_enemy(self, _index, 1, MAP_A, Vector2(0.2, 0.2))
	)
	_controller.visual_cells[0].queue_free()
	_controller.visual_cells[2].queue_free()
	_controller._apply_field_tick()
	_controller._apply_field_tick()
	assert(
		_damage_count == 2,
		"early cell destruction must not change the damage range"
	)
	var diag: Dictionary = _controller.fire_wall_controller_diagnostics()
	assert(
		int(diag.get("visual_cell_count", 0)) == 4
		and int(diag.get("visual_cell_exact_test_count", 0)) == 0,
		"freed cells must not affect controller damage or exact tests"
	)
	_cleanup_world()


func _natural_expiry_case() -> void:
	_fresh_world()
	_controller = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 2.0, "tick_interval_ms": 1000},
		"q2c:lifecycle:expiry",
		null,
		Callable(self, "_record_damage")
	)
	_enemies.append(
		Fixtures.make_enemy(self, _index, 1, MAP_A, Vector2(0.2, 0.2))
	)
	for _frame: int in range(4):
		_controller._physics_process(1.0)
	var diag: Dictionary = _controller.fire_wall_controller_diagnostics()
	assert(
		bool(diag.get("expired", false)),
		"controller must report expired"
	)
	var before := _damage_count
	_controller._physics_process(1.0)
	assert(
		_damage_count == before,
		"no damage after natural expiry"
	)
	_cleanup_world()
	await get_tree().process_frame


func _manual_cancel_case() -> void:
	_fresh_world()
	_controller = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:lifecycle:cancel",
		null,
		Callable(self, "_record_damage")
	)
	_controller.cancel()
	assert(
		bool(
			_controller.fire_wall_controller_diagnostics().get(
				"cancelled", false
			)
		),
		"manual cancel must be recorded"
	)
	var cells := _controller.visual_cells.duplicate()
	_cleanup_world()
	await get_tree().process_frame
	for raw_cell: Variant in cells:
		assert(
			not is_instance_valid(raw_cell),
			"controller teardown must free every visual cell (no orphans)"
		)


func _caster_death_case() -> void:
	_fresh_world()
	_caster = Node2D.new()
	_caster.name = "DoomedQ2CCaster"
	add_child(_caster)
	_controller = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:lifecycle:caster",
		_caster,
		Callable(self, "_record_damage")
	)
	_enemies.append(
		Fixtures.make_enemy(self, _index, 1, MAP_A, Vector2(0.2, 0.2))
	)
	_caster.queue_free()
	_controller._apply_field_tick()
	assert(
		_damage_count == 1,
		"legacy contract: caster death does not cancel its fire wall"
	)
	_cleanup_world()


func _map_generation_clear_case() -> void:
	_fresh_world()
	_controller = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:lifecycle:clear",
		null,
		Callable(self, "_record_damage")
	)
	_enemies.append(
		Fixtures.make_enemy(self, _index, 1, MAP_A, Vector2(0.2, 0.2))
	)
	# Generation / map transition frees the zone_content cells.
	for cell: GroundSkillVisualCell in _controller.visual_cells:
		cell.queue_free()
	_controller._apply_field_tick()
	assert(
		_damage_count == 1,
		"cells freed by a generation change must not stop controller damage"
	)
	_cleanup_world()


func _fresh_world() -> void:
	_cleanup_world()
	_index = SpatialIndexScript.new()
	_controller = null
	_enemies.clear()
	_damage_count = 0


func _cleanup_world() -> void:
	if _controller != null and is_instance_valid(_controller):
		_controller.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if _caster != null and is_instance_valid(_caster):
		_caster.queue_free()
		_caster = null
	_enemies.clear()


func _cleanup() -> void:
	_cleanup_world()


func _record_damage(enemy: EnemyActor, raw_power: int) -> void:
	_damage_count += 1
	enemy.take_damage(raw_power, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
