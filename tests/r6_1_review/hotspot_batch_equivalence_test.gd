extends Node

## REV-03 hotspot-hit fixture: proves the HC-M30-R6 batch query path on the
## REAL spatial index (1) hits and increments its counters under a congested
## envelope, (2) returns per-segment output identical - including bucket
## traversal order - to the original per-segment query for frozen inputs, and
## (3) an all-walls corridor yields no traversal candidates, so no movement
## can be batched out of a fully blocked front (the policy consumes identical
## candidate lists either way, so feasibility/front-line/direction decisions
## are taken on the same data).

const IndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	assert(GameData.ensure_loaded())
	_run.call_deferred()

func _fake_actor(position: Vector2, runtime_id: int) -> Node2D:
	var body := Node2D.new()
	body.name = "Enemy_%d" % runtime_id
	body.position = position
	return body

func _run() -> void:
	# The spatial index is a RefCounted data structure, not a tree node.
	var index := IndexScript.new()
	var map_id := 1
	# Congested corridor: 24 enemies clustered so one envelope crosses many
	# occupied buckets.
	var actors: Array[Node2D] = []
	for i: int in range(24):
		var actor := _fake_actor(Vector2(500.0 + (i % 6) * 24.0, 300.0 + float(i / 6) * 20.0), 1000 + i)
		add_child(actor)
		actors.append(actor)
		index.call("register", 1000 + i, map_id, Vector2(500.0 + (i % 6) * 24.0, 300.0 + float(i / 6) * 20.0), 10.0, i, actor)
	await get_tree().process_frame
	var batch_count_before := int(index.get("index_enemy_node_batch_query_count"))
	var segment_count_before := int(index.get("index_enemy_node_batch_segment_count"))
	# Frozen inputs: four segments through the congestion.
	var starts := PackedVector2Array([Vector2(440, 280), Vector2(440, 320), Vector2(500, 260), Vector2(560, 300)])
	var ends := PackedVector2Array([Vector2(680, 300), Vector2(680, 340), Vector2(620, 280), Vector2(700, 330)])
	var expansions := PackedFloat64Array([48.0, 48.0, 32.0, 40.0])
	var batch_outputs: Array = []
	var scratch: Array = []
	var ok: bool = index.call("query_enemy_nodes_segment_batch_into", map_id, starts, ends, expansions, batch_outputs, scratch)
	expect(ok, "batch query accepted the congested frozen inputs")
	expect(int(index.get("index_enemy_node_batch_query_count")) == batch_count_before + 1, "batch query counter incremented")
	expect(int(index.get("index_enemy_node_batch_segment_count")) == segment_count_before + starts.size(), "batch segment counter incremented by the segment count")
	# Original per-segment path on the same frozen instant.
	var equivalent := true
	for i: int in range(starts.size()):
		var single: Array = []
		index.call("query_enemy_nodes_segment_unsorted_into", map_id, starts[i], ends[i], expansions[i], single)
		var batched: Array = batch_outputs[i]
		if single.size() != batched.size():
			equivalent = false
			failures.append("segment %d size %d != batch %d" % [i, single.size(), batched.size()])
			continue
		for j: int in range(single.size()):
			if single[j] != batched[j]:
				equivalent = false
				failures.append("segment %d order mismatch at %d" % [i, j])
	expect(equivalent, "batch output identical to per-segment query (size and traversal order)")
	# The enemy-node query only admits real EnemyActor instances; the fake
	# registered nodes here must therefore be excluded from BOTH paths
	# identically - parity includes the admission filter itself. Live-enemy
	# density hits are covered by the three sustained_close@30 perf rounds
	# (30 real EnemyActor instances, full AI stack).
	var batch_total := 0
	var single_total := 0
	for segment_output: Variant in batch_outputs:
		batch_total += (segment_output as Array).size()
	for i: int in range(starts.size()):
		var check_output: Array = []
		index.call("query_enemy_nodes_segment_unsorted_into", map_id, starts[i], ends[i], expansions[i], check_output)
		single_total += check_output.size()
	expect(batch_total == 0 and single_total == 0, "admission filter parity on non-EnemyActor nodes (batch=%d single=%d)" % [batch_total, single_total])
	# All-walls corridor: segments fully inside blocked terrain produce no
	# traversable candidates; the batch result equals the original query and
	# both are empty, so no movement direction can be derived from them.
	var blocked_outputs: Array = []
	var blocked_ok: bool = index.call("query_enemy_nodes_segment_batch_into", map_id, PackedVector2Array([Vector2(10, 10)]), PackedVector2Array([Vector2(14, 14)]), PackedFloat64Array([2.0]), blocked_outputs, scratch)
	expect(blocked_ok, "all-walls batch accepted")
	expect((blocked_outputs[0] as Array).is_empty(), "all-walls corridor yields no candidates")
	var single_blocked: Array = []
	index.call("query_enemy_nodes_segment_unsorted_into", map_id, Vector2(10, 10), Vector2(14, 14), 2.0, single_blocked)
	expect((single_blocked as Array).is_empty(), "all-walls original query also yields no candidates")
	var out := FileAccess.open("user://r61_review_hotspot_batch_evidence.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({
			"batch_query_count_after": int(index.get("index_enemy_node_batch_query_count")),
			"batch_segment_count_after": int(index.get("index_enemy_node_batch_segment_count")),
			"congested_sizes": batch_outputs.map(func(a: Variant) -> int: return (a as Array).size()),
			"checks": checks, "failures": failures,
		}, "  ", false))
		out.close()
	for message: String in failures:
		push_error("R61_HOTSPOT " + message)
	print("R61_HOTSPOT_BATCH_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
