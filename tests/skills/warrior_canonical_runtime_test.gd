extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	assert(not Router.CANONICAL_PRODUCTION_DEFAULT)
	var passive := _execute("warrior.basic_swordsmanship", 3, {"valid_melee_swing": true})
	assert(passive.accepted and passive.effects[0].value == 9)
	assert(passive.proficiency_event == "valid_basic_melee_attack_resolved")
	var slaying := _execute("warrior.slaying_swordsmanship", 3, {
		"has_target": true,
		"force_proc": true,
	})
	assert(slaying.effects[0].flat_dc_bonus == 8)
	assert(slaying.effects[0].flat_accuracy_bonus == 3)
	assert(slaying.proficiency_event == "successful_slaying_proc_on_valid_melee_swing")
	var thrust := _execute("warrior.thrusting", 3, {"has_target": true, "eligible_target_count": 2})
	assert(thrust.effects[1].multiplier == 1.0 and thrust.effects[1].ignore_ac)
	assert(thrust.geometry.length_tiles == 2)
	var half := _execute("warrior.half_moon", 3, {"has_target": true, "eligible_target_count": 4}, 100)
	assert(half.effects[0].maximum_targets == 4)
	assert(is_equal_approx(float(half.effects[0].side_multiplier), 5.0 / 13.0))
	assert(half.effects[0].max_resource_commits == 1)
	var rush := _execute("warrior.wild_rush", 3, {
		"has_target": true,
		"target_level": 30,
		"target_is_boss": false,
		"force_success": true,
	}, 100, 40)
	assert(rush.effect_success and rush.effects[0].push_distance_tiles == 3)
	var blocked_rush := _execute("warrior.wild_rush", 3, {
		"has_target": true,
		"target_level": 30,
		"force_success": true,
		"path_blocked_after_start": true,
		"caster_max_hp": 1000,
	}, 100, 40)
	assert(not blocked_rush.effect_success and blocked_rush.effects[1].amount == 10)
	assert(blocked_rush.proficiency_event.is_empty())
	var boss_rush := _execute("warrior.wild_rush", 3, {
		"has_target": true, "target_level": 1, "target_is_boss": true,
	}, 100, 40)
	assert(not boss_rush.accepted)
	var fire := _execute("warrior.fire_sword", 3, {"charge_consumed": false}, 100)
	assert(fire.effects[0].damage_multiplier == 2.6)
	assert(not fire.effects[0].auto_cast and fire.proficiency_event.is_empty())
	var consumed_fire := _execute("warrior.fire_sword", 3, {"charge_consumed": true}, 100)
	assert(consumed_fire.proficiency_event == "charged_fire_sword_is_consumed_by_valid_melee_attack")
	assert(consumed_fire.timing.body_cast_ms == 600)
	assert(consumed_fire.timing.cooldown_ms == 8000)
	print("WARRIOR_CANONICAL_RUNTIME_PASS: six skills, active fire charge, tile geometry and proficiency events")
	get_tree().quit()


func _execute(
	skill_id: String,
	rank: int,
	target_context: Dictionary,
	mana := 100,
	caster_level := 40
) -> Dictionary:
	if not target_context.has("line_of_sight"):
		target_context["line_of_sight"] = true
	var request := Request.create(
		skill_id,
		rank,
		caster_level,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		target_context,
		{"mana": mana, "materials": {}},
		11
	)
	return Router.execute(request)
