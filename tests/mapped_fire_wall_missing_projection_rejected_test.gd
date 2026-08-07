extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")

const MAP_ID := 248

var _index: SpatialIndexScript
var _enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	_index = SpatialIndexScript.new()
	var center_abs := Vector2(130.0, 130.0)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		center_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	var context := Fixtures.absolute_context(
		MAP_ID,
		center_abs,
		Fixtures.DESIGN_256
	)
	var cells: Array[Vector2i] = [Vector2i(130, 130)]
	var snapshot := SpellGeometry.create_exact_cell_union_release_snapshot(
		"wizard.fire_wall",
		"p01:fw:1",
		center_abs,
		cells,
		context
	)
	var controller := FireWallFieldController.new()
	controller.setup_fire_wall_field(
		null,
		"wizard.fire_wall",
		{"raw_power": 11, "radius_gu": 0.5, "duration_seconds": 1.0, "tick_interval_ms": 1000},
		[Fixtures.ground_to_screen(Fixtures.DESIGN_256).call(center_abs)],
		cells,
		[],
		Callable(),
		Callable(),  # screen_to_ground MISSING
		"p01:fw:1",
		snapshot,
		context,
		_index,
		MAP_ID
	)
	add_child(controller)
	controller.set_physics_process(false)
	var converted: Vector2 = controller._runtime_screen_to_ground_position(
		_enemy.global_position
	)
	assert(
		not converted.is_finite(),
		"mapped FireWall target conversion must never fake absolute from delta"
	)
	controller._apply_field_tick()
	var diag: Dictionary = controller.fire_wall_controller_diagnostics()
	assert(
		int(diag.get("controller_exact_test_count", 0)) == 0,
		"exact phase must fail closed without projection"
	)
	assert(
		int(diag.get("damage_application_count", 0)) == 0,
		"no damage may be applied through a fake exact phase"
	)
	assert(
		int(diag.get("missing_projection_rejection_count", 0)) >= 1,
		"FireWall must record the projection rejection"
	)
	assert(
		str(diag.get("rejection_reason", ""))
		== str(GroundUnit.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION),
		"FireWall must distinguish missing_runtime_projection from spatial_index_unavailable"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"MAPPED_FIRE_WALL_MISSING_PROJECTION_REJECTED_PASS exact=%d damage=%d"
		% [
			int(diag.get("controller_exact_test_count", 0)),
			int(diag.get("damage_application_count", 0)),
		]
	)
	get_tree().quit(0)


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
