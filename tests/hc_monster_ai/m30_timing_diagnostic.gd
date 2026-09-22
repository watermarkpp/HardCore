extends "res://tests/hc_monster_ai/m30_sampling_copy.gd"

## Observation-only supplement to the original real-time benchmark. A named
## test-only hitch can expose its mixed wall-clock/physics-clock sensitivity;
## timings from this fixture are never used as performance acceptance data.
var _trace: Array[Dictionary] = []
var _await_count := 0
var _warmup_start_tick := 0
var _last_tick := 0


func _sample_case(scenario: String, count: int) -> Dictionary:
	_trace.clear()
	_await_count = 0
	_warmup_start_tick = Engine.get_physics_frames()
	_last_tick = _warmup_start_tick
	var row := await super._sample_case(scenario, count)
	row["timing_diagnostic"] = {
		"status": "PASS", "purpose": "clock sensitivity, not performance",
		"injected_warmup_hitch_ms": int(OS.get_environment("HARDCORE_TIMING_HITCH_MS")),
		"trace": _trace.duplicate(true),
	}
	return row


func _await_real_frame() -> void:
	_await_count += 1
	if _await_count == 20:
		var hitch_ms := int(OS.get_environment("HARDCORE_TIMING_HITCH_MS"))
		assert(hitch_ms >= 0 and hitch_ms <= 100)
		if hitch_ms > 0:
			OS.delay_msec(hitch_ms)
	await super._await_real_frame()
	var tick := Engine.get_physics_frames()
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or int(node.get_meta("spawn_serial", -1)) != 13:
			continue
		var enemy := node as EnemyActor
		var point := enemy.spatial_index_position()
		_trace.append({
			"await_iteration": _await_count, "capturing": _capture_actor_progress,
			"relative_physics_tick": tick - _warmup_start_tick,
			"physics_ticks_since_last_await": tick - _last_tick,
			"wall_ms": Time.get_ticks_msec(),
			"side_retry_ms": enemy._hc_next_side_retry_ms,
			"step_active": enemy._movement_step_active,
			"ground": [point.x, point.y],
			"distance": point.distance_to(_target_ground()),
			"reason": enemy._hc_last_reason,
			"attack_starts": int(enemy.get("probe_attack_starts")),
		})
	_last_tick = tick


func _source_hashes() -> Dictionary:
	var hashes := super._source_hashes()
	hashes["res://tests/hc_monster_ai/m30_timing_diagnostic.gd"] = FileAccess.get_sha256(
		"res://tests/hc_monster_ai/m30_timing_diagnostic.gd")
	return hashes
