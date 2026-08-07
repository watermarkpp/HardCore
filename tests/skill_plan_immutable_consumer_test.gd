extends Node

## Q3-A: consumers (CasterSkillRuntime adapter, descriptor consumers) must not
## modify the canonical plan - plan hash and snapshot hash stay identical.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var snapshot := Fixtures.cell_union_snapshot(
		self,
		"wizard.fire_wall",
		"q3a:immutable:1",
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
	var plan: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(1, "q3a:immutable:1", 7, 8, snapshot)
	)
	var hash_before := str(plan.get("plan_hash", ""))
	var snapshot_hash_before := "%d" % hash(
		Plan._canonicalize(plan.get("canonical_snapshot", {}))
	)
	# Consume through the CasterSkillRuntime canonical-plan adapter.
	var nodes: Array[Node2D] = CasterRuntime.create_cast_nodes_from_canonical_plan(
		plan,
		Vector2.ZERO,
		Vector2.DOWN,
		Color.WHITE,
		null,
		null,
		1,
		1
	)
	assert(
		not nodes.is_empty(),
		"adapter must create nodes from the canonical plan"
	)
	for node: Node2D in nodes:
		if node is GroundSkillEffect:
			assert(
				str((node as GroundSkillEffect).release_id)
				== str(plan.get("release_id", "")),
				"consumed nodes must reference the plan release id"
			)
	# Descriptor consumers read but never write the plan.
	var descriptor_copy: Dictionary = plan.get(
		"ground_effect_descriptors",
		[]
	)[0]
	assert(
		str(descriptor_copy.get("kind", "")) == "ground_effect",
		"descriptor must be readable"
	)
	var verify: Dictionary = Plan.verify_immutable(plan, hash_before)
	assert(
		bool(verify.get("valid", false)),
		"plan hash must be unchanged after consumption"
	)
	assert(
		str(plan.get("plan_hash", "")) == hash_before,
		"plan_hash field must be unchanged"
	)
	var snapshot_hash_after := "%d" % hash(
		Plan._canonicalize(plan.get("canonical_snapshot", {}))
	)
	assert(
		snapshot_hash_after == snapshot_hash_before,
		"snapshot hash must be unchanged"
	)
	for node: Node2D in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	print("SKILL_PLAN_IMMUTABLE_CONSUMER_PASS")
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
