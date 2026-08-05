extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")


func _context() -> Dictionary:
	return {
		"skill_level": 3,
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"magic_stat_roll": 30,
		"spiritual_stat_roll": 30,
	}


func _ready() -> void:
	var skill_id := "wizard.laser"
	var merged_profile: Dictionary = CasterSkillVisualRegistry.profile(skill_id)
	var merged_animation: Dictionary = CasterSkillVisualRegistry.animation_profile(skill_id)
	var resolved_plan: Dictionary = CasterSkillRuntime.resolve(skill_id, _context())
	var visual_profile: Dictionary = resolved_plan.get("visual", {})
	var profile_animation: Dictionary = CasterSkillVisualRegistry.visual_profile(skill_id).get("animation", {})

	assert(
		merged_profile.get("status", "") == "formal_primary_client_animation",
		"%s profile should remain formal runtime"
		% skill_id
	)
	assert(merged_animation is Dictionary, "%s animation profile should be dictionary" % skill_id)
	assert(str(merged_animation.get("contract", "")) != "", "%s merged contract should keep runtime animation contract" % skill_id)
	assert(int(merged_animation.get("frame_count", 0)) > 0, "%s merged frame_count should stay from manifest" % skill_id)
	assert(merged_animation.get("sequences") is Array and not merged_animation.get("sequences").is_empty(), "%s merged sequences should stay from manifest" % skill_id)

	assert(visual_profile is Dictionary, "%s visual profile should exist in resolved plan" % skill_id)
	assert(profile_animation is Dictionary and profile_animation.size() > 0, "%s visual profile animation should exist" % skill_id)
	assert(profile_animation.get("scale_mode", "") != "", "%s visual profile animation.scale_mode should remain available" % skill_id)
	assert(visual_profile.get("animation", {}).get("contract", "") == "caster_skill_animation.v1", "%s resolved plan should keep runtime animation contract" % skill_id)
	assert(visual_profile.get("visual_type", "") == "beam", "%s should remain beam after merge" % skill_id)

	print("VISUAL_PROFILE_MERGE_CONTRACT_TEST_PASS")
	get_tree().quit(0)
