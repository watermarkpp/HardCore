extends Node

const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")

const MAP_A := 7001
const MAP_B := 7002


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_query_source_shape()
	var index := SpatialIndex.new()
	var first := _make_enemy(index, 1, MAP_A, Vector2.ZERO, 0.5, 20)
	var second := _make_enemy(index, 2, MAP_A, Vector2(4.1, 0.0), 0.25, 10)
	var tie_a := _make_enemy(index, 3, MAP_A, Vector2(0.0, 1.5), 0.25, 30)
	var tie_b := _make_enemy(index, 4, MAP_A, Vector2(0.5, 1.5), 0.25, 30)
	var other_map := _make_enemy(
		index,
		5,
		MAP_B,
		Vector2.ZERO,
		0.25,
		1,
	)
	var generic := Node.new()
	index.register(
		99,
		MAP_A,
		Vector2.ZERO,
		0.25,
		5,
		generic,
	)

	var output: Array = [generic]
	var aabb_query_count := index.index_enemy_node_aabb_query_count
	index.query_enemy_nodes_aabb_into(
		MAP_A,
		Rect2(Vector2(-0.5, -1.0), Vector2(5.5, 3.0)),
		output,
	)
	assert(index.index_enemy_node_aabb_query_count == aabb_query_count + 1)
	assert(output.size() == 4, "AABB must return only live EnemyActor nodes")
	assert(not output.has(generic), "generic index entries must not leak")
	assert(not output.has(other_map), "map-scoped query leaked another map")
	assert(output[0] == second, "stable combat order must be ascending")
	assert(output[1] == first)
	assert(
		int((output[2] as EnemyActor).get_instance_id())
		< int((output[3] as EnemyActor).get_instance_id()),
		"equal stable orders must use instance id"
	)
	assert(output[2] == tie_a or output[2] == tie_b)
	assert(output[3] == tie_a or output[3] == tie_b)

	var segment_output: Array = [first]
	var segment_query_count := index.index_enemy_node_segment_query_count
	index.query_enemy_nodes_segment_into(
		MAP_A,
		Vector2(-1.0, 0.0),
		Vector2(5.0, 0.0),
		0.0,
		segment_output,
	)
	assert(
		index.index_enemy_node_segment_query_count == segment_query_count + 1
	)
	assert(segment_output.has(first))
	assert(segment_output.has(second))
	assert(not segment_output.has(other_map))

	# The update is the same transaction as the caller's position change; the
	# following query must see the new bucket and not the old one.
	index.update_actor(2, Vector2(9.0, 0.0))
	var old_bucket_output: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_A,
		Rect2(Vector2(4.0, -0.25), Vector2(0.2, 0.5)),
		old_bucket_output,
	)
	assert(not old_bucket_output.has(second))
	var new_bucket_output: Array = []
	index.query_enemy_nodes_segment_into(
		MAP_A,
		Vector2(8.5, 0.0),
		Vector2(9.5, 0.0),
		0.0,
		new_bucket_output,
	)
	assert(new_bucket_output.has(second))

	# Death flags and queue_free are visible to the broadphase immediately; a
	# subsequent query must not return either stale node.
	first._death_pending = true
	var dead_output: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_A,
		Rect2(Vector2(-0.1, -0.1), Vector2(0.2, 0.2)),
		dead_output,
	)
	assert(not dead_output.has(first))
	assert(index.registered_actor_count() == 5)

	var queued := _make_enemy(
		index,
		6,
		MAP_A,
		Vector2(12.0, 0.0),
		0.25,
		40,
	)
	queued.queue_free()
	assert(queued.is_queued_for_deletion())
	var queued_output: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_A,
		Rect2(Vector2(11.9, -0.1), Vector2(0.2, 0.2)),
		queued_output,
	)
	assert(not queued_output.has(queued))

	index.unregister(2)
	var unregistered_output: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_A,
		Rect2(Vector2(8.9, -0.1), Vector2(0.2, 0.2)),
		unregistered_output,
	)
	assert(unregistered_output.is_empty())

	index.clear_map(MAP_B)
	var cleared_map_output: Array = []
	index.query_enemy_nodes_aabb_into(
		MAP_B,
		Rect2(Vector2(-1.0, -1.0), Vector2(2.0, 2.0)),
		cleared_map_output,
	)
	assert(cleared_map_output.is_empty())

	var diagnostics := index.diagnostics()
	assert(diagnostics.has("index_enemy_node_aabb_query_count"))
	assert(diagnostics.has("index_enemy_node_segment_query_count"))
	assert(diagnostics.has("index_enemy_node_candidate_count"))
	_cleanup(index, [first, second, tie_a, tie_b, other_map, queued], generic)
	print(
		"RUNTIME_COMBAT_SPATIAL_INDEX_ENEMY_QUERY_PASS "
		+ "aabb=%d segment=%d candidates=%d"
		% [
			int(diagnostics.get("index_enemy_node_aabb_query_count", 0)),
			int(diagnostics.get("index_enemy_node_segment_query_count", 0)),
			int(diagnostics.get("index_enemy_node_candidate_count", 0)),
		]
	)
	get_tree().quit(0)


func _make_enemy(
	index: SpatialIndex,
	actor_id: int,
	map_id: int,
	position_ground_gu: Vector2,
	bounds_gu: float,
	stable_order: int,
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.current_hp = 100
	enemy.max_hp = 100
	enemy._dying = false
	enemy._death_pending = false
	index.register(
		actor_id,
		map_id,
		position_ground_gu,
		bounds_gu,
		stable_order,
		enemy,
	)
	return enemy


func _verify_query_source_shape() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/runtime_combat_spatial_index.gd"
	)
	var aabb_start := source.find("func query_enemy_nodes_aabb_into")
	var segment_start := source.find("func query_enemy_nodes_segment_into")
	var helper_start := source.find("func _query_enemy_nodes_in_aabb")
	assert(aabb_start >= 0 and segment_start > aabb_start)
	assert(helper_start > segment_start)
	for function_source: String in [
		source.substr(aabb_start, segment_start - aabb_start),
		source.substr(segment_start, helper_start - segment_start),
		source.substr(helper_start, source.find("func _finish_enemy_node_query", helper_start) - helper_start),
	]:
		assert(function_source.find("get_nodes_in_group") < 0)
		assert(function_source.find("seen: Dictionary") < 0)
		assert(function_source.find("append({") < 0)


func _cleanup(
	index: SpatialIndex,
	enemies: Array,
	generic: Node,
) -> void:
	for actor_id: int in range(1, 7):
		index.unregister(actor_id)
	index.unregister(99)
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	if is_instance_valid(generic):
		generic.queue_free()
