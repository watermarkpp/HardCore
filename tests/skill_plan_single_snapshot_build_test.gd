extends Node

## Q3-A: one release builds exactly one canonical Snapshot V2; rebuilding the
## canonical plan for the same frozen input yields the same snapshot id and a
## stable plan hash (no drift, no duplicate snapshot construction).

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 2026-09-13 user request 5 moved the canonical fire_wall footprint from
	# 2x2 to 3x3 (manifest conflict_note; SOT geometry width_tiles/height_tiles
	# 3, status project_canonical). The fixture freezes the canonical 3x3.
	var frozen_cells: Array[Vector2i] = []
	for offset_x: int in range(3):
		for offset_y: int in range(3):
			frozen_cells.append(Vector2i(offset_x, offset_y))
	var snapshot := Fixtures.cell_union_snapshot(
		self,
		"wizard.fire_wall",
		"q3a:snapshot:1",
		1,
		Vector2(0, 0),
		frozen_cells
	)
	var request := Fixtures.make_request(
		"wizard.fire_wall",
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true, Vector2i.ZERO),
		Fixtures.default_resource_context(500)
	)
	var context := Fixtures.canonical_context(
		1,
		"q3a:snapshot:1",
		7,
		8,
		snapshot
	)
	var plan_a: Dictionary = Router.build_canonical_plan(request, context)
	var plan_b: Dictionary = Router.build_canonical_plan(request, context)
	assert(
		str(plan_a.get("snapshot_id", "")) == str(snapshot.get("snapshot_id", "")),
		"plan must carry the single frozen snapshot id"
	)
	assert(
		str(plan_a.get("snapshot_id", "")) == str(plan_b.get("snapshot_id", "")),
		"rebuilding for the same input must not create a new snapshot"
	)
	assert(
		str(plan_a.get("plan_hash", "")) == str(plan_b.get("plan_hash", "")),
		"plan hash must be stable across identical builds"
	)
	var cells_a: Array = plan_a.get("geometry_cells", [])
	assert(
		cells_a.size() == 9,
		"canonical plan must carry the frozen 3x3 cells exactly once"
	)
	var plan_hash_before := str(plan_a.get("plan_hash", ""))
	var verify: Dictionary = Plan.verify_immutable(plan_a, plan_hash_before)
	assert(
		bool(verify.get("valid", false)),
		"plan must verify immutable against its own hash"
	)
	await get_tree().process_frame
	print(
		"SKILL_PLAN_SINGLE_SNAPSHOT_BUILD_PASS snapshot=%s cells=9"
		% str(plan_a.get("snapshot_id", ""))
	)
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
