extends Node
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")
const Enemy := preload("res://scripts/enemy.gd")
var failures: Array[String] = []
var checks := 0
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260911
	var index := Index.new()
	var actors: Array[EnemyActor] = []
	for i in range(64):
		var actor := Enemy.new()
		actor.spatial_actor_runtime_id = 1000 + i
		actor.runtime_map_id = 7 if i < 48 else 8
		actor.current_hp = 100
		actors.append(actor)
		index.register(actor.spatial_actor_runtime_id, actor.runtime_map_id, Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)), rng.randf_range(0.2, 1.5), i, actor)
	var outputs: Array = []
	var scratch: Array = []
	for trial in range(100):
		var starts := PackedVector2Array()
		var ends := PackedVector2Array()
		var expansions := PackedFloat64Array()
		for i in range(16):
			starts.append(Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
			ends.append(Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
			expansions.append(rng.randf_range(0.0, 2.0))
		if trial % 9 == 0:
			var moved := actors[trial % 40]
			index.update_actor(moved.spatial_actor_runtime_id, Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
		expect(index.query_enemy_nodes_segment_batch_into(7, starts, ends, expansions, outputs, scratch), "valid batch")
		for i in range(16):
			var single: Array = []
			index.query_enemy_nodes_segment_unsorted_into(7, starts[i], ends[i], expansions[i], single)
			expect(single == outputs[i], "exact candidates AND order trial=%d segment=%d" % [trial, i])
	# Death and clear-map must not leave cached nodes in later batches.
	for i in range(20):
		actors[i]._dying = true
	var starts := PackedVector2Array([Vector2(-30, -30)])
	var ends := PackedVector2Array([Vector2(30, 30)])
	var expansion := PackedFloat64Array([1.0])
	expect(index.query_enemy_nodes_segment_batch_into(7, starts, ends, expansion, outputs, scratch), "death filtering batch")
	for actor: EnemyActor in outputs[0]:
		expect(not actor._dying, "dead actor filtered")
	index.clear_map(7)
	expect(index.query_enemy_nodes_segment_batch_into(7, starts, ends, expansion, outputs, scratch) and outputs[0].is_empty(), "clear-map no stale candidates")
	expect(not index.query_enemy_nodes_segment_batch_into(-1, starts, ends, expansion, outputs, scratch), "invalid map rejected")
	for actor: EnemyActor in actors:
		actor.free()
	for message: String in failures:
		push_error("R6_SPATIAL " + message)
	print("R6_1_SPATIAL_BATCH_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
