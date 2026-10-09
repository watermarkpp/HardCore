extends "res://tests/crowd_formal_grid_comparison_20261008.gd"

const AuditSinkScript := preload("res://tests/support/no_plan_failure_audit_20261009.gd")
const AUDIT_MANIFEST := "res://outputs/crowd_no_plan_failure_audit_20261009/current_run_inputs.json"

var _audit_sinks: Dictionary = {}
var _audit_failures: Array[String] = []
var _audit_sample_started := false
var _audit_binding: Dictionary = {}

func _physics_process(delta: float) -> void:
	if _scaling_sampling and not _audit_sample_started:
		_audit_sample_started = true
		for sink in _audit_sinks.values():
			sink.clear()
	super._physics_process(delta)

func _run() -> void:
	var input_file := FileAccess.open(AUDIT_MANIFEST, FileAccess.READ)
	if input_file == null:
		_audit_failures.append("audit_manifest_missing")
		push_error("NO_PLAN_FAILURE_AUDIT manifest missing")
		get_tree().quit(1)
		return
	var parsed: Variant = JSON.parse_string(input_file.get_as_text())
	if not parsed is Dictionary:
		_audit_failures.append("audit_manifest_invalid")
		push_error("NO_PLAN_FAILURE_AUDIT manifest invalid")
		get_tree().quit(1)
		return
	_audit_binding = parsed
	_audit_binding["manifest_sha256"] = FileAccess.get_sha256(AUDIT_MANIFEST)
	_audit_binding["engine_actual_sha256"] = FileAccess.get_sha256(OS.get_executable_path())
	for input_path: String in _audit_binding.get("source_sha256", {}):
		if FileAccess.get_sha256("res://" + input_path) != str(_audit_binding.source_sha256[input_path]):
			_audit_failures.append("source_binding_mismatch:%s" % input_path)
	if str(_audit_binding.get("engine_sha256", "")) != str(_audit_binding.engine_actual_sha256):
		_audit_failures.append("engine_binding_mismatch")
	if not _audit_failures.is_empty():
		push_error("NO_PLAN_FAILURE_AUDIT binding mismatch: " + ",".join(_audit_failures))
		get_tree().quit(1)
		return
	await super._run()

func _place_scaling_actors(enemies: Array) -> Dictionary:
	var layout := super._place_scaling_actors(enemies)
	for enemy: EnemyActor in enemies:
		if not is_instance_valid(enemy):
			continue
		var sink := AuditSinkScript.new(enemy.get_instance_id())
		_audit_sinks[str(enemy.get_instance_id())] = sink
		if enemy.has_method(&"configure_no_plan_failure_audit"):
			enemy.call(&"configure_no_plan_failure_audit", sink)
		else:
			_audit_failures.append("production_hook_missing:%d" % enemy.get_instance_id())
	return layout

func _audit_snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var totals := {"calls": 0, "wait": 0, "postretry": 0, "budget": 0,
		"chooser_success": 0, "complete_failure": 0, "target_only_invalidation": 0,
		"known_live_difference": 0, "elapsed_usec": 0}
	for sink in _audit_sinks.values():
		var row: Dictionary = sink.snapshot()
		rows.append(row)
		for key: String in totals:
			totals[key] += int(row.get("counts", {}).get(key, 0))
	return {"owners": rows, "totals": totals,
		"hook_count": _audit_sinks.size(),
		"certificate_creation": "NOT_MEASURED", "certificate_validation": "NOT_MEASURED",
		"diagnostic_cpu": "NOT_PERFORMANCE_EVIDENCE",
		"failures": _audit_failures,
		"interpretation": "UNPROVEN unless complete failure and repeated hard evidence are present in calls"}

func _append_scaling_result(result: Dictionary) -> void:
	var audit := _audit_snapshot()
	result["no_plan_failure_audit"] = audit
	result["no_plan_failure_audit"]["run_binding"] = _audit_binding
	var counts: Dictionary = result.get("actor_counts", {})
	var targeting: Dictionary = result.get("targeting", {})
	var loot: Dictionary = result.get("loot", {})
	var expected_checks := {
		"actors_34": int(counts.get("alive_after_sample", -1)) == 34,
		"engaged_30": int(targeting.get("max_actual", -1)) == 30,
		"loot_48": int(loot.get("ending_active_count", -1)) == 48,
		"physics_ticks_300": int(result.get("actual_physics_ticks", -1)) == 300,
		"player_motion_positive": float(result.get("player_motion", {}).get("total_gu", 0.0)) > GroundUnitSpace.EPSILON_GU,
		"hooks_34": int(audit.get("hook_count", 0)) == 34,
		"active_empty": _audit_active_empty(),
		"diagnostic_calls_match_neighbor_counter": int(audit.get("totals", {}).get("calls", -1)) == int(result.get("counters", {}).get("enemy_neighbor_calls", -2)),
		"physics_callbacks_10200": int(result.get("counters", {}).get("enemy_physics_calls", -1)) == 10200}
	audit["contract_checks"] = expected_checks
	for key: String in expected_checks:
		if not bool(expected_checks[key]):
			_audit_failures.append("contract_%s" % key)
	for failure: String in _audit_failures:
		if failure not in _scaling_failures:
			_scaling_failures.append(failure)
	result["failures"] = Array(result.get("failures", [])) + _audit_failures
	if not _audit_failures.is_empty():
		result["status"] = "FAIL"
	super._append_scaling_result(result)

func _audit_active_empty() -> bool:
	for sink in _audit_sinks.values():
		if not (sink.snapshot().get("active", {}) as Dictionary).is_empty():
			return false
	return true

