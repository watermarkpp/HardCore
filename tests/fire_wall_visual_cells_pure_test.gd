extends Node

## Q2-C: GroundSkillVisualCell instances are pure presentation - no enemy
## query, no damage callback, no claim, no damage tick, no exact test.

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
const GroundSkillVisualCell := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)

const MAP_A := 11003
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controller: FireWallFieldController
var _caster: Node2D
var _enemies: Array[EnemyActor] = []
var _damage_log: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_index = SpatialIndexScript.new()
	_caster = Node2D.new()
	_caster.name = "Q2CCaster"
	add_child(_caster)
	_controller = Fixtures.make_controller(
		self,
		_index,
		MAP_A,
		Vector2(0, 0),
		{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
		"q2c:pure_cells:1",
		_caster,
		Callable(self, "_record_damage")
	)
	for i: int in range(2):
		_enemies.append(
			Fixtures.make_enemy(
				self,
				_index,
				i + 1,
				MAP_A,
				Vector2(0.2 + float(i) * 0.3, 0.2)
			)
		)
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_controller._apply_field_tick()
	_controller._apply_field_tick()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	for cell: GroundSkillVisualCell in _controller.visual_cells:
		assert(cell.visual_only, "cell must be marked visual_only")
		assert(
			cell.damage_owner == GroundSkillVisualCell.DAMAGE_OWNER,
			"cell damage owner must be the fire wall controller"
		)
		assert(
			not cell.runtime_target_filter.is_valid(),
			"cell must not carry a per-cell damage filter"
		)
		assert(
			cell.cell_index >= 0
			and not cell.canonical_snapshot_id.is_empty(),
			"cell must carry its index and the canonical snapshot id"
		)
		var cell_diag: Dictionary = cell.runtime_diagnostics()
		assert(
			int(cell_diag.get("enemy_group_queries", -1)) == 0
			and int(cell_diag.get("damage_ticks", -1)) == 0,
			"cell must never query enemies or apply damage"
		)
	var controller_diag: Dictionary = (
		_controller.fire_wall_controller_diagnostics()
	)
	assert(
		int(controller_diag.get("visual_cell_exact_test_count", -1)) == 0,
		"cells must never run exact tests"
	)
	assert(
		_damage_log.size() == 2 * 2,
		"damage must come from the controller only (2 ticks x 2 inside enemies)"
	)
	# Claim ownership: after a controller tick the shared claim table key must
	# be owned by the controller instance, not by a cell.
	var claim_keys: Array = GroundSkillEffect._runtime_tick_claims.keys()
	assert(not claim_keys.is_empty(), "controller claim must be recorded")
	for key: Variant in claim_keys:
		var claim: Dictionary = GroundSkillEffect._runtime_tick_claims.get(key, {})
		assert(
			int(claim.get("owner_effect_id", 0))
			== _controller.get_instance_id(),
			"claim owner must be the FireWallFieldController"
		)
	var cell_count := _controller.visual_cells.size()
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_VISUAL_CELLS_PURE_PASS cells=%d" % cell_count)
	get_tree().quit(0)


func _cleanup() -> void:
	if _controller != null and is_instance_valid(_controller):
		_controller.queue_free()
	for enemy: EnemyActor in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if _caster != null and is_instance_valid(_caster):
		_caster.queue_free()


func _record_damage(enemy: EnemyActor, raw_power: int) -> void:
	_damage_log.append(enemy.get_instance_id())
	enemy.take_damage(raw_power, null)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
