extends Node


func _ready() -> void:
	var package := TaoistProfessionPackage.new()
	assert(package.is_valid())
	assert(package.identity().package_id == "profession.package.taoist.v1")
	assert(package.profession_id == "taoist" and package.display_name == "道士")
	assert(package.supports_gender("男") and not package.supports_gender("女"))
	assert(package.skill_ids().size() == 13)
	assert(package.manifest.runtime.training_policy.status == "project_adapter_C_candidate")
	for skill_id: String in package.skill_ids():
		var definition := package.skill_definition(skill_id)
		assert(definition.levels.size() == 4)
		if skill_id == "taoist.spiritual_warfare":
			assert(definition.visual_profile.status == "no_runtime_visual")
		else:
			assert(definition.visual_profile.status == "formal_primary_client_pixel")
			assert(definition.visual_profile.source_priority.tier == "primary")
		for record: Dictionary in definition.levels:
			assert(record.source_trace.mana_cost.original_path == "Server.MirDB")
	var level_40_stats := package.stats_for_level(40)
	var service_stats := GameData.service_profession_stats("道士", 40)
	assert(level_40_stats.max_hp == service_stats.max_hp)
	assert(level_40_stats.max_mp == service_stats.max_mp)
	assert(level_40_stats.formula_id == "taoist.server_setup.hp_mp.v1")

	package.reset_character(40)
	assert(package.learn_skill("taoist.healing").learned)
	assert(package.add_training_points("taoist.healing", 100000).skill_level == 3)
	var all_skills := {}
	for skill_id: String in package.skill_ids():
		all_skills[skill_id] = 3
	assert(package.load_skill_state(all_skills).loaded_count == 13)
	assert(package.load_skill_state({"wizard.fireball": 3}).rejected.size() == 1)
	assert(package.load_skill_state(all_skills).loaded_count == 13)

	var no_material := package.cast("taoist.soul_fire_talisman", _plan_context(), {})
	assert(not no_material.accepted and no_material.reason == "insufficient_material")
	assert(no_material.material_id == "amulet")
	package.grant_material("amulet", 100)
	package.grant_material("poison_powder", 100)
	var caster := PlayerCharacter.new()
	caster.global_position = Vector2.ZERO
	for skill_id: String in package.skill_ids():
		if skill_id == "taoist.spiritual_warfare":
			var passive := package.cast(skill_id, _plan_context(), {})
			assert(not passive.accepted and passive.reason == "passive_skill")
			continue
		package.restore_mana(100000)
		var target := EnemyActor.new()
		target.max_hp = 10000
		target.current_hp = 10000
		target.display_name = "taoist package target"
		target.global_position = Vector2(96, 0)
		var cast_result := package.cast(skill_id, _plan_context(), {
			"parent": self,
			"caster": caster,
			"primary_target": target,
			"affected_targets": [target],
			"affected_allies": [caster],
			"origin": caster.global_position,
			"target_position": target.global_position,
			"direction": Vector2.RIGHT,
			"defense_bonus": 5,
			"spiritual_power": 30,
			"owner_level": 40,
		})
		assert(cast_result.accepted, "%s rejected: %s" % [skill_id, cast_result.get("reason", "")])
		assert(cast_result.package_contract == "caster_profession_package.v1")
		assert(cast_result.plan.profession_package_id == package.package_id)
		assert(cast_result.plan.level_source_trace.mana_cost.original_path == "Server.MirDB")
		assert(cast_result.mana_spent == int(package.skill_level_record(skill_id, 3).manaCost))
		assert(cast_result.training_gain == 1)
		assert(cast_result.execution.spawned_count >= 1)
		if skill_id.begins_with("taoist.summon_"):
			assert(cast_result.execution.nodes[0] is SummonActor)
			assert(cast_result.execution.nodes[0].owner_player == caster)
		for node: Node2D in cast_result.execution.nodes:
			node.free()
		if is_instance_valid(target):
			target.free()

	var cooldown_block := package.cast("taoist.healing", _plan_context(), {})
	assert(not cooldown_block.accepted and cooldown_block.reason == "cooldown")
	package.tick(10.0)
	package.restore_mana(100000)
	var red_poison_target := EnemyActor.new()
	red_poison_target.max_hp = 100
	red_poison_target.current_hp = 100
	var red_context := _plan_context()
	red_context.poison_type = "red"
	var red_poison := package.cast("taoist.poison", red_context, {
		"parent": self,
		"caster": caster,
		"primary_target": red_poison_target,
		"operation_adapters": {
			"poison_armor": Callable(self, "_apply_armor_poison"),
		},
	})
	assert(red_poison.accepted and red_poison_target.get_meta("armor_poison_applied", false))
	for node: Node2D in red_poison.execution.nodes:
		node.free()
	red_poison_target.free()
	var snapshot := package.snapshot()
	assert(snapshot.state_contract == "caster_profession_state.v1")
	assert(snapshot.profession_id == "taoist" and snapshot.gender == "male")
	assert(int(snapshot.materials.amulet) < 100 and int(snapshot.materials.poison_powder) < 100)
	caster.free()
	print("TAOIST_PROFESSION_PACKAGE_PASS: male-only growth, 13 skills, mana, materials, statuses and summons are self-contained")
	get_tree().quit(0)


func _apply_armor_poison(_plan: Dictionary, context: Dictionary) -> void:
	var target := context.get("primary_target") as Node2D
	if target != null:
		target.set_meta("armor_poison_applied", true)


func _plan_context() -> Dictionary:
	return {
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"target_max_hp": 10000,
		"spiritual_stat_roll": 30,
		"magic_power_roll": 20,
		"def_power_roll": 5,
		"random_0_to_5": 0,
		"anti_poison_random": 0,
		"owner_slave_count": 0,
	}
