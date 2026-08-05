extends Node

const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")


func _ready() -> void:
	var visual_type_profile_cases := {
		"wizard.lightning": "sky_strike",
		"wizard.hell_lightning": "impact_area",
		"wizard.laser": "beam",
		"wizard.hellfire": "impact_area",
	}
	for skill_id: String in visual_type_profile_cases.keys():
		var expected_type: String = visual_type_profile_cases[skill_id]
		var profile: Dictionary = CasterSkillVisualRegistry.profile(skill_id)
		assert(not profile.is_empty(), "%s profile is missing" % skill_id)
		assert(profile.get("status", "") == "formal_primary_client_animation", "%s should keep formal visual runtime status" % skill_id)
		assert(profile.get("role", "") in ["target_effect", "self_area", "line_effect"], "%s has unexpected role" % skill_id)
		assert(CasterSkillVisualRegistry.visual_type(skill_id) == expected_type, "%s visual_type should be %s" % [skill_id, expected_type])
		var visual_profile: Dictionary = CasterSkillVisualRegistry.visual_profile(skill_id)
		assert(not visual_profile.is_empty(), "%s has no visual_profile" % skill_id)
		var animation_profile := CasterSkillVisualRegistry.animation_profile(skill_id)
		assert(int(animation_profile.get("frame_count", 0)) > 0, "%s animation frame_count should be > 0" % skill_id)
		var render := CasterSkillVisualRegistry.render_policy(skill_id)
		assert(str(render.get("anchor_policy", "")).length() > 0, "%s anchor_policy should exist" % skill_id)
		var visual_profile_animation: Dictionary = visual_profile.get("animation", {})
		assert(visual_profile_animation is Dictionary, "%s visual profile animation should be a dictionary" % skill_id)
		var visual_profile_anchor: Dictionary = visual_profile.get("anchor", {})
		if visual_profile_anchor.is_empty():
			assert(false, "%s visual profile anchor should be present" % skill_id)
		if visual_profile_animation.size() > 0:
			assert(float(visual_profile_animation.get("width_scale", 1.0)) > 0.0, "%s visual width_scale must be > 0 when specified" % skill_id)
			assert(float(visual_profile_animation.get("height_scale", 1.0)) > 0.0, "%s visual height_scale must be > 0 when specified" % skill_id)

	assert(CasterSkillVisualRegistry.visual_type("wizard.fireball") == "sprite", "unknown/unconfigured skills should default to sprite")
	print("SKILL_VISUAL_CONTRACT_TEST_OK")
	get_tree().quit(0)
