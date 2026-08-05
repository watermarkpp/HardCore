extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterSkillVisualFactory := preload("res://scripts/caster_skill_visual_factory.gd")
const CasterSkillBeamVisualEffect := preload(
	"res://scripts/caster_skill_beam_visual_effect.gd"
)
const CasterSkillAnimationPlayer := preload(
	"res://scripts/caster_skill_animation_player.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")


const SKILL_ID := "wizard.laser"
const EMPTY_SPACE_LENGTH_GU := 8.0


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


func _beam_profile(width_scale := 1.0) -> Dictionary:
	var profile := CasterSkillVisualRegistry.profile(SKILL_ID).duplicate(true)
	var visual_profile: Dictionary = CasterSkillVisualRegistry.visual_profile(SKILL_ID)
	if not visual_profile.is_empty():
		var visual_animation: Variant = visual_profile.get("animation", {})
		var visual_animation_profile: Dictionary = (
			visual_animation.duplicate(true) if visual_animation is Dictionary else {}
		)
		visual_animation_profile["width_scale"] = width_scale
		visual_profile["animation"] = visual_animation_profile
		profile["visual_profile"] = visual_profile
		profile.merge(visual_profile, true)
	profile["enable_beam_visual"] = true
	return profile


func _build_snapshot(
	direction_screen_px: Vector2,
	actual_length_gu: float,
	declared_length_gu: float
) -> Dictionary:
	var direction_ground := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		direction_screen_px
	).normalized()
	var snapshot := SkillFootprintSnapshotScript.create_directed_rectangle(
		SKILL_ID,
		"beam_runtime_empty_space",
		Vector2.ZERO,
		direction_ground,
		actual_length_gu,
		1.0,
		0.0,
		declared_length_gu,
		actual_length_gu
	).duplicate()
	snapshot["axis_screen_length_px"] = (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * actual_length_gu
		).length()
	)
	snapshot["declared_axis_screen_length_px"] = (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * declared_length_gu
		).length()
	)
	return snapshot


func _spawn_beam(
	direction_screen_px: Vector2,
	actual_length_gu: float,
	declared_length_gu: float,
	width_scale := 1.0
) -> CasterSkillBeamVisualEffect:
	var snapshot := _build_snapshot(
		direction_screen_px,
		actual_length_gu,
		declared_length_gu
	)
	var profile := _beam_profile(width_scale)
	var effect := CasterSkillVisualFactory.create(profile)
	assert(effect is CasterSkillBeamVisualEffect)
	effect.setup(
		Vector2.ZERO,
		SKILL_ID,
		72.0,
		0.8,
		direction_screen_px,
		null,
		"",
		{
			"skill_footprint_snapshot": snapshot,
			"visual_profile": profile,
		}
	)
	add_child(effect)
	return effect as CasterSkillBeamVisualEffect


func _assert_length_and_direction(
	effect: CasterSkillBeamVisualEffect,
	direction: Vector2,
	expected_length_px: float
) -> void:
	assert(
		absf(effect._beam_length_px - expected_length_px) <= 2.0,
		"beam length should come from axis length"
	)
	var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
	assert(sprite != null)
	assert(
		sprite.direction_index == CasterSkillVisualRegistry.direction_index(direction),
		"direction index should match registry for %s" % str(direction)
	)


func _assert_width_from_profile(
	effect: CasterSkillBeamVisualEffect,
	expected_width_scale: float
) -> void:
	var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
	assert(sprite != null)
	var metadata := effect.beam_debug_metadata()
	print("[BeamWidthMetadata] %s" % JSON.stringify(metadata))
	assert(is_equal_approx(float(metadata.get("width_scale", 0.0)), expected_width_scale))
	assert(
		effect._beam_length_px > 0.0
	)
	assert(sprite.scale.length() > 0.0)


func _safe_free(node: Variant) -> void:
	if node == null:
		return
	if is_instance_valid(node):
		node.queue_free()


func _ready() -> void:
	assert(CasterSkillVisualRegistry.visual_type(SKILL_ID) == "beam")
	var profile := _beam_profile()
	var visual_profile: Dictionary = CasterSkillVisualRegistry.visual_profile(SKILL_ID)
	assert(not visual_profile.is_empty())
	assert(visual_profile.get("geometry_binding", {}).get("length", "") == "actual_length")
	assert(visual_profile.get("geometry_binding", {}).get("direction", "") == "snapshot_axis")
	assert(profile.get("visual_type", "") == "beam")

	var resolved_plan := CasterSkillRuntime.resolve(SKILL_ID, _context())
	var direction_vectors: Array[Vector2] = []
	for direction_index: int in range(8):
		direction_vectors.append(DirectionSpace.projected_screen_direction_px(direction_index))

	# A. 空旷场景：declared=8 resolved=8
	for direction: Vector2 in direction_vectors:
		var direction_case_label := str(direction)
		var resolved_snapshot := _build_snapshot(
			direction,
			EMPTY_SPACE_LENGTH_GU,
			EMPTY_SPACE_LENGTH_GU
		)
		var effect := _spawn_beam(direction, EMPTY_SPACE_LENGTH_GU, EMPTY_SPACE_LENGTH_GU)
		await get_tree().process_frame
		var expected_length_px: float = float(
			resolved_snapshot.get("axis_screen_length_px", 0.0)
		)
		_assert_length_and_direction(
			effect,
			direction,
			expected_length_px
		)
		var effect_metadata := effect.beam_debug_metadata()
		print(
			"[SkillVisual][BeamEmpty] direction=%s declared=%s resolved=%s anchor=%s length_source=%s"
			% [
				direction_case_label,
				resolved_snapshot.get("declared_axis_screen_length_px", 0.0),
				expected_length_px,
				str(effect_metadata.get("anchor_policy", "")),
				str(effect_metadata.get("length_source", "")),
			]
		)
		_safe_free(effect)

	# B. 方向覆盖: N/NE/E/SE/S/SW/W/NW
	var focus_directions := [
		DirectionSpace.projected_screen_direction_px(0),
		DirectionSpace.projected_screen_direction_px(1),
		DirectionSpace.projected_screen_direction_px(2),
		DirectionSpace.projected_screen_direction_px(3),
		DirectionSpace.projected_screen_direction_px(4),
		DirectionSpace.projected_screen_direction_px(5),
		DirectionSpace.projected_screen_direction_px(6),
		DirectionSpace.projected_screen_direction_px(7),
	]
	for direction: Vector2 in focus_directions:
		var effect := _spawn_beam(direction, EMPTY_SPACE_LENGTH_GU, EMPTY_SPACE_LENGTH_GU)
		await get_tree().process_frame
		assert(effect != null)
		var expected_length_snapshot := _build_snapshot(direction, EMPTY_SPACE_LENGTH_GU, EMPTY_SPACE_LENGTH_GU)
		var expected_length_px := float(expected_length_snapshot.get("axis_screen_length_px", 0.0))
		_assert_length_and_direction(effect, direction, expected_length_px)
		_safe_free(effect)

	# C. Width 由 profile.width_scale 驱动（不是 desired_cross_extent）
	var width_scale_case := 1.28
	var width_effect := _spawn_beam(
		DirectionSpace.projected_screen_direction_px(2),
		EMPTY_SPACE_LENGTH_GU,
		EMPTY_SPACE_LENGTH_GU,
		width_scale_case
	)
	await get_tree().process_frame
	_assert_width_from_profile(width_effect, width_scale_case)
	_safe_free(width_effect)

	print("BEAM_RUNTIME_EMPTY_SPACE_TEST_PASS")
	get_tree().quit(0)
