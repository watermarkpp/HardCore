extends RefCounted

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")

const CONTRACT_ID := "combat.targeting.euclidean_gu.v2"
const DEFAULT_SEARCH_RANGE_GU := 12.0
const RELEASE_RANGE_GU := 12.0


static func is_valid_target_ground_gu(
	target: Node,
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	maximum_range_gu := RELEASE_RANGE_GU
) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and GroundUnitSpace.is_within_range_gu(
			origin_ground_gu,
			target_ground_gu,
			maximum_range_gu
		)
	)


static func select_target_ground_gu(
	candidates: Array[Dictionary],
	origin_ground_gu: Vector2,
	preferred_direction_ground: Vector2,
	excluded_target: Node = null,
	maximum_range_gu := DEFAULT_SEARCH_RANGE_GU
) -> Node:
	var best: Node
	var best_band := 99
	var best_distance_squared_gu := INF
	var best_alignment := -2.0
	var best_instance_id := 0x7FFFFFFFFFFFFFFF
	var facing_ground := (
		preferred_direction_ground.normalized()
		if preferred_direction_ground.length_squared()
		> GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU
		else Vector2.DOWN
	)
	for candidate: Dictionary in candidates:
		var target := candidate.get("target") as Node
		if (
			not is_instance_valid(target)
			or target == excluded_target
			or target.is_queued_for_deletion()
		):
			continue
		var target_ground_gu: Vector2 = candidate.get(
			"ground_position_gu", Vector2.INF
		)
		var offset_ground_gu := target_ground_gu - origin_ground_gu
		var distance_squared_gu := offset_ground_gu.length_squared()
		if (
			distance_squared_gu
			<= GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU
			or not GroundUnitSpace.is_within_range_gu(
				origin_ground_gu,
				target_ground_gu,
				maximum_range_gu
			)
		):
			continue
		var alignment := facing_ground.dot(offset_ground_gu.normalized())
		var band := _direction_band(alignment)
		var instance_id := target.get_instance_id()
		if (
			band < best_band
			or (
				band == best_band
				and (
					distance_squared_gu
					< best_distance_squared_gu
					- GroundUnitSpace.EPSILON_GU
					or (
						is_equal_approx(
							distance_squared_gu,
							best_distance_squared_gu
						)
						and (
							alignment > best_alignment
							or (
								is_equal_approx(alignment, best_alignment)
								and instance_id < best_instance_id
							)
						)
					)
				)
			)
		):
			best_band = band
			best_distance_squared_gu = distance_squared_gu
			best_alignment = alignment
			best_instance_id = instance_id
			best = target
	return best


static func front_targets_ground_gu(
	candidates: Array[Dictionary],
	origin_ground_gu: Vector2,
	facing_direction_ground: Vector2,
	maximum_range_gu := DEFAULT_SEARCH_RANGE_GU
) -> Array[Node]:
	var ranked: Array[Dictionary] = []
	var facing_ground := (
		facing_direction_ground.normalized()
		if facing_direction_ground.length_squared()
		> GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU
		else Vector2.DOWN
	)
	for candidate: Dictionary in candidates:
		var target := candidate.get("target") as Node
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			continue
		var target_ground_gu: Vector2 = candidate.get(
			"ground_position_gu", Vector2.INF
		)
		var offset_ground_gu := target_ground_gu - origin_ground_gu
		var distance_squared_gu := offset_ground_gu.length_squared()
		if (
			distance_squared_gu
			<= GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU
			or not GroundUnitSpace.is_within_range_gu(
				origin_ground_gu,
				target_ground_gu,
				maximum_range_gu
			)
			or facing_ground.dot(offset_ground_gu.normalized()) <= 0.0
		):
			continue
		ranked.append({
			"target": target,
			"distance_squared_gu": distance_squared_gu,
			"instance_id": target.get_instance_id(),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance_squared_gu := float(a.distance_squared_gu)
		var b_distance_squared_gu := float(b.distance_squared_gu)
		if not is_equal_approx(a_distance_squared_gu, b_distance_squared_gu):
			return a_distance_squared_gu < b_distance_squared_gu
		return int(a.instance_id) < int(b.instance_id)
	)
	var result: Array[Node] = []
	for entry: Dictionary in ranked:
		result.append(entry.target as Node)
	return result


static func _direction_band(alignment: float) -> int:
	if alignment >= 0.5:
		return 0
	if alignment > -0.5:
		return 1
	return 2
