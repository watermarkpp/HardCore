extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload(
	"res://scripts/caster_skill_visual_registry.gd"
)
const CasterSkillVisualFactory := preload("res://scripts/caster_skill_visual_factory.gd")
const CasterSkillVisualEffect := preload("res://scripts/caster_skill_visual_effect.gd")
const CasterSkillBeamVisualEffect := preload("res://scripts/caster_skill_beam_visual_effect.gd")
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
	return CasterSkillVisualRegistry.profile("wizard.laser").duplicate(true)


func _build_beam_snapshot(
	direction_screen_px: Vector2,
	axis_screen_length_px: float
) -> Dictionary:
	var direction_ground := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		direction_screen_px
	).normalized()
	var snapshot := SkillFootprintSnapshotScript.create_directed_rectangle(
		"wizard.laser",
		"beam_single_active_contract",
		Vector2.ZERO,
		direction_ground,
		1.0,
		1.0,
		0.0,
		8.0,
		4.0,
		"actual"
	).duplicate()
	snapshot["direction_ground_gu"] = direction_ground
	snapshot["axis_screen_direction_px"] = direction_screen_px.normalized()
	snapshot["axis_screen_length_px"] = axis_screen_length_px
	return snapshot


func _spawn_beam_node(
	plan: Dictionary,
	owner: PlayerCharacter,
	target: Node2D,
	single_active_enabled := true,
	target_group := "",
	single_active_scope := "",
	visual_type_overrides: Dictionary = {},
	enable_beam_visual := true,
	direction_screen_px := Vector2.RIGHT
) -> CasterSkillBeamVisualEffect:
	var profile: Dictionary = _beam_profile().duplicate(true)
	var visual_profile: Dictionary = profile.get("visual_profile", {}).duplicate(true)
	var raw_single_active: Variant = visual_profile.get("single_active", {})
	var single_active: Dictionary = (
		raw_single_active if raw_single_active is Dictionary else {}
	)
	single_active["enabled"] = single_active_enabled
	if not target_group.is_empty():
		single_active["group"] = target_group
	if not single_active_scope.is_empty():
		single_active["scope"] = single_active_scope
	visual_profile["single_active"] = single_active
	for key in visual_type_overrides.keys():
		visual_profile[key] = visual_type_overrides[key]
	profile["visual_profile"] = visual_profile
	profile["visual_type"] = "beam"
	profile["enable_beam_visual"] = enable_beam_visual
	var effect := CasterSkillVisualFactory.create(profile)
	assert(effect != null, "beam factory should create effect")
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
	assert(effect is CasterSkillBeamVisualEffect)
	return effect as CasterSkillBeamVisualEffect


func _safe_free(node) -> void:
	if node == null:
		return
	if not is_instance_valid(node):
		return
	node.queue_free()


func _ready() -> void:
	var owner := PlayerCharacter.new()
	var target := Node2D.new()
	owner.global_position = Vector2(16, 18)
	target.global_position = Vector2(160, 20)
	add_child(owner)
	add_child(target)

	# 1. Continuous casting keeps one-beam instance.
	var plan := {
		"success": true,
		"skill_id": "wizard.laser",
		"operation": "canonical_visual_only",
		"origin": Vector2.ZERO,
		"visual_radius_px": 72.0,
		"visual_duration": 0.8,
		"skill_footprint_snapshot": {},
	}
	plan["skill_footprint_snapshot"] = _build_beam_snapshot(Vector2.RIGHT, 72.0)
	var first := _spawn_beam_node(plan, owner, target, true, "beam")
	assert(first != null and first.visible, "first beam should become visible")
	var second := _spawn_beam_node(plan, owner, target, true, "beam")
	await get_tree().process_frame
	assert(
		not is_instance_valid(first) or first.is_queued_for_deletion(),
		"new cast should queue previous beam for deletion"
	)
	assert(
		not second.is_queued_for_deletion(),
		"newest beam should stay active"
	)

	# 2. Different beam groups should not delete each other.
	var first_group := _spawn_beam_node(plan, owner, target, true, "beam_a")
	var second_group := _spawn_beam_node(plan, owner, target, true, "beam_b")
	await get_tree().process_frame
	assert(
		not first_group.is_queued_for_deletion(),
		"beam group A should not be removed by group B"
	)
	assert(
		not second_group.is_queued_for_deletion(),
		"beam group B should not be removed by group A"
	)

	# 3. Fallback path remains using legacy visual effect when Beam visual is off.
	var legacy_profile := _beam_profile().duplicate(true)
	legacy_profile["enable_beam_visual"] = false
	var effect := CasterSkillVisualFactory.create(legacy_profile)
	assert(effect != null, "factory should create legacy effect when beam disabled")
	assert(
		effect is CasterSkillVisualEffect
		and not (effect is CasterSkillBeamVisualEffect),
		"legacy visual effect should be used when beam flag is false"
	)

	# Cleanup.
	_safe_free(first)
	_safe_free(second)
	_safe_free(first_group)
	_safe_free(second_group)
	_safe_free(effect)
	_safe_free(owner)
	_safe_free(target)
	print("BEAM_SINGLE_ACTIVE_TEST_PASS")
	get_tree().quit(0)
