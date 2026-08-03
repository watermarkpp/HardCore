extends Node


func _ready() -> void:
	var package := WizardProfessionPackage.new()
	assert(package.is_valid())
	assert(package.identity().package_id == "profession.package.wizard.v1")
	assert(package.profession_id == "wizard" and package.display_name == "法师")
	assert(package.supports_gender("男") and package.supports_gender("male"))
	assert(not package.supports_gender("女") and not package.supports_gender("female"))
	assert(package.skill_ids().size() == 14)
	assert(CasterProfessionRegistry.create("法师").package_id == package.package_id)
	assert(CasterProfessionRegistry.create("warrior") == null)
	assert(CasterProfessionRegistry.integration_descriptors().size() == 2)
	assert(package.manifest.runtime.training_policy.status == "project_adapter_C_candidate")
	for skill_id: String in package.skill_ids():
		var definition := package.skill_definition(skill_id)
		assert(definition.levels.size() == 4)
		assert(definition.visual_profile.status == "formal_primary_client_animation")
		assert(definition.visual_profile.animation_contract == "caster_skill_animation.v1")
		assert(definition.visual_profile.source_priority.tier == "primary")
		for record: Dictionary in definition.levels:
			assert(record.source_trace.mana_cost.original_path == "Server.MirDB")
	var level_40_stats := package.stats_for_level(40)
	var service_stats := GameData.service_profession_stats("法师", 40)
	assert(level_40_stats.max_hp == service_stats.max_hp)
	assert(level_40_stats.max_mp == service_stats.max_mp)
	assert(level_40_stats.formula_id == "wizard.server_setup.hp_mp.v1")

	package.reset_character(1)
	var early_learning := package.learn_skill("wizard.fireball")
	assert(not early_learning.learned and early_learning.reason == "character_level")
	package.reset_character(40)
	assert(not package.learn_skill("wizard.fireball", false).learned)
	assert(package.learn_skill("wizard.fireball").learned)
	assert(package.add_training_points("wizard.fireball", 499).skill_level == 0)
	assert(package.add_training_points("wizard.fireball", 100000).skill_level == 3)
	assert(package.learning_status("wizard.fireball").reason == "maximum_skill_level")
	assert(package.skill_level_record("wizard.fireball", 3).source_trace.mana_cost.original_path == "Server.MirDB")

	var all_skills := {}
	for skill_id: String in package.skill_ids():
		all_skills[skill_id] = 3
	assert(package.load_skill_state(all_skills).loaded_count == 14)
	var caster := PlayerCharacter.new()
	caster.global_position = Vector2.ZERO
	for skill_id: String in package.skill_ids():
		package.restore_mana(100000)
		var target := EnemyActor.new()
		target.max_hp = 10000
		target.current_hp = 10000
		target.display_name = "wizard package target"
		target.global_position = Vector2(96, 0)
		var plan_context := _plan_context()
		if skill_id == "wizard.holy_word":
			plan_context.target_is_undead = true
		var cast_result := package.cast(skill_id, plan_context, {
			"parent": self,
			"caster": caster,
			"primary_target": target,
			"affected_targets": [target],
			"affected_allies": [caster],
			"origin": caster.global_position,
			"target_position": target.global_position,
			"direction": Vector2.RIGHT,
			"teleport_destination": Vector2(144, 48),
			"spatial_test_adapter_id": (
				CasterSkillRuntime.NON_PRODUCTION_SPATIAL_ADAPTER_ID
			),
		})
		assert(cast_result.accepted, "%s rejected: %s" % [skill_id, cast_result.get("reason", "")])
		assert(cast_result.package_contract == "caster_profession_package.v1")
		assert(cast_result.plan.profession_package_id == package.package_id)
		assert(cast_result.plan.level_source_trace.mana_cost.original_path == "Server.MirDB")
		assert(cast_result.mana_spent == int(package.skill_level_record(skill_id, 3).manaCost))
		assert(cast_result.training_gain == 1)
		assert(cast_result.cooldown_seconds >= 0.0)
		assert(cast_result.execution.spawned_count >= 1)
		for node: Node2D in cast_result.execution.nodes:
			node.free()
		if is_instance_valid(target):
			target.free()

	var cooldown_block := package.cast("wizard.fireball", _plan_context(), {})
	assert(not cooldown_block.accepted and cooldown_block.reason == "cooldown")
	package.tick(10.0)
	package.current_mana = 0
	var mana_block := package.cast("wizard.fireball", _plan_context(), {})
	assert(not mana_block.accepted and mana_block.reason == "insufficient_mana")
	var snapshot := package.snapshot()
	assert(snapshot.state_contract == "caster_profession_state.v1")
	assert(snapshot.profession_id == "wizard" and snapshot.gender == "male")
	caster.free()
	print("WIZARD_PROFESSION_PACKAGE_PASS: male-only growth, 14 skills, learning, mana, cooldown and actual casts are self-contained")
	get_tree().quit(0)


func _plan_context() -> Dictionary:
	return {
		"caster_level": 40,
		"target_level": 20,
		"target_max_hp": 10000,
		"magic_stat_roll": 30,
		"magic_power_roll": 20,
		"def_power_roll": 5,
		"outer_random": 0,
		"coin_random": 0,
		"level_random": 50,
		"hp_random": 0,
		"random_0_to_19": 0,
		"random_0_or_1": 1,
		"random_0_to_10": 0,
		"random_0_to_99": 0,
		"owner_slave_count": 0,
	}
