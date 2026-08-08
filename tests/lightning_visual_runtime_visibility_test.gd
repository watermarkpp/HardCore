extends Node2D

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload(
	"res://scripts/caster_skill_visual_registry.gd"
)
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

const SKILL_ID := "wizard.lightning"
const EXPECTED_SCALE := Vector2(0.62, 1.0)


func _ready() -> void:
	var owner := PlayerCharacter.new()
	var target := Node2D.new()
	owner.global_position = Vector2(320.0, 620.0)
	target.global_position = Vector2(760.0, 620.0)
	add_child(owner)
	add_child(target)

	var plan := Fixtures.build_canonical_presentation_plan(
		SKILL_ID,
		3,
		40,
		owner.global_position,
		Vector2.RIGHT,
		target.global_position,
		Fixtures.circle_snapshot(
			self,
			SKILL_ID,
			"lightning:runtime_visibility",
			1,
			Vector2.ZERO,
			2.0
		)
	)
	assert(bool(plan.get("rejection", {}).get("accepted", false)))
	var visual_requests: Array[Dictionary] = []
	for raw_action: Variant in plan.get("presentation_actions", []):
		if raw_action is Dictionary and str(raw_action.get("type", "")) == "visual":
			visual_requests.append(raw_action)
	assert(visual_requests.size() == 1, "lightning must generate one visual request")
	assert(
		CasterSkillVisualRegistry.visual_type(SKILL_ID) == "sky_strike",
		"lightning visual request must dispatch as sky_strike"
	)
	var lifecycle: Dictionary = CasterSkillVisualRegistry.visual_profile(
		SKILL_ID
	).get("lifecycle", {})
	assert(float(lifecycle.get("warning", -1.0)) == 0.0)
	assert(
		float(lifecycle.get("impact", -1.0)) == 0.0,
		"lightning presentation must not add a post-release impact gate"
	)
	assert(float(lifecycle.get("duration", -1.0)) == 0.3)
	var gameplay_actions_before: Array = (
		plan.get("gameplay_actions", []) as Array
	).duplicate(true)
	assert(gameplay_actions_before.size() == 1)
	assert(
		str((gameplay_actions_before[0] as Dictionary).get("type", ""))
		== "targeted_sky_strike"
	)
	assert(
		int(
			(gameplay_actions_before[0] as Dictionary).get(
				"raw_power_after_race",
				(gameplay_actions_before[0] as Dictionary).get("raw_power", 0)
			)
		) > 0,
		"canonical lightning damage action must remain present at release"
	)

	var nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		plan,
		owner.global_position,
		Vector2.RIGHT,
		Color.WHITE,
		target,
		owner
	)
	assert(nodes.size() == 1, "lightning visual request must create one node")
	var effect := nodes[0] as CasterSkillSkyStrikeVisualEffect
	assert(effect != null, "lightning node must use the SkyStrike branch")
	assert(
		plan.get("gameplay_actions", []) == gameplay_actions_before,
		"presentation node creation must not mutate lightning gameplay"
	)
	add_child(effect)

	assert(effect.get_parent() == self)
	assert(effect.visible and effect.modulate.a > 0.99)
	assert(effect.z_index == -1)
	assert(effect.global_position.distance_to(target.global_position.round()) <= 0.5)
	assert(effect._sprites.size() == 1)
	var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
	assert(sprite != null)
	assert(sprite.texture != null, "lightning first frame texture must load")
	assert(sprite.frame_count() == 6)
	assert(sprite.scale.is_equal_approx(EXPECTED_SCALE))
	assert(sprite.modulate.a > 0.99)
	assert(
		sprite.visible,
		"lightning must be visible when add_child returns, before gameplay commit continues"
	)
	assert(
		sprite.is_processing(),
		"lightning playback must start at the canonical release point"
	)
	assert(sprite.current_frame_index == 0)
	assert(not sprite.playback_complete)
	var release_frame_image := sprite.texture.get_image()
	assert(release_frame_image != null and not release_frame_image.is_empty())
	var release_frame_used_rect := release_frame_image.get_used_rect()
	assert(
		release_frame_used_rect.size.x > 4 or release_frame_used_rect.size.y > 1,
		"lightning release frame zero must contain drawable pixels"
	)

	var observed_drawable_frames := PackedInt32Array([sprite.current_frame_index])
	var playback_started := sprite.is_processing()
	var start_msec := Time.get_ticks_msec()
	await get_tree().process_frame
	while Time.get_ticks_msec() - start_msec < 1200:
		await get_tree().process_frame
		if not is_instance_valid(sprite):
			break
		if not sprite.visible:
			continue
		playback_started = playback_started or sprite.is_processing()
		var image := sprite.texture.get_image()
		assert(image != null and not image.is_empty())
		var used_rect := image.get_used_rect()
		if used_rect.size.x > 4 or used_rect.size.y > 1:
			if not observed_drawable_frames.has(sprite.current_frame_index):
				observed_drawable_frames.append(sprite.current_frame_index)

	assert(playback_started, "lightning animation playback never started")
	assert(
		observed_drawable_frames.size() >= 3,
		"lightning did not render enough non-empty animation frames: %s"
		% str(observed_drawable_frames)
	)
	assert(
		observed_drawable_frames.has(0),
		"lightning skipped its first drawable frame before rendering"
	)
	assert(
		not is_instance_valid(effect) or effect.is_queued_for_deletion(),
		"lightning visual did not clean up after playback"
	)

	owner.free()
	target.free()
	print(
		"LIGHTNING_VISUAL_RUNTIME_VISIBILITY_PASS "
		+ "visible_on_release=true frames=%s scale=%s position=%s "
		+ "z=-1 alpha=1 impact=0 duration=0.3 gameplay_action=unchanged"
		% [
			str(observed_drawable_frames),
			str(EXPECTED_SCALE),
			str(Vector2(760.0, 620.0)),
		]
	)
	get_tree().quit(0)
