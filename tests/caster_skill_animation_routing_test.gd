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


func _test_absolute_context() -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		9001,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_test_ground_to_screen")
	)


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)


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

	var lightning := CasterSkillRuntime.resolve("wizard.lightning", _context())
	var lightning_nodes := CasterSkillRuntime.create_cast_nodes(
		lightning, owner.global_position, target.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(lightning_nodes.size() == 1)
	var strike := lightning_nodes[0] as CasterSkillVisualEffect
	add_child(strike)
	
	assert(strike is CasterSkillSkyStrikeVisualEffect, "wizard.lightning must create SkyStrike via Factory")
	strike.free()

	var temptation := CasterSkillRuntime.resolve("wizard.temptation_light", _context())
	var temptation_nodes := CasterSkillRuntime.create_cast_nodes(
		temptation, owner.global_position, target.global_position,
		Vector2.RIGHT, Color.WHITE, target, owner
	)
	assert(temptation_nodes.size() == 1)
	var followed := temptation_nodes[0] as CasterSkillVisualEffect
	add_child(followed)
	target.global_position += Vector2(32, 16)
	followed._process(0.01)
	assert(followed.global_position == target.global_position.round())
	followed.free()

	var hellfire := CasterSkillRuntime.resolve("wizard.hellfire", _context())
	var hellfire_nodes := CasterSkillRuntime.create_cast_nodes(
		hellfire, owner.global_position, owner.global_position + Vector2(250, 0),
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

	var hell_lightning := CasterSkillRuntime.resolve("wizard.hell_lightning", _context())
	var hell_lightning_nodes := CasterSkillRuntime.create_cast_nodes(
		hell_lightning, owner.global_position, target.global_position,
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
	inflated_plan["geometry_screen_points_px"] = [
		Vector2.ZERO,
		Vector2(400.0, 640.0),
		Vector2(320.0, 160.0),
	]
	inflated_plan["geometry_screen_offsets_px"] = [
		Vector2.ZERO,
		Vector2(400.0, 640.0),
		Vector2(320.0, 160.0),
	]
	var inflated_nodes := CasterSkillRuntime.create_cast_nodes(
		inflated_plan, owner.global_position, target.global_position,
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

	var fire_wall := CasterSkillRuntime.resolve("wizard.fire_wall", _context())
	fire_wall["snapshot_coordinate_context"] = _test_absolute_context()
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

	var skeleton_plan := CasterSkillRuntime.resolve("taoist.summon_skeleton", _context())
	skeleton_plan["snapshot_coordinate_context"] = _test_absolute_context()
	var skeleton := CasterSkillRuntime.create_summon_actor(
		skeleton_plan, owner, 30, 40, owner.global_position
	)
	assert(skeleton != null)
	add_child(skeleton)
	assert(skeleton._sprite != null)
	assert(skeleton._sprite.name == "SkeletonPrimaryStandAnimation")
	assert(int(skeleton._sprite.call("frame_count")) == 4)
	skeleton.free()

	var teleport := CasterSkillRuntime.resolve("wizard.teleport", _context())
	var destination := Vector2(320, 160)
	var teleport_execution := CasterSkillRuntime.execute_cast(
		teleport,
		{
			"parent": self,
			"caster": owner,
			"origin": owner.global_position,
			"direction": Vector2.RIGHT,
			"teleport_destination": destination,
		}
	)
	assert(teleport_execution.spawned_count == 2)
	assert(owner.global_position == destination)
	var phase_ids: Array[String] = []
	for node: Node2D in teleport_execution.nodes:
		assert(node is CasterSkillVisualEffect)
		phase_ids.append((node as CasterSkillVisualEffect).phase_id)
		node.free()
	phase_ids.sort()
	assert(phase_ids == ["", "arrival"])

	owner.free()
	target.free()
	print(
		"CASTER_SKILL_ANIMATION_ROUTING_PASS: exact direction thresholds, "
		+ "primary-pixel rendering, slender-axis lightning, specialized roles, "
		+ "formal five-tile hellfire, primary fire wall and two-phase teleport"
	)
	print("CASTER_SKILL_ANIMATION_ROUTING_TEST_PASS")
	get_tree().quit(0)
