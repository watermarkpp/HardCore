extends RefCounted

const DEFAULT_SEARCH_RADIUS := 520.0
const RELEASE_RADIUS := 680.0

static func is_valid_target(target: Node2D, origin: Vector2, maximum_distance := RELEASE_RADIUS) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.global_position.distance_to(origin) <= maximum_distance

static func select_target(enemies: Array, origin: Vector2, preferred_direction: Vector2, current_target: Node2D = null, excluded_target: Node2D = null, maximum_distance := DEFAULT_SEARCH_RADIUS) -> Node2D:
	var best: Node2D
	var best_band := 99
	var best_distance := INF
	var best_alignment := -2.0
	var facing := preferred_direction.normalized() if preferred_direction.length_squared() > 0.01 else Vector2.DOWN
	for candidate: Variant in enemies:
		if not candidate is Node2D or candidate == excluded_target or candidate.is_queued_for_deletion():
			continue
		var node := candidate as Node2D
		var offset := node.global_position - origin
		var distance := offset.length()
		if distance <= 0.01 or distance > maximum_distance:
			continue
		var alignment := facing.dot(offset / distance)
		var band := _direction_band(alignment)
		if band < best_band or (band == best_band and (distance < best_distance - 0.01 or (is_equal_approx(distance, best_distance) and alignment > best_alignment))):
			best_band = band
			best_distance = distance
			best_alignment = alignment
			best = node
	return best

static func front_targets(enemies: Array, origin: Vector2, facing_direction: Vector2, maximum_distance := DEFAULT_SEARCH_RADIUS) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var facing := facing_direction.normalized() if facing_direction.length_squared() > 0.01 else Vector2.DOWN
	for candidate: Variant in enemies:
		if not candidate is Node2D or candidate.is_queued_for_deletion():
			continue
		var node := candidate as Node2D
		var offset := node.global_position - origin
		var distance := offset.length()
		if distance <= maximum_distance and distance > 0.01 and facing.dot(offset / distance) > 0.0:
			result.append(node)
	result.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position)
	)
	return result

static func _direction_band(alignment: float) -> int:
	if alignment >= 0.5:
		return 0
	if alignment > -0.5:
		return 1
	return 2
