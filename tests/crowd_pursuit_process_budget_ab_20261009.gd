extends "res://tests/crowd_attack_start_frame_ab_20261009.gd"

## PURSUIT_PROCESS_BUDGET_AB. The inherited workload and attack AB stay on
## immediate mode; this fixture changes only the optional process-budget gate
## for ordinary foreground observation/new-step planning.

var _pursuit_mode := ""
var _pursuit_trace := false
var _new_step_interval_ms := -1
var _owner_decision_interval_ms := -1
var _instant_contact_settle := false
var _visual_move_override := false
var _residual_phase_probe := false
var _owner_optional_budget := false

func _run() -> void:
	_pursuit_mode = OS.get_environment("HARDCORE_PURSUIT_PROCESS_BUDGET_MODE").strip_edges().to_lower()
	if _pursuit_mode not in ["immediate", "dispatched"]:
		print("PURSUIT_PROCESS_BUDGET_MODE_MISSING_OR_INVALID")
		get_tree().quit(1)
		return
	var interval_text := OS.get_environment("HARDCORE_NEW_STEP_DECISION_INTERVAL_MS").strip_edges()
	if interval_text not in ["0", "200"]:
		print("HARDCORE_NEW_STEP_DECISION_INTERVAL_MS_MISSING_OR_INVALID")
		get_tree().quit(1)
		return
	_new_step_interval_ms = int(interval_text)
	var owner_interval_text := OS.get_environment("HARDCORE_OWNER_DECISION_INTERVAL_MS").strip_edges()
	if owner_interval_text not in ["0", "100", "200", "300"]:
		print("HARDCORE_OWNER_DECISION_INTERVAL_MS_MISSING_OR_INVALID")
		get_tree().quit(1)
		return
	_owner_decision_interval_ms = int(owner_interval_text)
	var instant_settle_text := OS.get_environment("HARDCORE_ORDINARY_CONTACT_INSTANT_SETTLE").strip_edges().to_lower()
	var visual_override_text := OS.get_environment("HARDCORE_ORDINARY_ATTACK_VISUAL_MOVE_OVERRIDE").strip_edges().to_lower()
	if instant_settle_text not in ["0", "1"] or visual_override_text not in ["0", "1"]:
		print("ATTACK_VISUAL_POLICY_FLAGS_MISSING_OR_INVALID")
		get_tree().quit(1)
		return
	_instant_contact_settle = instant_settle_text == "1"
	_visual_move_override = visual_override_text == "1"
	_residual_phase_probe = OS.get_environment("HARDCORE_ENEMY_RESIDUAL_PHASE_PROBE").strip_edges().to_lower() in ["1", "true", "yes"]
	if OS.get_environment("HARDCORE_ATTACK_AB_MODE").strip_edges().to_lower() != "immediate":
		print("PURSUIT_PROCESS_BUDGET_REQUIRES_ATTACK_IMMEDIATE")
		get_tree().quit(1)
		return
	if not EnemyActor.configure_pursuit_process_budget_mode(_pursuit_mode):
		print("PURSUIT_PROCESS_BUDGET_MODE_CONFIGURE_FAILED")
		get_tree().quit(1)
		return
	if not EnemyActor.configure_new_step_decision_interval_for_test(_new_step_interval_ms):
		print("NEW_STEP_DECISION_INTERVAL_CONFIGURE_FAILED")
		get_tree().quit(1)
		return
	if not EnemyActor.configure_owner_decision_interval_for_test(_owner_decision_interval_ms):
		print("OWNER_DECISION_INTERVAL_CONFIGURE_FAILED")
		get_tree().quit(1)
		return
	EnemyActor.configure_attack_visual_policy_for_test(_instant_contact_settle, _visual_move_override)
	var optional_text := OS.get_environment("HARDCORE_OWNER_OPTIONAL_BUDGET").strip_edges()
	if optional_text not in ["", "0", "1"]:
		print("OWNER_OPTIONAL_BUDGET_FLAG_INVALID")
		get_tree().quit(1)
		return
	_owner_optional_budget = optional_text == "1"
	EnemyActor.configure_owner_optional_budget_for_test(_owner_optional_budget)
	_pursuit_trace = OS.get_environment("HARDCORE_PURSUIT_PROCESS_BUDGET_TRACE").strip_edges().to_lower() in ["1", "true", "yes"]
	EnemyActor.configure_pursuit_process_trace(_pursuit_trace)
	EnemyActor.configure_residual_phase_probe(_residual_phase_probe)
	EnemyActor.reset_pursuit_process_budget_diagnostics()
	await super._run()

func _start_ab_window() -> void:
	super._start_ab_window()
	# The sample boundary resets counters only. Business FIFO/credits are
	# intentionally retained across the warmup/window boundary; the explicit
	# state-reset API is reserved for a direct contract test with no open lease.
	EnemyActor.reset_pursuit_process_budget_diagnostics()
	EnemyActor.reset_residual_phase_probe()

func _append_scaling_result(result: Dictionary) -> void:
	var classifications: Array[Dictionary] = []
	for actor: EnemyActor in _scaling_enemies:
		if not is_instance_valid(actor):
			continue
		classifications.append({
			"instance_id": actor.get_instance_id(),
			"monster_id": actor.monster_id,
			"ordinary": actor._source176_ordinary_melee(),
			"boss": actor.is_boss,
			"area_enabled": bool(actor.area_attack_rule.get("enabled", false)),
			"summon_enabled": bool(actor.summon_rule.get("enabled", false)),
			"delivery_kind": str(actor.attack_delivery_rule.get("kind", "")),
		})
	var diagnostic: Dictionary = EnemyActor.pursuit_process_budget_diagnostics()
	var residual_probe: Dictionary = EnemyActor.residual_phase_probe_snapshot()
	var budget_snapshot: Dictionary = diagnostic.get("decision_budget", {})
	var dispatch_samples: Array = budget_snapshot.get("dispatch_samples", [])
	var dispatch_cpu: Dictionary = {
		"enemy_planning_dispatch_usec": int(budget_snapshot.get("dispatch_usec_total", 0)),
		"dispatch_calls": int(budget_snapshot.get("dispatch_calls", 0)),
		"dispatch_samples": dispatch_samples,
		"dispatch_samples_truncated": bool(budget_snapshot.get("dispatch_samples_truncated", false)),
		"dispatch_queue_end": int(budget_snapshot.get("dispatch_queue_length", 0)),
		"dispatch_frame_budget_scopes": int(budget_snapshot.get("dispatch_frame_budget_scopes", 0)),
		"dispatch_atomic_overrun_usec": int(budget_snapshot.get("dispatch_atomic_overrun_usec", 0)),
		"dispatch_maintenance_used": int(budget_snapshot.get("dispatch_maintenance_used", 0)),
		"dispatch_maintenance_skipped": int(budget_snapshot.get("dispatch_maintenance_skipped", 0)),
		"dispatch_post_invalid": int(budget_snapshot.get("dispatch_post_invalid", 0)),
		"dispatch_denied_fairness": int(budget_snapshot.get("dispatch_denied_fairness", 0)),
		"dispatch_denied_unrunnable": int(budget_snapshot.get("dispatch_denied_unrunnable", 0)),
		"dispatch_queue_rows": budget_snapshot.get("dispatch_queue_rows", []),
		"dispatch_queue_max_wait_usec": int(budget_snapshot.get("dispatch_queue_max_wait_usec", 0)),
	}
	var enemy_physics_usec := int(result.counters.get("enemy_physics_usec", 0))
	dispatch_cpu["enemy_physics_plus_dispatch_usec_same_window"] = enemy_physics_usec + int(dispatch_cpu.enemy_planning_dispatch_usec)
	dispatch_cpu["comparison_basis"] = "enemy_physics_usec_plus_full_dispatch_wrapper_usec"
	var timeline: Array = diagnostic.get("service_timeline", [])
	var runtime_receipt_present: bool = diagnostic.has("requests") and diagnostic.has("grants") and diagnostic.has("decision_budget")
	var missing: Array[String] = []
	if timeline.is_empty():
		missing.append("runtime_service_timeline")
	if not runtime_receipt_present:
		missing.append("runtime_budget_receipt")
	var status: String = "OBSERVED" if runtime_receipt_present else "MISSING_RUNTIME_RECEIPT"
	result["pursuit_process_budget_ab"] = {
		"mode": _pursuit_mode,
		"new_step_decision_interval_ms": _new_step_interval_ms,
		"owner_decision_interval_ms": _owner_decision_interval_ms,
		"owner_optional_budget_enabled": _owner_optional_budget,
		"ordinary_contact_instant_settle": _instant_contact_settle,
		"ordinary_attack_visual_move_override": _visual_move_override,
		"trace_enabled": _pursuit_trace,
		"diagnostic": diagnostic,
		"diagnostic_actual_dispatch_cpu": dispatch_cpu,
		"residual_phase_probe": residual_probe,
		"actor_classification": classifications,
		"contract": {
			"status": status,
			"same_code_both_policies": "MISSING_COMPARISON_PAIR",
			"attack_frequency_unchanged": "MISSING_RUNTIME_COMPARISON",
			"physics_tick_unchanged": "MISSING_RUNTIME_COMPARISON",
			"active_motion_outside_budget": "MISSING_RUNTIME_COMPARISON",
			"diagnostic_cpu_not_acceptance": "POLICY",
			"grants_observed": int(budget_snapshot.get("grants", 0)),
			"queue_peak_observed": int(budget_snapshot.get("queue_peak", 0)),
		},
		"missing": missing,
	}
	super._append_scaling_result(result)

