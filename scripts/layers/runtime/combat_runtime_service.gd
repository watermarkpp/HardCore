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
