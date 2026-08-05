extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualFactory := preload("res://scripts/caster_skill_visual_factory.gd")
const CasterSkillVisualEffect := preload("res://scripts/caster_skill_visual_effect.gd")
const CasterSkillBeamVisualEffect := preload("res://scripts/caster_skill_beam_visual_effect.gd")
const PlayerCharacter := preload("res://scripts/player.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")


func _context() -> Dictionary:
	return {"skill_level": 3, "caster_level": 40, "owner_level": 40, "target_level": 20, "target_max_hp": 500, "magic_stat_roll": 30, "spiritual_stat_roll": 30, "random_0_to_10": 0}


func _beam_profile() -> Dictionary:
	return CasterSkillRuntime.resolve("wizard.laser", _context()).get("visual", {}).duplicate(true)


func _build_beam_snapshot(dir: Vector2, length: float) -> Dictionary:
	var dg := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(dir).normalized()
	var s := SkillFootprintSnapshotScript.create_directed_rectangle("wizard.laser", "beam_test", Vector2.ZERO, dg, 1.0, 1.0, 0.0, 8.0, 4.0, "actual").duplicate()
	s["direction_ground_gu"] = dg; s["axis_screen_direction_px"] = dir.normalized(); s["axis_screen_length_px"] = length
	return s


func _safe_free(node) -> void:
	if is_instance_valid(node): node.queue_free()


func _ready() -> void:
	var owner := PlayerCharacter.new(); var target := Node2D.new()
	owner.global_position = Vector2(16, 18); target.global_position = Vector2(160, 20)
	add_child(owner); add_child(target)

	var plan := CasterSkillRuntime.resolve("wizard.laser", _context())
	plan["skill_footprint_snapshot"] = _build_beam_snapshot(Vector2.RIGHT, 72.0)

	# 1. Same group: old beam queued.
	var profile := _beam_profile()
	profile["visual_type"] = "beam"; profile["enable_beam_visual"] = true
	var first := CasterSkillVisualFactory.create(profile)
	first.setup(owner.global_position, "wizard.laser", 72.0, 0.8, Vector2.RIGHT, target, "", {"visual_type": "beam"})
	add_child(first)
	var second := CasterSkillVisualFactory.create(profile)
	second.setup(owner.global_position, "wizard.laser", 72.0, 0.8, Vector2.RIGHT, target, "", {"visual_type": "beam"})
	add_child(second)
	await get_tree().process_frame
	assert(not is_instance_valid(first) or first.is_queued_for_deletion(), "old beam queued")

	# 2. Different groups survive.
	var fa := CasterSkillVisualFactory.create(profile); fa.setup(owner.global_position, "wizard.laser", 72.0, 0.8, Vector2.RIGHT, target, "", {"visual_type": "beam"}); add_child(fa)
	var fb := CasterSkillVisualFactory.create(profile); fb.setup(owner.global_position, "wizard.laser", 72.0, 0.8, Vector2.RIGHT, target, "", {"visual_type": "beam"}); add_child(fb)
	await get_tree().process_frame
	assert(not is_instance_valid(fa) or not fa.is_queued_for_deletion(), "group A ok")
	assert(not is_instance_valid(fb) or not fb.is_queued_for_deletion(), "group B ok")

	# 3. Legacy fallback.
	var lp := _beam_profile(); lp["enable_beam_visual"] = false
	assert(CasterSkillVisualFactory.create(lp) != null, "legacy ok")

	for n in [first, second, fa, fb, owner, target]: _safe_free(n)
	print("BEAM_SINGLE_ACTIVE_TEST_PASS"); get_tree().quit(0)
