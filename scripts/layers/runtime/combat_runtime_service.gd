extends Node


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
