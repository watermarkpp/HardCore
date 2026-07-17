extends Node


func _ready() -> void:
	var caster_ids := PackedStringArray()
	for skill_id: String in ProfessionRules.SKILL_CATALOG:
		if skill_id.begins_with("wizard.") or skill_id.begins_with("taoist."):
			caster_ids.append(skill_id)
	assert(caster_ids.size() == 27)
	var summon_owner := PlayerCharacter.new()
	for skill_id: String in caster_ids:
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
		}
		if skill_id == "wizard.holy_word":
			context.target_is_undead = true
		var plan := CasterSkillRuntime.resolve(skill_id, context)
		assert(plan.runtime_contract == "caster_skill_runtime.v1", "%s lacks runtime contract" % skill_id)
		assert(not str(plan.get("operation", "")).is_empty(), "%s lacks runtime operation" % skill_id)
		assert(plan.get("failure_reason", "") != "missing_runtime_operation", "%s is not executable" % skill_id)
		if skill_id == "taoist.spiritual_warfare":
			assert(not plan.castable and plan.visual.status == "no_runtime_visual")
		else:
			assert(plan.visual.status == "formal_primary_client_pixel", "%s lacks formal visual binding" % skill_id)
		var cast_nodes := CasterSkillRuntime.create_cast_nodes(
			plan,
			Vector2.ZERO,
			Vector2(96, 48),
			Vector2.RIGHT,
			Color.WHITE,
			null,
			summon_owner,
			30,
			40
		)
		var expected_node_count := 0 if skill_id == "taoist.spiritual_warfare" else (5 if skill_id == "wizard.fire_wall" else 1)
		assert(cast_nodes.size() == expected_node_count, "%s cast factory returned %d nodes" % [skill_id, cast_nodes.size()])
		for node: Node2D in cast_nodes:
			add_child(node)
			if node is SkillProjectile:
				assert(node._sprite != null, "%s projectile did not load formal pixels" % skill_id)
			elif node is GroundSkillEffect:
				assert(node._sprite != null, "%s ground effect did not load formal pixels" % skill_id)
			elif node is SummonActor:
				assert(node._sprite != null and node.owner_player == summon_owner, "%s summon factory is incomplete" % skill_id)
			elif node is CasterSkillVisualEffect:
				assert(node.visual_loaded, "%s runtime visual did not load formal pixels" % skill_id)
			node.free()
	summon_owner.free()

	var fire_wall := CasterSkillRuntime.resolve("wizard.fire_wall", {
		"skill_level": 3, "magic_stat_roll": 30, "cell_size": 48,
	})
	assert(fire_wall.operation == "ground_dot" and fire_wall.execution_shape == "five_cell_cross")
	assert(fire_wall.duration_seconds == 28 and fire_wall.tick_interval_seconds == 3.0)
	var fire_cells := CasterSkillRuntime.fire_wall_positions(Vector2(100, 100), 48)
	assert(fire_cells.size() == 5 and fire_cells.has(Vector2(148, 100)) and fire_cells.has(Vector2(100, 52)))

	var lightning := CasterSkillRuntime.resolve("wizard.lightning", {
		"skill_level": 3, "magic_stat_roll": 30, "target_is_undead": true,
	})
	assert(lightning.operation == "target_damage" and lightning.damage > 0)
	assert(lightning.visual.original_path == "Data/Magic2.wil" and lightning.visual.source_index == 10)
	var lightning_visual := CasterSkillRuntime.create_visual(lightning, Vector2.ZERO)
	add_child(lightning_visual)
	assert(lightning_visual.visual_loaded and lightning_visual.visual_role == "target_effect")
	lightning_visual.free()
	var lightning_target := EnemyActor.new()
	lightning_target.max_hp = 500
	lightning_target.current_hp = 500
	var lightning_execution := CasterSkillRuntime.execute_cast(lightning, {
		"parent": self,
		"primary_target": lightning_target,
		"affected_targets": [lightning_target],
		"origin": Vector2.ZERO,
		"target_position": Vector2(48, 0),
		"direction": Vector2.RIGHT,
	})
	assert(lightning_execution.runtime_contract == "caster_skill_execution.v1")
	assert(lightning_execution.applied_count == 1 and lightning_target.current_hp == 500 - lightning.damage)
	assert(lightning_execution.nodes.size() == 1 and lightning_execution.nodes[0] is CasterSkillVisualEffect)
	for node: Node2D in lightning_execution.nodes:
		node.free()
	lightning_target.free()

	var healing_target := PlayerCharacter.new()
	healing_target.max_hp = 100
	healing_target.current_hp = 10
	var healing := CasterSkillRuntime.resolve("taoist.healing", {
		"skill_level": 3, "spiritual_stat_roll": 30,
	})
	var healing_execution := CasterSkillRuntime.execute_cast(healing, {
		"parent": self,
		"caster": healing_target,
		"affected_allies": [healing_target],
	})
	assert(healing_execution.applied_count == 1 and healing_target.current_hp == mini(100, 10 + healing.healing))
	for node: Node2D in healing_execution.nodes:
		node.free()
	healing_target.free()

	var teleport := CasterSkillRuntime.resolve("wizard.teleport", {
		"skill_level": 3, "random_0_to_10": 0,
	})
	var teleport_execution := CasterSkillRuntime.execute_cast(teleport, {"parent": self})
	assert(teleport_execution.adapter_required == "validated_home_map_destination")
	assert(teleport_execution.nodes.is_empty(), "teleport must not play before integration validates the destination")

	var armor_poison := CasterSkillRuntime.resolve("taoist.poison", {
		"skill_level": 3,
		"spiritual_stat_roll": 30,
		"poison_type": "red",
		"anti_poison_random": 0,
	})
	var armor_poison_execution := CasterSkillRuntime.execute_cast(armor_poison, {"parent": self})
	assert(armor_poison_execution.adapter_required == "target_armor_poison")
	assert(armor_poison_execution.nodes.is_empty(), "red poison must not play before the shared armor adapter accepts it")

	for skill_id: String in SkillProjectile.VISUAL_PATHS:
		var projectile_plan := CasterSkillRuntime.resolve(skill_id, {
			"skill_level": 3, "magic_stat_roll": 30, "spiritual_stat_roll": 30,
		})
		var projectile := CasterSkillRuntime.create_projectile(projectile_plan, Vector2.ZERO, Vector2.RIGHT)
		assert(projectile != null and projectile.skill_id == skill_id)
		add_child(projectile)
		assert(projectile._sprite != null)
		projectile.free()
	print("CASTER_SKILL_RUNTIME_PASS: all 27 wizard/taoist skills have stable execution plans and actual visual/node dispatch")
	get_tree().quit(0)
