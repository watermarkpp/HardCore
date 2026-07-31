extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	assert(Router.CANONICAL_PRODUCTION_DEFAULT)
	var thrust_definition := Loader.skill("warrior.thrusting")
	var half_definition := Loader.skill("warrior.half_moon")
	var fire_definition := Loader.skill("warrior.fire_sword")
	assert(thrust_definition.geometry.maximum_targets == -1)
	assert(half_definition.geometry.maximum_targets == -1)
	assert(fire_definition.geometry.maximum_targets == 1)
	assert(
		thrust_definition.geometry.target_count_policy_id
		== "gameplay.warrior.melee_target_count.v1"
	)
	assert(
		half_definition.geometry.target_count_policy_id
		== "gameplay.warrior.melee_target_count.v1"
	)
	var passive := _execute("warrior.basic_swordsmanship", 3, {"valid_melee_swing": true})
	assert(passive.accepted and passive.effects[0].value == 9)
	assert(passive.proficiency_event == "valid_basic_melee_attack_resolved")
	var slaying := _execute("warrior.slaying_swordsmanship", 3, {
		"has_target": true,
		"valid_melee_swing": true,
		"force_proc": true,
	})
	assert(slaying.effects[0].flat_damage_bonus == 8)
	assert(slaying.effects[0].flat_accuracy_bonus == 3)
	assert(slaying.effects[0].proc_denominator == 4 and slaying.effects[0].proc_roll == 0)
	assert(slaying.proficiency_event == "successful_slaying_proc_on_valid_melee_swing")
	var slaying_definition := Loader.skill("warrior.slaying_swordsmanship")
	assert(slaying_definition.ranks.map(func(rank: Dictionary) -> int:
		return int(rank.player_level_required)
	) == [19, 19, 22, 24])
	assert(slaying_definition.ranks.map(func(rank: Dictionary) -> int:
		return int(rank.proficiency_required_to_reach_rank)
	) == [0, 4000, 8000, 16000])
	var denominators := [7, 6, 5, 4]
	var damage_bonuses := [2, 4, 6, 8]
	for body_mode: String in ["normal", "thrust", "half_moon", "fire"]:
		for rank in range(4):
			var layered_proc := Router.resolve_warrior_melee_modifiers({
				"body_mode": body_mode,
				"basic_sword_learned": true,
				"basic_sword_rank": 3,
				"slaying_learned": true,
				"slaying_rank": rank,
				"valid_melee_swing": true,
				"slaying_proc_roll": 0,
			})
			assert(layered_proc.contract_id == Router.WARRIOR_MELEE_MODIFIER_CONTRACT_ID)
			assert(layered_proc.body_mode == body_mode)
			assert(layered_proc.body_mode_agnostic)
			assert(layered_proc.scope == "all_hits_of_selected_melee_action")
			assert(layered_proc.requires_one_call_per_action)
			assert(layered_proc.slaying_proc and layered_proc.slaying_proc_roll_count == 1)
			assert(layered_proc.slaying_proc_denominator == denominators[rank])
			assert(layered_proc.slaying_proc_roll == 0)
			assert(layered_proc.flat_dc_bonus_before_body_formula == 0)
			assert(layered_proc.flat_damage_bonus_after_body_formula == damage_bonuses[rank])
			assert(layered_proc.flat_accuracy_bonus == 9 + rank, "攻杀准确必须常驻进入每个目标命中检查")
			assert(
				_body_damage(body_mode, 100) + layered_proc.flat_damage_bonus_after_body_formula
				== _expected_proc_damage(body_mode, rank)
			)
			assert(layered_proc.proficiency_events.size() == 2)
			var no_proc := Router.resolve_warrior_melee_modifiers({
				"body_mode": body_mode,
				"basic_sword_learned": true,
				"basic_sword_rank": 3,
				"slaying_learned": true,
				"slaying_rank": rank,
				"valid_melee_swing": true,
				"slaying_proc_roll": denominators[rank] - 1,
			})
			assert(not no_proc.slaying_proc and no_proc.slaying_proc_roll_count == 1)
			assert(no_proc.slaying_proc_roll == denominators[rank] - 1)
			assert(no_proc.flat_damage_bonus_after_body_formula == 0)
			assert(no_proc.flat_accuracy_bonus == 9 + rank, "未触发攻杀仍必须保留常驻准确")
			assert(no_proc.proficiency_events.size() == 1)
	_verify_multi_target_shared_action_layer("thrust")
	_verify_multi_target_shared_action_layer("half_moon")
	var empty_swing := Router.resolve_warrior_melee_modifiers({
		"basic_sword_learned": true,
		"basic_sword_rank": 3,
		"slaying_learned": true,
		"slaying_rank": 3,
		"valid_melee_swing": false,
		"force_slaying_proc": true,
	})
	assert(empty_swing.slaying_proc_roll_count == 0 and not empty_swing.slaying_proc)
	assert(empty_swing.flat_accuracy_bonus == 12, "空挥不掷骰，但攻杀准确仍是常驻被动")
	assert(empty_swing.proficiency_events.is_empty())
	var thrust := _execute("warrior.thrusting", 3, {"has_target": true, "eligible_target_count": 2})
	assert(thrust.effects[1].multiplier == 1.0 and thrust.effects[1].ignore_ac)
	assert(thrust.effects[0].maximum_targets == -1)
	assert(thrust.effects[1].maximum_targets == -1)
	assert(thrust.effects[0].target_count_policy_id == "gameplay.warrior.melee_target_count.v1")
	assert(thrust.geometry.length_tiles == 2)
	var half := _execute("warrior.half_moon", 3, {"has_target": true, "eligible_target_count": 4}, 100)
	assert(half.effects[0].maximum_targets == -1)
	assert(half.effects[0].target_count_policy_id == "gameplay.warrior.melee_target_count.v1")
	assert(is_equal_approx(float(half.effects[0].side_multiplier), 5.0 / 13.0))
	assert(half.effects[0].max_resource_commits == 1)
	var rush := _execute("warrior.wild_rush", 3, {
		"has_target": true,
		"target_level": 30,
		"target_is_boss": false,
		"resolved_push_distance_tiles": 3,
	}, 100, 40)
	assert(rush.effect_success and rush.effects[0].push_distance_tiles == 3)
	assert(rush.effects[0].resolved_push_distance_tiles == 3)
	assert(rush.effects[0].damage_amount == 0 and rush.effects[0].self_damage_amount == 0)
	var blocked_rush := _execute("warrior.wild_rush", 3, {
		"has_target": true,
		"target_level": 30,
		"resolved_push_distance_tiles": 3,
		"dynamic_blocker_in_corridor": true,
	}, 100, 40)
	assert(blocked_rush.accepted and not blocked_rush.effect_success)
	assert(blocked_rush.effects.size() == 1 and blocked_rush.effects[0].resolved_push_distance_tiles == 0)
	assert(blocked_rush.proficiency_event.is_empty())
	var partial_rush := _execute("warrior.wild_rush", 0, {
		"has_target": true,
		"target_level": 30,
		"resolved_push_distance_tiles": 2,
	}, 100, 40)
	assert(partial_rush.effect_success and partial_rush.effects[0].resolved_push_distance_tiles == 2)
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
	print("WARRIOR_CANONICAL_RUNTIME_PASS: six skills, deterministic atomic wild rush, active fire charge and proficiency events")
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


func _body_damage(body_mode: String, augmented_base_damage: int) -> int:
	match body_mode:
		"half_moon":
			return roundi(float(augmented_base_damage) * (5.0 / 13.0))
		"fire":
			return roundi(float(augmented_base_damage) * 2.6)
	return augmented_base_damage


func _expected_proc_damage(body_mode: String, rank: int) -> int:
	return _body_damage(body_mode, 100) + 2 * (rank + 1)


func _verify_multi_target_shared_action_layer(body_mode: String) -> void:
	var action_layer := Router.resolve_warrior_melee_modifiers({
		"body_mode": body_mode,
		"basic_sword_learned": false,
		"slaying_learned": true,
		"slaying_rank": 2,
		"valid_melee_swing": true,
		"slaying_proc_roll": 0,
	})
	assert(action_layer.slaying_proc and action_layer.slaying_proc_roll_count == 1)
	assert(action_layer.slaying_proc_denominator == 5 and action_layer.slaying_proc_roll == 0)
	assert(action_layer.flat_accuracy_bonus == 2)
	assert(action_layer.flat_damage_bonus_after_body_formula == 6)
	for target_index in range(3):
		var damage_without_proc: int = _body_damage(body_mode, 100 + target_index)
		var damage_with_proc: int = (
			damage_without_proc
			+ int(action_layer.flat_damage_bonus_after_body_formula)
		)
		assert(damage_with_proc - damage_without_proc == 6)
	assert(action_layer.slaying_proc_roll_count == 1, "半月/刺杀多目标不得重复掷攻杀")
