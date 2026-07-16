extends Node

const TargetingRule := preload("res://scripts/targeting_system.gd")


func select_auto(candidates: Array, origin: Vector2, facing: Vector2, excluded: Node = null, maximum_distance := 520.0) -> Node:
	return TargetingRule.select_target(candidates, origin, facing, null, excluded, maximum_distance)


func front_targets(candidates: Array, origin: Vector2, facing: Vector2) -> Array:
	return TargetingRule.front_targets(candidates, origin, facing)


func valid(target: Node, origin: Vector2) -> bool:
	return TargetingRule.is_valid_target(target, origin)
