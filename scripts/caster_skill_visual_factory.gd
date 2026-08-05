class_name CasterSkillVisualFactory
extends RefCounted

const CasterSkillVisualEffectScript := preload("res://scripts/caster_skill_visual_effect.gd")
const CasterSkillSkyStrikeVisualEffectScript := preload(
	"res://scripts/caster_skill_sky_strike_visual_effect.gd"
)
const CasterSkillBeamVisualEffectScript := preload(
	"res://scripts/caster_skill_beam_visual_effect.gd"
)


static func create(profile: Dictionary) -> CasterSkillVisualEffect:
	var visual_type := str(profile.get("visual_type", ""))
	var enable_beam_visual := bool(profile.get("enable_beam_visual", false))
	match visual_type:
		"sky_strike":
			return CasterSkillSkyStrikeVisualEffectScript.new()
		"beam":
			if enable_beam_visual:
				return CasterSkillBeamVisualEffectScript.new()
			return CasterSkillVisualEffectScript.new()
		_:
			return CasterSkillVisualEffectScript.new()
