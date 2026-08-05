extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterSkillVisualFactory := preload("res://scripts/caster_skill_visual_factory.gd")
const CasterSkillVisualEffect := preload("res://scripts/caster_skill_visual_effect.gd")
const CasterSkillBeamVisualEffect := preload(
	"res://scripts/caster_skill_beam_visual_effect.gd"
)
const CasterSkillAnimationPlayer := preload(
	"res://scripts/caster_skill_animation_player.gd"
)
const PlayerCharacter := preload("res://scripts/player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)


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


func _beam_profile() -> Dictionary:
	return CasterSkillVisualRegistry.profile("wizard.laser")


func _build_beam_snapshot(
	direction_screen_px: Vector2,
	axis_screen_length_px: float,
	declared_axis_screen_length_px := 8.0
) -> Dictionary:
	var direction_ground := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		direction_screen_px
	).normalized()
	var snapshot := SkillFootprintSnapshotScript.create_directed_rectangle(
		"wizard.laser",
		"beam_contract_test",
		Vector2.ZERO,
		direction_ground,
		1.0,
		1.0,
		0.0,
		8.0,
		4.0,
		"actual"
	).duplicate()
	var axis_unit := direction_screen_px.normalized()
	snapshot["direction_ground_gu"] = direction_ground
	snapshot["axis_screen_direction_px"] = axis_unit
	snapshot["axis_screen_length_px"] = axis_screen_length_px
	snapshot["declared_axis_screen_length_px"] = declared_axis_screen_length_px
	snapshot["declared_length_px"] = declared_axis_screen_length_px
	return snapshot


func _spawn_beam_node(
	plan: Dictionary,
	owner: PlayerCharacter,
	target: Node2D,
	enable_beam_visual := true,
	direction_screen_px := Vector2.RIGHT,
	expect_beam := true
) -> Node:
	var profile := _beam_profile().duplicate(true)
	profile["enable_beam_visual"] = enable_beam_visual
	var effect := CasterSkillVisualFactory.create(profile)
	assert(effect != null, "beam factory should create a visual effect")
	effect.setup(
		plan.get("origin", owner.global_position),
		"wizard.laser",
		float(plan.get("visual_radius_px", 72.0)),
		float(plan.get("visual_duration", 0.8)),
		direction_screen_px,
		target,
		"",
		{
			"skill_footprint_snapshot": plan.get("skill_footprint_snapshot", {}),
			"visual_profile": profile,
			"visual_type": str(profile.get("visual_type", "")),
		}
	)
	add_child(effect)
	assert(
		(effect is CasterSkillBeamVisualEffect) == expect_beam,
		"beam factory should honor enable flag"
	)
	return effect


func _spawn_default_visual(plan: Dictionary, owner: PlayerCharacter) -> CasterSkillVisualEffect:
	var target := owner
	var nodes := CasterSkillRuntime.create_cast_nodes(
		plan,
		owner.global_position,
		target.global_position,
		Vector2.RIGHT,
		Color.WHITE,
		target,
		owner
	)
	assert(nodes.size() == 1, "visual spawn count should be 1")
	var node := nodes[0]
	assert(node is CasterSkillVisualEffect)
	return node as CasterSkillVisualEffect


func _assert_beam_forward_extent(sprite: CasterSkillAnimationPlayer, axis: Vector2, expected: float) -> void:
	var axis_unit := (
		axis.normalized()
		if axis.length_squared() > 0.000001
		else Vector2.RIGHT
	)
	assert(
		abs(
			sprite.fitted_visual_forward_extent(axis_unit) - expected
		) <= 0.001,
		"beam should scale visual forward extent from snapshot actual length"
	)


func _assert_beam_direction(sprite: CasterSkillAnimationPlayer, axis: Vector2) -> void:
	assert(
		sprite.direction_index == CasterSkillVisualRegistry.direction_index(axis),
		"beam sprite direction should come from snapshot axis, not skill call argument"
	)


func _ready() -> void:
	assert(CasterSkillVisualRegistry.visual_type("wizard.laser") == "beam")
	var beam_profile := _beam_profile()
	var flag_source: Dictionary = beam_profile.get("visual_profile", {})
	var enable_beam_visual_flag := bool(
		beam_profile.get(
			"enable_beam_visual",
			flag_source.get("enable_beam_visual", false)
		)
	)
	assert(enable_beam_visual_flag, "beam flag should exist and be true by default")

	var owner := PlayerCharacter.new()
	var target := Node2D.new()
	owner.global_position = Vector2(16, 18)
	target.global_position = Vector2(160, 20)
	add_child(owner)
	add_child(target)

	# A. Profile should use beam type.
	# B. Length should come from actual snapshot length and not declared length.
	var resolved_plan := CasterSkillRuntime.resolve("wizard.laser", _context())
	for snapshot_case in [
		{"declared": 8.0, "resolved": 4.0},
		{"declared": 8.0, "resolved": 8.0},
	]:
		var plan := resolved_plan.duplicate(true)
		var declared_length_case: float = float(snapshot_case.get("declared", 8.0))
		var resolved_length_case: float = float(snapshot_case.get("resolved", 8.0))
		plan["skill_footprint_snapshot"] = _build_beam_snapshot(
			Vector2.RIGHT,
			resolved_length_case,
			declared_length_case
		)
		var snapshot: Dictionary = plan.get("skill_footprint_snapshot", {}) as Dictionary
		assert(snapshot is Dictionary)
		assert(
			is_equal_approx(
				float(snapshot.get("axis_screen_length_px", 0.0)),
				resolved_length_case
			),
			"snapshot should expose resolved length"
		)
		if not is_equal_approx(declared_length_case, resolved_length_case):
			assert(
				is_equal_approx(
					float(snapshot.get("declared_axis_screen_length_px", 0.0)),
					declared_length_case
				),
				"snapshot should preserve declared length metadata when different"
			)
		var node := _spawn_beam_node(
			plan,
			owner,
			target,
			true,
			Vector2.RIGHT
		) as CasterSkillBeamVisualEffect
		var sprite := node._sprites[0] as CasterSkillAnimationPlayer
		assert(sprite != null)
		_assert_beam_forward_extent(sprite, Vector2.RIGHT, resolved_length_case)
		node.free()

	# C. Direction should consume snapshot axis.
	var direction_cases := [
		Vector2(0, -1),
		Vector2(1, -1),
		Vector2(1, 0),
		Vector2(1, 1),
		Vector2(0, 1),
		Vector2(-1, 1),
		Vector2(-1, 0),
		Vector2(-1, -1),
	]
	for direction_case in direction_cases:
		var plan := resolved_plan.duplicate(true)
		plan["skill_footprint_snapshot"] = _build_beam_snapshot(
			direction_case,
			72.0
		)
		var node := _spawn_beam_node(
			plan,
			owner,
			target,
			true,
			Vector2.RIGHT
		) as CasterSkillBeamVisualEffect
		var sprite := node._sprites[0] as CasterSkillAnimationPlayer
		assert(sprite != null)
		_assert_beam_direction(sprite, direction_case)
		node.free()

	# D. Beam fallback should remain old path when enable flag is false.
	var profile := _beam_profile().duplicate(true)
	profile["enable_beam_visual"] = false
	var fallback_node := CasterSkillVisualFactory.create(profile)
	assert(fallback_node is CasterSkillVisualEffect)
	fallback_node.free()
	var legacy_node := _spawn_beam_node(
		resolved_plan,
		owner,
		target,
		false,
		Vector2.RIGHT,
		false
	)
	legacy_node.free()

	owner.free()
	target.free()
	print("BEAM_VISUAL_CONTRACT_TEST_PASS")
	get_tree().quit(0)
