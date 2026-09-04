extends Node

const TargetingRule := preload("res://scripts/targeting_system.gd")


func select_auto_ground_gu(
	candidates: Array[Dictionary],
	origin_ground_gu: Vector2,
	facing_ground: Vector2,
	excluded: Node = null,
	maximum_range_gu := TargetingRule.DEFAULT_SEARCH_RANGE_GU
) -> Node:
	return TargetingRule.select_target_ground_gu(
		candidates,
		origin_ground_gu,
		facing_ground,
		excluded,
		maximum_range_gu
	)


func front_targets_ground_gu(
	candidates: Array[Dictionary],
	origin_ground_gu: Vector2,
	facing_ground: Vector2,
	maximum_range_gu := TargetingRule.DEFAULT_SEARCH_RANGE_GU
) -> Array[Node]:
	return TargetingRule.front_targets_ground_gu(
		candidates,
		origin_ground_gu,
		facing_ground,
		maximum_range_gu
	)


func valid_ground_gu(
	target: Node,
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	maximum_range_gu := TargetingRule.RELEASE_RANGE_GU
) -> bool:
	return TargetingRule.is_valid_target_ground_gu(
		target,
		origin_ground_gu,
		target_ground_gu,
		maximum_range_gu
	)
