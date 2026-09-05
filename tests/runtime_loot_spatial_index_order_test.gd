extends Node

const LootIndexScript := preload("res://scripts/runtime_loot_spatial_index.gd")
const LootPickupScript := preload("res://scripts/loot_pickup.gd")

const TEST_MAP_ID := 71
const OTHER_MAP_ID := 72

var _pickups: Array[LootPickup] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_assert_reverse_order_and_runtime_key()
	_assert_multi_bucket_ties_and_map_isolation()
	_assert_boundary_and_weak_reference_behavior()
	print("RUNTIME_LOOT_SPATIAL_INDEX_ORDER_PASS: reverse, buckets, ties, map, boundary, weakref")
	get_tree().quit(0)


func _assert_reverse_order_and_runtime_key() -> void:
	var index := LootIndexScript.new()
	var expected: Array[LootPickup] = []
	const COUNT := 48
	for item_index in range(COUNT):
		var pickup := _new_pickup(Vector2(0.25, 0.25))
		expected.append(pickup)
		# Deliberately keep runtime IDs separate from node instance IDs. The
		# `_entries` key is a runtime identity; ordering uses the node identity.
		assert(index.register(
			90000 + item_index,
			TEST_MAP_ID,
			Vector2(0.25, 0.25),
			COUNT - item_index,
			pickup,
		))
	var output: Array = ["stale caller value"]
	index.query_nearby_into(TEST_MAP_ID, Vector2.ZERO, 0.75, output)
	assert(output.size() == COUNT, "reverse-order query lost candidates")
	for item_index in range(COUNT):
		assert(output[item_index] == expected[COUNT - item_index - 1], "stable registration order changed")
	assert(index.registered_pickup_count() == COUNT, "runtime key/node identity split dropped entries")
	output.clear()
	index.query_nearby_into(OTHER_MAP_ID, Vector2.ZERO, 0.75, output)
	assert(output.is_empty(), "query crossed runtime map partition")


func _assert_multi_bucket_ties_and_map_isolation() -> void:
	var index := LootIndexScript.new()
	var positions := [
		Vector2(-5.5, 0.0),
		Vector2(0.25, 0.25),
		Vector2(5.5, 0.0),
		Vector2(0.0, 5.5),
		Vector2(0.0, -5.5),
	]
	var expected: Array[LootPickup] = []
	for item_index in range(positions.size()):
		var pickup := _new_pickup(positions[item_index])
		expected.append(pickup)
		assert(index.register(
			91000 + item_index,
			TEST_MAP_ID,
			positions[item_index],
			12,
			pickup,
		))
	var other_map_pickup := _new_pickup(Vector2.ZERO)
	assert(index.register(92000, OTHER_MAP_ID, Vector2.ZERO, 1, other_map_pickup))
	var output: Array = []
	index.query_nearby_into(TEST_MAP_ID, Vector2.ZERO, 6.0, output)
	assert(output.size() == expected.size(), "multi-bucket query changed candidate quantity")
	expected.sort_custom(
		func(a: LootPickup, b: LootPickup) -> bool:
			return a.get_instance_id() < b.get_instance_id()
	)
	for item_index in range(expected.size()):
		assert(output[item_index] == expected[item_index], "same-order instance ID tie changed")
	assert(not output.has(other_map_pickup), "multi-bucket query leaked another map")


func _assert_boundary_and_weak_reference_behavior() -> void:
	var index := LootIndexScript.new()
	var center := Vector2(20.0, 20.0)
	var radius := 0.75
	var inside := _new_pickup(center + Vector2(radius - 0.001, 0.0))
	var boundary := _new_pickup(center + Vector2(radius, 0.0))
	assert(index.register(93001, TEST_MAP_ID, center + Vector2(radius - 0.001, 0.0), 1, inside))
	assert(index.register(93002, TEST_MAP_ID, center + Vector2(radius, 0.0), 2, boundary))
	var output: Array = []
	index.query_nearby_into(TEST_MAP_ID, center, radius, output)
	# This API is a conservative bucket broadphase. The caller's existing
	# strict `< radius^2` narrow phase owns the exact boundary decision.
	assert(output.has(inside) and output.has(boundary), "exact boundary candidate was lost")
	assert((center.distance_squared_to(inside.global_position) < radius * radius), "inside fixture is not strictly in range")
	assert(not (center.distance_squared_to(boundary.global_position) < radius * radius), "boundary fixture must remain excluded by strict narrow phase")

	var ghost := _new_pickup(center)
	assert(index.register(93003, TEST_MAP_ID, center, 3, ghost))
	ghost.free()
	output.clear()
	index.query_nearby_into(TEST_MAP_ID, center, radius, output)
	assert(not output.has(ghost), "freed weak reference leaked into query output")
	assert(index.index_stale_cleanup_count == 1, "freed weak reference was not lazily cleaned")
	assert(index.registered_pickup_count() == 2, "stale cleanup removed a live entry")


func _new_pickup(position_gu: Vector2) -> LootPickup:
	var pickup: LootPickup = LootPickupScript.new()
	pickup.global_position = position_gu
	add_child(pickup)
	_pickups.append(pickup)
	return pickup
