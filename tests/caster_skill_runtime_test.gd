extends Node

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshot := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const CombatUnitLegacyAdapter := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)

var _magic_defense_calls: Array[String] = []


func _test_absolute_context() -> Dictionary:
	return SkillFootprintSnapshot.make_absolute_runtime_context(
		9001,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_test_ground_to_screen")
	)


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)


func _test_magic_defense(skill_id: String, incoming_damage: int, _target_stats: Dictionary) -> int:
	_magic_defense_calls.append(skill_id)
	return maxi(0, incoming_damage - 3)


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
		assert(plan.runtime_contract == CasterSkillRuntime.RUNTIME_CONTRACT_ID, "%s lacks runtime contract" % skill_id)
		for formal_field in [
			"maximum_range_gu", "search_range_gu", "area_radius_gu", "visual_radius_px",
		]:
			assert(plan.has(formal_field), "%s lacks %s" % [skill_id, formal_field])
		for forbidden_field in [
			"range", "search_range", "area_radius", "area_radius_cells", "cell_size",
		]:
			assert(not plan.has(forbidden_field), "%s exposes %s" % [skill_id, forbidden_field])
		assert(not str(plan.get("operation", "")).is_empty(), "%s lacks runtime operation" % skill_id)
		assert(plan.get("failure_reason", "") != "missing_runtime_operation", "%s is not executable" % skill_id)
		if skill_id == "taoist.spiritual_warfare":
			assert(not plan.castable and plan.visual.status == "no_runtime_visual")
		else:
			assert(plan.visual.status == "formal_primary_client_animation", "%s lacks formal visual binding" % skill_id)
			assert(plan.visual.animation.contract == "caster_skill_animation.v1")
		plan["snapshot_coordinate_context"] = _test_absolute_context()
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
		var expected_node_count := 0 if skill_id == "taoist.spiritual_warfare" else (4 if skill_id == "wizard.fire_wall" else 1)
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
		"skill_level": 3, "magic_stat_roll": 30,
	})
	assert(fire_wall.operation == "ground_dot" and fire_wall.execution_shape == "square_2x2")
	assert(fire_wall.duration_seconds == 28 and fire_wall.tick_interval_seconds == 1.0)
	assert(is_equal_approx(float(fire_wall.cell_spacing_gu), 1.0))
	assert(is_equal_approx(float(fire_wall.ground_effect_radius_gu), 0.5))
	var fire_cells := CasterSkillRuntime.fire_wall_positions_ground_gu(
		Vector2(100, 100), 1.0
	)
	assert(fire_cells == [
		Vector2(100, 100), Vector2(132, 116),
		Vector2(68, 116), Vector2(100, 132),
	])
	GroundSkillEffect.reset_runtime_tick_claims_for_tests()
	var fire_wall_caster := Node2D.new()
	var second_fire_wall_caster := Node2D.new()
	var fire_wall_target := Node.new()
	var first_runtime_field := GroundSkillEffect.new()
	first_runtime_field.setup_ground_unit_effect(
		Vector2.ZERO, 37, 0.5, 12.0, Color.WHITE, "wizard.fire_wall", 1.0, 74.0
	)
	first_runtime_field.configure_runtime_source(fire_wall_caster)
	var overlapping_runtime_field := GroundSkillEffect.new()
	overlapping_runtime_field.setup_ground_unit_effect(
		Vector2.ZERO, 91, 0.5, 12.0, Color.WHITE, "wizard.fire_wall", 1.0, 74.0
	)
	overlapping_runtime_field.configure_runtime_source(fire_wall_caster)
	assert(first_runtime_field.claim_runtime_tick(fire_wall_target))
	assert(
		not overlapping_runtime_field.claim_runtime_tick(fire_wall_target),
		"overlapping fire walls from one caster stacked a second tick"
	)
	assert(
		first_runtime_field.damage == 37
		and overlapping_runtime_field.damage == 91,
		"fire wall overlap protection changed either field's canonical tick power"
	)
	overlapping_runtime_field.configure_runtime_source(second_fire_wall_caster)
	assert(
		overlapping_runtime_field.claim_runtime_tick(fire_wall_target),
		"different casters incorrectly shared one fire wall tick claim"
	)
	first_runtime_field.free()
	overlapping_runtime_field.free()
	fire_wall_target.free()
	fire_wall_caster.free()
	second_fire_wall_caster.free()

	var repulsion_target := Node2D.new()
	var repulsion_origin_screen_px := Vector2(100.0, 100.0)
	repulsion_target.global_position = (
		repulsion_origin_screen_px
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(Vector2.RIGHT)
	)
	var repulsion_result := CasterSkillRuntime.execute_cast({
		"skill_id": "wizard.repulsion_ring",
		"success": true,
		"operation": "knockback",
		"push_distance_gu": 1.0,
	}, {
		"origin": repulsion_origin_screen_px,
		"direction": Vector2.RIGHT,
		"affected_targets": [repulsion_target],
		"spatial_test_adapter_id": (
			CasterSkillRuntime.NON_PRODUCTION_SPATIAL_ADAPTER_ID
		),
	})
	assert(repulsion_result.applied_count == 1)
	assert(repulsion_result.compatibility_adapter_used)
	assert(repulsion_target.global_position.is_equal_approx(
		repulsion_origin_screen_px
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(Vector2.RIGHT * 2.0)
	))
	for repulsion_node: Node2D in repulsion_result.nodes:
		repulsion_node.free()
	repulsion_target.free()

	var lightning := CasterSkillRuntime.resolve("wizard.lightning", {
		"skill_level": 3, "magic_stat_roll": 30, "target_is_undead": true,
	})
	assert(lightning.operation == "target_damage" and lightning.damage > 0)
	assert(lightning.visual.original_path == "Data/Magic2.wil")
	assert(lightning.visual.animation.sequences[0].frames[0].source_index == 10)
	var lightning_visual := CasterSkillRuntime.create_visual(lightning, Vector2.ZERO)
	add_child(lightning_visual)
	assert(lightning_visual.visual_loaded and lightning_visual.visual_role == "target_effect")
	lightning_visual.free()
	var lightning_target := EnemyActor.new()
	lightning_target.max_hp = 500
	lightning_target.current_hp = 500
	lightning_target.monster_data = {"antiMagic": 1}
	var lightning_evaded := CasterSkillRuntime.execute_cast(lightning, {
		"parent": self,
		"primary_target": lightning_target,
		"affected_targets": [lightning_target],
		"origin": Vector2.ZERO,
		"target_position": Vector2(48, 0),
		"direction": Vector2.RIGHT,
		"anti_magic_roll": 0,
		"magic_defense_adapter": Callable(self, "_test_magic_defense"),
		"snapshot_coordinate_context": _test_absolute_context(),
	})
	assert(lightning_evaded.evaded_count == 1 and lightning_evaded.applied_count == 0)
	assert(lightning_target.current_hp == 500 and _magic_defense_calls.is_empty(), "雷电AntiMagic成功后仍进入MAC或伤害")
	assert(
		lightning_evaded.target_resolutions[0].stage_order == ["anti_magic", "magic_defense", "take_damage"]
		and not lightning_evaded.target_resolutions[0].magic_defense_checked,
		"雷电运行时阶段顺序错误"
	)
	for node: Node2D in lightning_evaded.nodes:
		node.free()
	var lightning_execution := CasterSkillRuntime.execute_cast(lightning, {
		"parent": self,
		"primary_target": lightning_target,
		"affected_targets": [lightning_target],
		"origin": Vector2.ZERO,
		"target_position": Vector2(48, 0),
		"direction": Vector2.RIGHT,
		"anti_magic_roll": 1,
		"magic_defense_adapter": Callable(self, "_test_magic_defense"),
		"snapshot_coordinate_context": _test_absolute_context(),
	})
	assert(lightning_execution.runtime_contract == "caster_skill_execution.v1")
	assert(lightning_execution.applied_count == 1 and lightning_execution.evaded_count == 0)
	assert(lightning_target.current_hp == 500 - maxi(0, int(lightning.damage) - 3), "雷电未按AntiMagic→MAC→伤害执行")
	assert(_magic_defense_calls == ["wizard.lightning"])
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
		"snapshot_coordinate_context": _test_absolute_context(),
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

		var projectile_target := EnemyActor.new()
		projectile_target.max_hp = 500
		projectile_target.current_hp = 500
		projectile_target.monster_data = {"antiMagic": 1}
		var evaded_projectile := CasterSkillRuntime.create_projectile(projectile_plan, Vector2.ZERO, Vector2.RIGHT)
		evaded_projectile.configure_runtime_resolution(
			null,
			Callable(self, "_test_magic_defense"),
			0
		)
		var calls_before_evade := _magic_defense_calls.size()
		evaded_projectile._apply_hit(projectile_target)
		assert(
			projectile_target.current_hp == 500
			and evaded_projectile.last_resolution.magic_evaded
			and not evaded_projectile.last_resolution.magic_defense_checked
			and _magic_defense_calls.size() == calls_before_evade,
			"%s投射物躲避后仍进入MAC或伤害" % skill_id
		)
		evaded_projectile.free()
		var connected_projectile := CasterSkillRuntime.create_projectile(projectile_plan, Vector2.ZERO, Vector2.RIGHT)
		connected_projectile.configure_runtime_resolution(
			null,
			Callable(self, "_test_magic_defense"),
			1
		)
		connected_projectile._apply_hit(projectile_target)
		assert(
			projectile_target.current_hp == 500 - maxi(0, int(projectile_plan.damage) - 3)
			and connected_projectile.last_resolution.magic_defense_checked
			and _magic_defense_calls[-1] == skill_id,
			"%s投射物未按AntiMagic→MAC→伤害执行" % skill_id
		)
		connected_projectile.free()
		projectile_target.free()

	var poison_target := EnemyActor.new()
	poison_target.max_hp = 100
	poison_target.current_hp = 100
	poison_target.anti_poison = 5
	poison_target.monster_data = {"antiMagic": 10}
	var resisted_poison_projectile := SkillProjectile.new()
	resisted_poison_projectile.setup_ground_unit_projectile(
		Vector2.ZERO,
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu(Vector2.RIGHT),
		3.125,
		30,
		CombatUnitLegacyAdapter.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapter.PROJECTILE_RADIUS_GU,
		Vector2.ZERO,
		Color.GREEN,
		"poison",
		4,
		8.0,
		"taoist.poison"
	)
	resisted_poison_projectile.configure_runtime_resolution(null, Callable(), 0, 7)
	resisted_poison_projectile._apply_hit(poison_target)
	assert(
		poison_target.current_hp == 100
		and poison_target.poison_time == 0.0
		and resisted_poison_projectile.last_resolution.evasion_channel == "anti_poison",
		"施毒投射物错误使用AntiMagic或绕过AntiPoison"
	)
	resisted_poison_projectile.free()
	var applied_poison_projectile := SkillProjectile.new()
	applied_poison_projectile.setup_ground_unit_projectile(
		Vector2.ZERO,
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu(Vector2.RIGHT),
		3.125,
		30,
		CombatUnitLegacyAdapter.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapter.PROJECTILE_RADIUS_GU,
		Vector2.ZERO,
		Color.GREEN,
		"poison",
		4,
		8.0,
		"taoist.poison"
	)
	applied_poison_projectile.configure_runtime_resolution(null, Callable(), 0, 6)
	applied_poison_projectile._apply_hit(poison_target)
	assert(
		poison_target.current_hp == 100
		and poison_target.poison_time == 8.0
		and applied_poison_projectile.last_resolution.poison_applies,
		"施毒AntiPoison成功门未应用独立毒状态"
	)
	applied_poison_projectile.free()
	poison_target.free()
	print("CASTER_SKILL_RUNTIME_PASS: all 27 wizard/taoist skills have stable execution plans and actual visual/node dispatch")
	get_tree().quit(0)
