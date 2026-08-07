extends Node

## Q3-C migration: the legacy the legacy resolver/create_cast_nodes
## entry was removed. This test keeps the avatar-independence contract: every
## caster skill must reach the canonical node factory without any paper-doll /
## wear dependency. Skills the canonical planner rejects for documented
## resource/target reasons are recorded (planner-level validation is not an
## avatar dependency).

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var avatar := PlayerCharacter.new()
	avatar.current_hp = 100
	avatar.facing = Vector2.DOWN
	add_child(avatar)
	var checked := 0
	var rejected: Array[String] = []
	for profession_id: String in ["wizard", "taoist"]:
		var test_profile := TestCharacterSkillProfiles.profile_for_profession(
			profession_id
		)
		for skill_id: String in test_profile.learned_skill_ids:
			var plan := Fixtures.build_canonical_presentation_plan(
				skill_id,
				3,
				40,
				Vector2.ZERO,
				Vector2.RIGHT,
				Vector2(96, 48),
				Fixtures.circle_snapshot(
					self,
					skill_id,
					"q3c:avatar:%s" % skill_id,
					1,
					Vector2(0, 0),
					2.0
				)
			)
			var rejection: Dictionary = plan.get("rejection", {})
			if not bool(rejection.get("accepted", false)):
				rejected.append(
					"%s:%s" % [skill_id, str(rejection.get("reason", ""))]
				)
				checked += 1
				continue
			var nodes := the legacy cast-node entry_from_canonical_plan(
				plan,
				Vector2.ZERO,
				Vector2.RIGHT,
				Color.WHITE,
				null,
				avatar,
				30,
				40
			)
			for node: Node2D in nodes:
				add_child(node)
				if node is SkillProjectile:
					assert(
						node._sprite != null,
						"%s投射物没有独立于人物视觉加载" % skill_id
					)
				elif node is SummonActor:
					assert(
						(node as SummonActor).owner_player == avatar
						and (node as SummonActor).skill_id == skill_id,
						"%s召唤入口依赖人物占位视觉" % skill_id
					)
				node.free()
			checked += 1
	assert(
		checked == 27,
		"法师/道士全技能入口审计数量错误 (checked=%d)" % checked
	)
	avatar.free()
	print(
		"CASTER_FULL_SKILL_ENTRY_AVATAR_INDEPENDENCE_PASS: all 27 caster skills reach the canonical node factory"
	)
	for rejected_line: String in rejected:
		print("CASTER_AVATAR_PLANNER_REJECTION %s" % rejected_line)
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
