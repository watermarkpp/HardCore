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
	var snapshot := Fixtures.cell_union_snapshot(
		self,
		"wizard.fire_wall",
		"q3a:snapshot:1",
		1,
		Vector2(0, 0),
		[Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]
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
	var plan_a: Dictionary = Plan.build_plan(request, context)
	var plan_b: Dictionary = Plan.build_plan(request, context)
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
		cells_a.size() == 4,
		"canonical plan must carry the frozen 2x2 cells exactly once"
	)
	var plan_hash_before := str(plan_a.get("plan_hash", ""))
	var verify: Dictionary = Plan.verify_immutable(plan_a, plan_hash_before)
	assert(
		bool(verify.get("valid", false)),
		"plan must verify immutable against its own hash"
	)
	await get_tree().process_frame
	print(
		"SKILL_PLAN_SINGLE_SNAPSHOT_BUILD_PASS snapshot=%s cells=4"
		% str(plan_a.get("snapshot_id", ""))
	)
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
