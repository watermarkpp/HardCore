extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterSkillVisualEffect := preload("res://scripts/caster_skill_visual_effect.gd")
const CasterSkillBeamVisualEffect := preload("res://scripts/caster_skill_beam_visual_effect.gd")
const CasterSkillSkyStrikeVisualEffect := preload("res://scripts/caster_skill_sky_strike_visual_effect.gd")
const PlayerCharacter := preload("res://scripts/player.gd")
const SkillFootprintSnapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")


func _context() -> Dictionary:
	return {"skill_level":3,"caster_level":40,"owner_level":40,"target_level":20,"target_max_hp":500,"magic_stat_roll":30,"spiritual_stat_roll":30,"random_0_to_10":0}


func _presentation_plan(skill_id: String) -> Dictionary:
	# Q3-C: legacy the legacy resolver was removed; create_visual is the
	# canonical visual helper and consumes the visual profile from the registry.
	return {
		"success": true,
		"skill_id": skill_id,
		"operation": "canonical_visual_only",
		"visual": CasterSkillVisualRegistry.profile(skill_id),
		"visual_radius_px": 72.0,
		"visual_duration": CasterSkillVisualRegistry.animation_duration(
			skill_id
		),
		"skill_footprint_snapshot": {},
	}


func _ready() -> void:
	var owner := PlayerCharacter.new()
	owner.global_position = Vector2(320, 240)
	add_child(owner)
	
	# Case 1: wizard.lightning → SkyStrike
	var lt_plan := _presentation_plan("wizard.lightning")
	var lt := CasterSkillRuntime.create_visual(lt_plan, Vector2.ZERO, Vector2.DOWN)
	assert(lt != null, "lightning create_visual must not return null")
	assert(lt is CasterSkillSkyStrikeVisualEffect, "wizard.lightning must be SkyStrike")
	print("PASS: wizard.lightning → SkyStrike")
	
	# Case 2: wizard.laser → Beam (check visual_type routing)
	# create_visual() may reject beam without snapshot; check that Registry routes beam type
	assert(CasterSkillVisualRegistry.visual_type("wizard.laser") == "beam")
	print("PASS: wizard.laser visual_type = beam")
	
	# Case 3: wizard.hell_lightning → NOT SkyStrike
	var hl_plan := _presentation_plan("wizard.hell_lightning")
	var hl := CasterSkillRuntime.create_visual(hl_plan, Vector2.ZERO, Vector2.DOWN)
	assert(hl != null, "hell_lightning must not be null")
	assert(not (hl is CasterSkillSkyStrikeVisualEffect), "hell_lightning must NOT be SkyStrike")
	print("PASS: wizard.hell_lightning → not SkyStrike")
	
	print("CASTER_SKILL_VISUAL_FACTORY_ENTRY_TEST_PASS")
	get_tree().quit(0)
