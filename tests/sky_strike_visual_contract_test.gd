extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterSkillSkyStrikeVisualEffect := preload(
	"res://scripts/caster_skill_sky_strike_visual_effect.gd"
)
const CasterSkillAnimationPlayer := preload(
	"res://scripts/caster_skill_animation_player.gd"
)
const PlayerCharacter := preload("res://scripts/player.gd")
const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")


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


func _build_anchor_offset() -> Vector2:
	var anchor_profile: Dictionary = CasterSkillVisualRegistry.visual_profile(
		"wizard.lightning"
	).get("anchor", {})
	var raw_offset: Variant = anchor_profile.get("offset", [0.0, 0.0])
	if raw_offset is Array and raw_offset.size() >= 2:
		return Vector2(float(raw_offset[0]), float(raw_offset[1]))
	return Vector2.ZERO


func _spawn_sky_strike_node(
	plan: Dictionary,
	owner: PlayerCharacter,
	target: Node2D
) -> CasterSkillSkyStrikeVisualEffect:
	var nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		plan,
		owner.global_position,
		Vector2.RIGHT,
		Color.WHITE,
		target,
		owner
	)
	assert(nodes.size() == 1)
	var node := nodes[0]
	assert(node is CasterSkillSkyStrikeVisualEffect)
	return node as CasterSkillSkyStrikeVisualEffect


func _ready() -> void:
	var owner := PlayerCharacter.new()
	var target := Node2D.new()
	owner.global_position = Vector2(10, 20)
	target.global_position = Vector2(96, 48)
	add_child(owner)
	add_child(target)

	assert(CasterSkillVisualRegistry.visual_type("wizard.lightning") == "sky_strike")
	assert(CasterSkillVisualRegistry.visual_type("wizard.hell_lightning") != "sky_strike")
	assert(
		CasterSkillSkyStrikeVisualEffect.new() != null,
		"sanity: class type is loadable"
	)
	var plan := Fixtures.build_canonical_presentation_plan(
		"wizard.lightning",
		3,
		40,
		owner.global_position,
		Vector2.RIGHT,
		target.global_position,
		Fixtures.circle_snapshot(
			self,
			"wizard.lightning",
			"q3c:visual:sky_strike",
			1,
			Vector2(0, 0),
			2.0
		)
	)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"canonical sky-strike plan must be accepted"
	)

	var profile_animation: Dictionary = CasterSkillVisualRegistry.visual_profile(
		"wizard.lightning"
	).get("animation", {})
	var expected_scale := Vector2(
		float(profile_animation.get("width_scale", 1.0)),
		float(profile_animation.get("height_scale", 1.0))
	)
	var anchor_profile_offset := _build_anchor_offset()

	var base_node := _spawn_sky_strike_node(plan, owner, target)
	add_child(base_node)
	var base_sprite := base_node._sprites[0] as CasterSkillAnimationPlayer
	assert(base_sprite != null)
	assert(base_sprite.scale.is_equal_approx(expected_scale))
	var baseline_anchor_position := base_node.global_position
	var baseline_anchor_sprite_position := base_sprite.position
	var animated_anchor_offset := Vector2(
		float(CasterSkillVisualRegistry.visual_profile("wizard.lightning").get(
			"anchor", {}
		).get("offset", [0.0, 0.0])[0]),
		float(CasterSkillVisualRegistry.visual_profile("wizard.lightning").get(
			"anchor", {}
		).get("offset", [0.0, 0.0])[1])
	)
	assert(
		animated_anchor_offset == anchor_profile_offset,
		"sky_strike anchor offset should be profile-driven"
	)

	for geometry_length in [50.0, 200.0, 500.0]:
		var geometry_plan := plan.duplicate(true)
		geometry_plan["geometry_screen_points_px"] = [
			Vector2.ZERO,
			Vector2(geometry_length, 0.0),
			Vector2(0.0, geometry_length),
		]
		geometry_plan["geometry_screen_offsets_px"] = [
			Vector2.ZERO,
			Vector2(geometry_length, 0.0),
			Vector2(0.0, geometry_length),
		]
		var geometry_node := _spawn_sky_strike_node(
			geometry_plan,
			owner,
			target
		)
		add_child(geometry_node)
		var geometry_sprite := geometry_node._sprites[0] as CasterSkillAnimationPlayer
		assert(geometry_sprite != null)
		assert(geometry_sprite.scale.is_equal_approx(expected_scale))
		geometry_node.free()

	# Anchor-policy is ingested from the presentation profile, not from legacy defaults
	var _md: Dictionary = base_node.sky_strike_visual_debug_metadata()
	assert(_md.get("anchor_policy", "") == "world_target_footpoint",
		"sky_strike anchor must be world_target_footpoint from profile")
	# Position must land on target footpoint + profile offset at release time
	var _expected_screen_px := (target.global_position + animated_anchor_offset).round() if animated_anchor_offset.length_squared() > 0.0 else target.global_position.round()
	assert(base_node.global_position.distance_to(_expected_screen_px) <= 0.5,
		"sky_strike must land at target footpoint (dist=%.1f)" % base_node.global_position.distance_to(_expected_screen_px))
	assert(base_node._sprites[0].position == baseline_anchor_sprite_position)
	target.global_position = Vector2(96.0, 48.0)

	var gameplay_offset_plan := plan.duplicate(true)
	gameplay_offset_plan["geometry_origin_screen_px"] = Vector2(560.0, 320.0)
	var gameplay_offset_context := {
		"gameplay_geometry": {"origin": Vector2(560.0, 320.0)},
	}
	gameplay_offset_plan["visual_geometry_context"] = gameplay_offset_context
	var gameplay_offset_node := _spawn_sky_strike_node(
		gameplay_offset_plan,
		owner,
		target
	)
	add_child(gameplay_offset_node)
	assert(
		gameplay_offset_node.global_position.is_equal_approx(baseline_anchor_position),
		"sky_strike anchor should come from profile and avoid gameplay_geometry origin"
	)
	assert(gameplay_offset_node._sprites[0].position == base_node._sprites[0].position)
	gameplay_offset_node.free()

	var lifecycle_plan := plan.duplicate(true)
	var lifecycle_node := _spawn_sky_strike_node(lifecycle_plan, owner, target)
	add_child(lifecycle_node)
	var debug_metadata: Dictionary = lifecycle_node.sky_strike_visual_debug_metadata()
	var lifecycle_profile: Dictionary = (
		CasterSkillVisualRegistry.visual_profile("wizard.lightning").get("lifecycle", {})
	)
	assert(debug_metadata.get("anchor_policy", "") == "world_target_footpoint")
	assert(profile_animation.get("scale_mode", "") == "fixed_source")
	assert(not bool(debug_metadata.get("geometry_driven_scale", true)))
	var consumed_lifecycle: Dictionary = (
		lifecycle_node.sky_strike_lifecycle_profile()
	)
	print("SKY_STRIKE_TEST_LIFECYCLE_DEBUG=%s" % str(consumed_lifecycle))
	print("SKY_STRIKE_TEST_PROFILE_DEBUG=%s" % str(lifecycle_profile))
	assert(consumed_lifecycle.get("impact", -1.0) > -0.0001)
	assert(consumed_lifecycle.get("duration", -1.0) > 0.0)
	assert(consumed_lifecycle.get("warning", -1.0) >= 0.0)
	assert(consumed_lifecycle.get("impact", -1.0) <= consumed_lifecycle.get("duration", 999.0) + 1.0)
	var warning_lifecycle_plan := plan.duplicate(true)
	var warning_lifecycle_profile: Dictionary = CasterSkillVisualRegistry.visual_profile(
		"wizard.lightning"
	).duplicate(true)
	if not warning_lifecycle_profile.has("lifecycle"):
		warning_lifecycle_profile["lifecycle"] = {}
	var warning_lifecycle := warning_lifecycle_profile.get("lifecycle", {}) as Dictionary
	warning_lifecycle["warning"] = 0.2
	warning_lifecycle["impact"] = 0.0
	var warning_lifecycle_node := _spawn_sky_strike_node(warning_lifecycle_plan, owner, target)
	warning_lifecycle_node._apply_sky_strike_profile_context(
		{"visual_profile": warning_lifecycle_profile}
	)
	warning_lifecycle_node._refresh_sky_strike_debug_metadata()
	var warning_lifecycle_metadata: Dictionary = warning_lifecycle_node.sky_strike_visual_debug_metadata()
	assert(float(warning_lifecycle_metadata.get("warning", -1.0)) == 0.2)
	var warning_lifecycle_sprite := warning_lifecycle_node._sprites[0] as CasterSkillAnimationPlayer
	assert(warning_lifecycle_sprite != null)
	assert(not warning_lifecycle_sprite.is_processing())
	warning_lifecycle_node._process(0.1)
	warning_lifecycle_sprite._process(0.1)
	assert(warning_lifecycle_sprite.visible == false)
	assert(not warning_lifecycle_sprite.is_processing())
	warning_lifecycle_node._process(0.05)
	warning_lifecycle_sprite._process(0.05)
	assert(warning_lifecycle_sprite.visible == false)
	assert(not warning_lifecycle_sprite.is_processing())
	warning_lifecycle_node._process(0.1)
	warning_lifecycle_sprite._process(0.1)
	assert(warning_lifecycle_sprite.visible == true)
	assert(warning_lifecycle_sprite.is_processing())
	warning_lifecycle_node.free()

	var lifecycle_sprite := lifecycle_node._sprites[0] as CasterSkillAnimationPlayer
	assert(lifecycle_sprite != null)
	assert(float(consumed_lifecycle.get("impact", -1.0)) == 0.0)
	assert(lifecycle_sprite.visible == true)
	assert(lifecycle_sprite.is_processing())
	assert(lifecycle_sprite.current_frame_index == 0)
	assert(not lifecycle_sprite.playback_complete)
	lifecycle_node._process(0.1)
	lifecycle_sprite._process(0.1)
	assert(lifecycle_sprite.visible == true)
	lifecycle_node._process(0.3)
	lifecycle_sprite._process(0.3)
	assert(lifecycle_sprite.visible == true)
	var impact_delay := float(consumed_lifecycle.get("impact", 0.0))
	var expected_duration := float(consumed_lifecycle.get("duration", 0.0))
	var lifetime_probe := 0.0
	while lifetime_probe < impact_delay + expected_duration + 1.0:
		lifecycle_node._process(0.05)
		lifecycle_sprite._process(0.05)
		lifetime_probe += 0.05
	assert(lifecycle_node.is_queued_for_deletion())

	owner.free()
	target.free()
	print("SKY_STRIKE_VISUAL_CONTRACT_TEST_PASS")
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)
