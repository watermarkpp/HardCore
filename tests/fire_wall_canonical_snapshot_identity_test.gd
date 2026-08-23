extends Node

## Q2-C canonical snapshot identity: one canonical 2x2 union Snapshot V2 per
## release; all 4 visual cells share its id and hold only display metadata.

const Fixtures := preload(
	"res://tests/helpers/fire_wall_controller_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const FireWallFieldController := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const GroundSkillVisualCell := preload(
	"res://scripts/ground_skill_visual_cell.gd"
)

const MAP_A := 11014
const SKILL_ID := "wizard.fire_wall"

var _index: SpatialIndexScript
var _controllers: Array[FireWallFieldController] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	_controllers.append(
		Fixtures.make_controller(
			self,
			_index,
			MAP_A,
			Vector2(0, 0),
			{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
			"q2c:identity:release_a",
			null,
			Callable(self, "_noop_damage")
		)
	)
	_controllers.append(
		Fixtures.make_controller(
			self,
			_index,
			MAP_A,
			Vector2(4, 0),
			{"raw_power": 3, "duration_seconds": 60.0, "tick_interval_ms": 1000},
			"q2c:identity:release_b",
			null,
			Callable(self, "_noop_damage")
		)
	)
	var first := _controllers[0]
	var first_snapshot: Dictionary = (
		first.get("_canonical_snapshot") as Dictionary
	)
	var first_context: Dictionary = (
		first.get("_snapshot_validation_context") as Dictionary
	)
	var strict := Snapshot.validate_for_consumer(
		first_snapshot,
		first_context,
		Snapshot.VALIDATION_STRICT_V2
	)
	assert(
		bool(strict.get("valid", false)),
		"controller canonical snapshot must validate STRICT_V2: %s"
		% str(strict.get("reason", ""))
	)
	assert(
		int(first_snapshot.get("schema_version", 0)) == Snapshot.SCHEMA_VERSION
		and str(first_snapshot.get("coordinate_space", ""))
			== Snapshot.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
		"canonical snapshot must be V2 runtime-map absolute ground GU"
	)
	assert(
		str(first_snapshot.get("shape_type", ""))
			== Snapshot.SHAPE_CELL_UNION,
		"canonical snapshot must be the formal 2x2 cell union"
	)
	var first_id := str(
		first.fire_wall_controller_diagnostics().get("snapshot_id", "")
	)
	var second_id := str(
		_controllers[1].fire_wall_controller_diagnostics().get(
			"snapshot_id", ""
		)
	)
	assert(
		not first_id.is_empty() and first_id != second_id,
		"each release must own a unique canonical snapshot id"
	)
	for controller: FireWallFieldController in _controllers:
		var expected_id := str(
			controller.fire_wall_controller_diagnostics().get(
				"snapshot_id", ""
			)
		)
		assert(
			controller.visual_cells.size() == 4,
			"formal fire wall must keep exactly 4 visual cells"
		)
		var offsets: Dictionary = {}
		for cell: GroundSkillVisualCell in controller.visual_cells:
			assert(
				cell.cell_index >= 0
				and cell.cell_index <= 3,
				"cell_index must be 0..3"
			)
			assert(
				cell.canonical_snapshot_id == expected_id,
				"all cells must share the controller canonical snapshot id"
			)
			assert(
				cell.visual_only
				and cell.damage_owner == GroundSkillVisualCell.DAMAGE_OWNER,
				"cells must be pure visual"
			)
			assert(
				not cell.runtime_target_filter.is_valid(),
				"cells must not carry per-cell damage geometry"
			)
			offsets[cell.cell_index] = true
		assert(offsets.size() == 4, "cell_index must cover 0,1,2,3")
		controller._apply_field_tick()
		var diag: Dictionary = controller.fire_wall_controller_diagnostics()
		assert(
			int(diag.get("visual_cell_exact_test_count", -1)) == 0
			and int(diag.get("snapshot_rebuild_count", -1)) == 0,
			"cells must never exact-test and the snapshot must never rebuild"
		)
	_cleanup()
	await get_tree().process_frame
	print("FIRE_WALL_CANONICAL_SNAPSHOT_IDENTITY_PASS controllers=2")
	get_tree().quit(0)


func _cleanup() -> void:
	for controller: FireWallFieldController in _controllers:
		if is_instance_valid(controller):
			controller.queue_free()


func _noop_damage(_enemy: EnemyActor, _raw_power: int) -> void:
	pass


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)
