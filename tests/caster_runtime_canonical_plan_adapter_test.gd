extends Node

## Q3-A: the canonical node entry create_cast_nodes_from_canonical_plan consumes the
## plan's descriptors and snapshot without re-resolving, re-quoting or
## replanning, and never mutates the plan.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var projectile_nodes := _consume("wizard.fireball", "projectile")
	assert(
		projectile_nodes.size() == 1,
		"projectile descriptor must create exactly one projectile"
	)
	var ground_nodes := _consume("wizard.fire_wall", "ground")
	assert(
		not ground_nodes.is_empty(),
		"ground descriptor must create ground effect nodes"
	)
	var visual_nodes := _consume("wizard.lightning", "visual")
	assert(
		not visual_nodes.is_empty(),
		"presentation action must create a visual node"
	)
	await get_tree().process_frame
	print(
		"CASTER_RUNTIME_CANONICAL_PLAN_ADAPTER_PASS projectile=%d ground=%d visual=%d"
		% [projectile_nodes.size(), ground_nodes.size(), visual_nodes.size()]
	)
	get_tree().quit(0)


func _consume(skill_id: String, expected_kind: String) -> Array[Node2D]:
	var snapshot := Fixtures.circle_snapshot(
		self,
		skill_id,
		"q3a:adapter:%s" % skill_id,
		1,
		Vector2(0, 0),
		2.0
	)
	var request := Fixtures.make_request(
		skill_id,
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.default_resource_context(500)
	)
	var plan: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(
			1,
			"q3a:adapter:%s" % skill_id,
			7,
			8,
			snapshot
		)
	)
	var hash_before := str(plan.get("plan_hash", ""))
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
		str(plan.get("plan_hash", "")) == hash_before,
		"adapter must not mutate the plan"
	)
	for node: Node2D in nodes:
		if node is SkillProjectile:
			assert(
				str((node as SkillProjectile).release_id)
				== str(plan.get("release_id", "")),
				"projectile must use the plan release id"
			)
	for node: Node2D in nodes:
		if is_instance_valid(node):
			node.queue_free()
	return nodes


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
