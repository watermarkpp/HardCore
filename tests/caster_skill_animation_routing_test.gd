extends Node

const AnimationPlayerScript := preload("res://scripts/caster_skill_animation_player.gd")
const CasterSkillSkyStrikeVisualEffect := preload(
	"res://scripts/caster_skill_sky_strike_visual_effect.gd"
)
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CombatUnitLegacyAdapter := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)


func _test_absolute_context() -> Dictionary:
	var context := Snapshot.make_absolute_runtime_context(
		9001,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_test_ground_to_screen")
	)
	# FREEZE-P0.1: mapped test context declares an explicit identity projection.
	context["screen_to_ground_position_px"] = Callable(
		self,
		"_test_screen_to_ground"
	)
	return context


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)


func _test_screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpace.screen_delta_px_to_ground_delta_gu(value)


func _context() -> Dictionary:
	return {
		"skill_level": 3,
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"target_max_hp": 500,
		"magic_stat_roll": 30,
		"spiritual_stat_roll": 30,
		"random_0_to_10": 0,
	}


func _canonical_plan(
	skill_id: String,
	origin: Vector2,
	target_position: Vector2
) -> Dictionary:
	# Q3-C: canonical plans for visual routing (legacy resolve removed).
	return Fixtures.build_canonical_presentation_plan(
		skill_id,
		3,
		40,
		origin,
		Vector2.RIGHT,
		target_position,
		Fixtures.circle_snapshot(
			self,
			skill_id,
			"q3c:routing:%s" % skill_id,
			9001,
			Vector2(0, 0),
			2.0
		),
		9001
	)


func _inject_line_geometry(
	plan: Dictionary,
	length_gu: float,
	direction: Vector2
) -> void:
	var actions: Array = plan.get("presentation_actions", [])
	if actions.is_empty():
		return
	var action: Dictionary = actions[0]
	var direction_ground_gu := (
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu(direction)
		.normalized()
	)
	var end_screen_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		direction_ground_gu * length_gu
	)
	action["geometry_origin_screen_px"] = Vector2.ZERO
	action["geometry_screen_points_px"] = [Vector2.ZERO, end_screen_px]
	action["geometry_screen_offsets_px"] = [Vector2.ZERO, end_screen_px]


func _ready() -> void:
	# Strict slope boundaries from MirClient.GetFlyDirection16.
	assert(CasterSkillVisualRegistry.direction_index(Vector2(4.0, -1.0)) == 4)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(4.0, -1.001)) == 3)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(190.0, -99.0)) == 3)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(190.0, -101.0)) == 2)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(10.0, -14.0)) == 2)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(10.0, -15.0)) == 1)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(1.0, -4.0)) == 1)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(1.0, -4.001)) == 0)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(-4.0, 1.001)) == 11)
	assert(CasterSkillVisualRegistry.direction_index(Vector2(-1.0, 4.001)) == 8)
	var eight_direction_sequences := [
		{"direction_index": 0}, {"direction_index": 2},
		{"direction_index": 4}, {"direction_index": 6},
		{"direction_index": 8}, {"direction_index": 10},
		{"direction_index": 12}, {"direction_index": 14},
	]
	assert(CasterSkillVisualRegistry.sequence_index(1, eight_direction_sequences) == 1)
	assert(CasterSkillVisualRegistry.sequence_index(15, eight_direction_sequences) == 0)

	var lightning_player := AnimationPlayerScript.new()
	add_child(lightning_player)
	assert(lightning_player.configure("wizard.lightning"))
	var lightning_render := CasterSkillVisualRegistry.render_policy(
		"wizard.lightning"
	)
	assert(
		lightning_render.get("presentation_contract", "")
		== "skills.wizard.lightning.slender_axis.v1"
	)
	assert(lightning_player.scale.is_equal_approx(Vector2(0.62, 1.0)))
	assert(lightning_player.frame_count() == 6)
	assert(lightning_player.fitted_visual_bounds().size.x <= 316.0 * 0.62 + 0.001)
	assert(lightning_player.fitted_visual_bounds().size.y == 997.0)
	lightning_player.free()

	var invalid_projectile := SkillProjectile.new()
	invalid_projectile.setup_ground_unit_projectile(
		Vector2.ZERO,
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu(Vector2.RIGHT),
		3.125,
		10,
		CombatUnitLegacyAdapter.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapter.PROJECTILE_RADIUS_GU,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.lightning"
	)
	add_child(invalid_projectile)
	assert(invalid_projectile._sprite == null)
	assert(invalid_projectile.visual_rejection_reason.begins_with("non_projectile_visual"))
	invalid_projectile.free()

	var owner := PlayerCharacter.new()
	owner.global_position = Vector2(10, 20)
	var target := Node2D.new()
	target.global_position = Vector2(96, 48)
	add_child(owner)
	add_child(target)

	var lightning := _canonical_plan(
		"wizard.lightning",
		owner.global_position,
		target.global_position
	)
	var lightning_nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		lightning, owner.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(lightning_nodes.size() == 1)
	var strike := lightning_nodes[0] as CasterSkillVisualEffect
	add_child(strike)
	
	assert(strike is CasterSkillSkyStrikeVisualEffect, "wizard.lightning must create SkyStrike via Factory")
	strike.free()

	var temptation := _canonical_plan(
		"wizard.temptation_light",
		owner.global_position,
		target.global_position
	)
	var temptation_nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		temptation, owner.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(temptation_nodes.size() == 1)
	var followed := temptation_nodes[0] as CasterSkillVisualEffect
	add_child(followed)
	target.global_position += Vector2(32, 16)
	followed._process(0.01)
	assert(followed.global_position == target.global_position.round())
	followed.free()

	var hellfire := _canonical_plan(
		"wizard.hellfire",
		owner.global_position,
		owner.global_position + Vector2(250, 0)
	)
	_inject_line_geometry(hellfire, 5.0, Vector2.RIGHT)
	var hellfire_nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		hellfire, owner.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(hellfire_nodes.size() == 1)
	var trail := hellfire_nodes[0] as CasterSkillVisualEffect
	add_child(trail)
	var hellfire_direction_ground_gu := (
		GroundUnitSpace.screen_delta_px_to_ground_delta_gu(Vector2.RIGHT)
		.normalized()
	)
	var expected_hellfire_radius_px := (
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			hellfire_direction_ground_gu * 5.0
		).length()
	)
	assert(is_equal_approx(
		trail.radius, expected_hellfire_radius_px
	), "formal five-GU hellfire radius was not authoritative")
	assert(trail._hellfire_frame_count == 6)
	assert(trail._hellfire_step_seconds == 0.05)
	assert(is_equal_approx(trail._hellfire_step_distance, (500.0 / 0.9) * 0.05))
	trail.free()

	var hell_lightning := _canonical_plan(
		"wizard.hell_lightning",
		owner.global_position,
		target.global_position
	)
	var hell_lightning_nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		hell_lightning, owner.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(hell_lightning_nodes.size() == 1)
	var hell_lightning_visual := hell_lightning_nodes[0]
	assert(hell_lightning_visual is CasterSkillVisualEffect)
	assert(not hell_lightning_visual is CasterSkillSkyStrikeVisualEffect)
	add_child(hell_lightning_visual)
	var profile_animation: Dictionary = (
		CasterSkillVisualRegistry.visual_profile("wizard.hell_lightning").get(
			"animation", {}
		)
	)
	assert(profile_animation is Dictionary)
	assert(str(profile_animation.get("scale_mode", "")) != "fixed_source")
	var sprite := (hell_lightning_visual._sprites[0] as CasterSkillAnimationPlayer)
	assert(sprite != null)
	assert(sprite.scale != Vector2.ZERO)
	var inflated_plan := hell_lightning.duplicate(true)
	var inflated_actions: Array = inflated_plan.get(
		"presentation_actions",
		[]
	)
	if not inflated_actions.is_empty():
		var inflated_action: Dictionary = inflated_actions[0]
		inflated_action["geometry_screen_points_px"] = [
			Vector2.ZERO,
			Vector2(400.0, 640.0),
			Vector2(320.0, 160.0),
		]
		inflated_action["geometry_screen_offsets_px"] = [
			Vector2.ZERO,
			Vector2(400.0, 640.0),
			Vector2(320.0, 160.0),
		]
	var inflated_nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		inflated_plan, owner.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(inflated_nodes.size() == 1)
	add_child(inflated_nodes[0] as Node2D)
	var inflated_sprite := (
		inflated_nodes[0]
	)._sprites[0] as CasterSkillAnimationPlayer
	assert(inflated_sprite != null)
	assert(inflated_sprite.scale != Vector2.ZERO)
	(inflated_nodes[0] as Node2D).free()
	hell_lightning_visual.free()

	# Q3-C: the ground factory consumes a canonical node plan; the legacy
	# resolve() plan was removed.
	var fire_wall := {
		"operation": "ground_dot",
		"success": true,
		"skill_id": "wizard.fire_wall",
		"release_id": "q3c:routing:fire_wall",
		"damage": 0,
		"duration_seconds": 1.0,
		"tick_interval_seconds": 0.8,
		"ground_effect_radius_gu": 0.5,
		"visual_radius_px": 22.08,
		"visual": {"role": CasterSkillVisualRegistry.ROLE_GROUND_EFFECT},
		"snapshot_coordinate_context": _test_absolute_context(),
		"skill_footprint_snapshot": {},
	}
	var fire_cells := CasterSkillRuntime.create_ground_effects(
		fire_wall, Vector2(96, 48), Color.WHITE, owner
	)
	assert(fire_cells.size() == 4)
	for cell: GroundSkillEffect in fire_cells:
		add_child(cell)
		assert(cell._sprite != null)
		assert(cell._sprite.frame_count() == 6)
		assert(cell._sprite.scale == Vector2.ONE)
		cell.free()

	# Q3-C: the summon factory consumes a canonical node plan.
	var skeleton_plan := {
		"operation": "summon",
		"success": true,
		"skill_id": "taoist.summon_skeleton",
		"release_id": "q3c:routing:summon",
		"display_name": "骷髅",
		"skill_level": 3,
		"snapshot_coordinate_context": _test_absolute_context(),
	}
	var skeleton := CasterSkillRuntime.create_summon_actor(
		skeleton_plan, owner, 30, 40, owner.global_position
	)
	assert(skeleton != null)
	add_child(skeleton)
	assert(skeleton._sprite != null)
	assert(skeleton._sprite.name == "SkeletonPrimaryStandAnimation")
	assert(int(skeleton._sprite.call("frame_count")) == 4)
	skeleton.free()

	# Q3-C: the legacy execute_cast was removed. The canonical adapter creates
	# the teleport departure visual; the arrival phase is covered by the Q3-B
	# formal production entry test (canonical_skill_production_entry_test).
	var teleport := _canonical_plan(
		"wizard.teleport",
		owner.global_position,
		owner.global_position
	)
	var teleport_nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		teleport, owner.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(teleport_nodes.size() == 1, "teleport departure visual must exist")
	var teleport_visual := teleport_nodes[0] as CasterSkillVisualEffect
	assert(teleport_visual != null)
	add_child(teleport_visual)
	assert(teleport_visual.phase_id == "")
	teleport_visual.free()

	owner.free()
	target.free()
	print(
		"CASTER_SKILL_ANIMATION_ROUTING_PASS: exact direction thresholds, "
		+ "primary-pixel rendering, slender-axis lightning, specialized roles, "
		+ "formal five-tile hellfire, primary fire wall and two-phase teleport"
	)
	print("CASTER_SKILL_ANIMATION_ROUTING_TEST_PASS")
	get_tree().quit(0)
