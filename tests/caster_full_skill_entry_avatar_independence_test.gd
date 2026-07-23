extends Node


func _ready() -> void:
	var avatar := PlayerCharacter.new()
	avatar.current_hp = 100
	avatar.facing = Vector2.DOWN
	var checked := 0
	for profession_id: String in ["wizard", "taoist"]:
		var test_profile := TestCharacterSkillProfiles.profile_for_profession(profession_id)
		for skill_id: String in test_profile.learned_skill_ids:
			var context := {
				"skill_level": 3,
				"caster_level": 40,
				"owner_level": 40,
				"target_level": 20,
				"target_max_hp": 500,
				"magic_stat_roll": 30,
				"spiritual_stat_roll": 30,
				"outer_random": 0,
				"coin_random": 0,
				"level_random": 50,
				"hp_random": 0,
				"random_0_to_19": 0,
				"random_0_or_1": 1,
				"random_0_to_10": 0,
				"random_0_to_99": 0,
				"random_0_to_5": 0,
				"anti_poison_random": 0,
				"owner_slave_count": 0,
				"target_is_undead": skill_id == "wizard.holy_word",
			}
			var plan := CasterSkillRuntime.resolve(skill_id, context)
			assert(plan.runtime_contract == "caster_skill_runtime.v1", "%s运行时入口缺失" % skill_id)
			assert(plan.get("failure_reason", "") != "missing_runtime_operation", "%s没有技能运行时操作" % skill_id)
			if skill_id == "taoist.spiritual_warfare":
				assert(not plan.castable, "被动技能不应生成主动施法节点")
				checked += 1
				continue
			var nodes := CasterSkillRuntime.create_cast_nodes(
				plan,
				Vector2.ZERO,
				Vector2(96, 48),
				Vector2.RIGHT,
				Color.WHITE,
				null,
				avatar,
				30,
				40
			)
			var expected_count := 5 if skill_id == "wizard.fire_wall" else 1
			assert(nodes.size() == expected_count, "%s因人物视觉未装配而无法进入技能节点工厂" % skill_id)
			for node: Node2D in nodes:
				add_child(node)
				if node is SkillProjectile:
					assert(node._sprite != null, "%s投射物没有独立于人物视觉加载" % skill_id)
				elif node is SummonActor:
					assert(node.owner_player == avatar and node.skill_id == skill_id, "%s召唤入口依赖人物占位视觉" % skill_id)
				node.free()
			checked += 1
	assert(checked == 27, "法师/道士全技能入口审计数量错误")
	avatar.free()
	print("CASTER_FULL_SKILL_ENTRY_AVATAR_INDEPENDENCE_PASS: all 27 caster skills enter runtime without paper-doll/wear dependency")
	get_tree().quit(0)
