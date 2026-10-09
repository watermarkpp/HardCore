extends "res://tests/crowd_attack_start_frame_ab_20261009.gd"

## Passive contact-check accounting only. The inherited AB fixture remains the
## workload owner; this fixture changes no attack, movement, clock, or budget
## decision and only enables the Enemy diagnostic window for the sample.

func _run() -> void:
	if OS.get_environment("HARDCORE_ATTACK_AB_MODE").strip_edges().to_lower() != "immediate":
		print("ATTACK_CONTACT_DIAGNOSTIC_REQUIRES_IMMEDIATE_AB")
		get_tree().quit(1)
		return
	await super._run()

func _start_ab_window() -> void:
	super._start_ab_window()
	EnemyActor.reset_contact_check_diagnostic()
	EnemyActor.set_contact_check_diagnostic_enabled(true)

func _append_scaling_result(result: Dictionary) -> void:
	var diagnostic := EnemyActor.contact_check_diagnostic_snapshot()
	diagnostic["window_contract"] = {
		"sample_window_only": true,
		"inclusive_nested_usec_not_additive": true,
		"return_values_unchanged": true,
		"diagnostic_cpu_not_acceptance": true,
	}
	result["contact_check_diagnostic"] = diagnostic
	EnemyActor.set_contact_check_diagnostic_enabled(false)
	super._append_scaling_result(result)
