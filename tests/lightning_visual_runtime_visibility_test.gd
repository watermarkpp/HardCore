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
	add_child(effect)
	await get_tree().process_frame

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
	assert(not sprite.visible, "impact gate should still be pending after ready")
	assert(not sprite.is_processing(), "hidden impact frame must not advance")
	assert(sprite.current_frame_index == 0)
	assert(not sprite.playback_complete)

	var observed_drawable_frames := PackedInt32Array()
	var first_visible_msec := -1
	var playback_started := false
	var start_msec := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_msec < 1200:
		await get_tree().process_frame
		if not is_instance_valid(sprite):
			break
		if not sprite.visible:
			continue
		if first_visible_msec < 0:
			first_visible_msec = Time.get_ticks_msec() - start_msec
		playback_started = playback_started or sprite.is_processing()
		var image := sprite.texture.get_image()
		assert(image != null and not image.is_empty())
		var used_rect := image.get_used_rect()
		if used_rect.size.x > 4 or used_rect.size.y > 1:
			if not observed_drawable_frames.has(sprite.current_frame_index):
				observed_drawable_frames.append(sprite.current_frame_index)

	assert(first_visible_msec >= 0, "lightning never became visible")
	assert(first_visible_msec <= 500, "lightning impact started too late")
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
		+ "first_visible_msec=%d frames=%s scale=%s position=%s z=-1 alpha=1"
		% [
			first_visible_msec,
			str(observed_drawable_frames),
			str(EXPECTED_SCALE),
			str(Vector2(760.0, 620.0)),
		]
	)
	get_tree().quit(0)
