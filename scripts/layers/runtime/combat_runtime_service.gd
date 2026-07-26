extends Node

const CombatResolutionRulesScript := preload("res://scripts/combat_resolution_rules.gd")

func face_target(actor: Node2D, target: Node2D) -> Vector2:
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return Vector2.ZERO
	var direction := actor.global_position.direction_to(target.global_position)
	if direction.length_squared() > 0.01:
		if actor.has_method("set_combat_facing"):
			actor.call("set_combat_facing", direction)
		else:
			actor.set("facing", direction)
	return direction


func apply_damage(target: Node, amount: int) -> bool:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return false
	target.take_damage(maxi(1, amount))
	return true


func apply_enemy_physical_damage(target: Node, amount: int, source_actor: Node2D = null) -> bool:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return false
	target.call("take_damage", maxi(1, amount), source_actor)
	return true


func apply_enemy_direct_spell_damage(
	target: Node,
	stable_skill_id: String,
	raw_damage: int,
	source_actor: Node2D,
	rng: RandomNumberGenerator,
	magic_defense_adapter: Callable
) -> Dictionary:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return {
			"success": false,
			"failure_reason": "target_missing_damage_pipeline",
			"final_damage": 0,
		}
	var target_stats: Dictionary = _target_stats_with_runtime_buffs(target)
	var resolution := CombatResolutionRulesScript.resolve_direct_spell_damage(
		stable_skill_id,
		maxi(0, raw_damage),
		target_stats,
		rng.randi_range(0, CombatResolutionRulesScript.ANTI_MAGIC_ROLL_SIDES - 1),
		magic_defense_adapter
	)
	var final_damage := int(resolution.get("final_damage", 0))
	if final_damage > 0:
		target.call("take_damage", final_damage, source_actor)
	var result := resolution.duplicate(true)
	result["success"] = final_damage > 0
	return result


func _target_stats_with_runtime_buffs(target: Node) -> Dictionary:
	var raw_stats: Variant = target.get("monster_data")
	var result: Dictionary = raw_stats.duplicate(true) if raw_stats is Dictionary else {}
	var red_poison: Variant = target.get_meta("canonical_red_poison", {})
	if not red_poison is Dictionary:
		return result
	if Time.get_ticks_msec() >= int(red_poison.get("expires_at_ms", 0)):
		target.remove_meta("canonical_red_poison")
		return result
	var reduction := maxi(0, int(red_poison.get("flat_reduction", 0)))
	for field: String in ["magic_defense_min", "magic_defense_max", "mdefMin", "mdefMax", "MinMAC", "MaxMAC"]:
		if result.has(field):
			result[field] = maxi(0, int(result[field]) - reduction)
	result["runtime_buff_contract"] = "buff.taoist.red_poison.v1"
	return result


func apply_player_direct_spell_damage(
	target: Node,
	stable_skill_id: String,
	raw_damage: int,
	anti_magic_roll := -1,
	magic_defense_roll := -1
) -> Dictionary:
	if not is_instance_valid(target) or not target.has_method("take_direct_spell_damage"):
		return {
			"success": false,
			"failure_reason": "target_missing_direct_spell_pipeline",
			"final_damage": 0,
		}
	var resolution: Variant = target.call(
		"take_direct_spell_damage",
		stable_skill_id,
		maxi(0, raw_damage),
		anti_magic_roll,
		magic_defense_roll
	)
	if not resolution is Dictionary:
		return {
			"success": false,
			"failure_reason": "invalid_direct_spell_resolution",
			"final_damage": 0,
		}
	var result := (resolution as Dictionary).duplicate(true)
	result["success"] = true
	return result
