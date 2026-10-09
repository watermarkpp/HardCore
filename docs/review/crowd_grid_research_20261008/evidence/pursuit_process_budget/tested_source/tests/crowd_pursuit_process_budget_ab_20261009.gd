extends "res://tests/crowd_attack_start_frame_ab_20261009.gd"

## PURSUIT_PROCESS_BUDGET_AB. The inherited workload and attack AB stay on
## immediate mode; this fixture changes only the optional process-budget gate
## for ordinary foreground observation/new-step planning.

var _pursuit_mode := ""

func _run() -> void:
	_pursuit_mode = OS.get_environment("HARDCORE_PURSUIT_PROCESS_BUDGET_MODE").strip_edges().to_lower()
	if _pursuit_mode not in ["immediate", "budgeted"]:
		print("PURSUIT_PROCESS_BUDGET_MODE_MISSING_OR_INVALID")
		get_tree().quit(1)
		return
	if OS.get_environment("HARDCORE_ATTACK_AB_MODE").strip_edges().to_lower() != "immediate":
		print("PURSUIT_PROCESS_BUDGET_REQUIRES_ATTACK_IMMEDIATE")
		get_tree().quit(1)
		return
	if not EnemyActor.configure_pursuit_process_budget_mode(_pursuit_mode):
		print("PURSUIT_PROCESS_BUDGET_MODE_CONFIGURE_FAILED")
		get_tree().quit(1)
		return
	EnemyActor.reset_pursuit_process_budget_diagnostics()
	await super._run()

func _start_ab_window() -> void:
	super._start_ab_window()
	# The sample boundary resets counters only. Business FIFO/credits are
	# intentionally retained across the warmup/window boundary; the explicit
	# state-reset API is reserved for a direct contract test with no open lease.
	EnemyActor.reset_pursuit_process_budget_diagnostics()

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
	var budget_snapshot: Dictionary = diagnostic.get("decision_budget", {})
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
		"diagnostic": diagnostic,
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

