extends "res://tests/helpers/crowd_quantum_boundary_trace_20261009.gd"

## This scene is diagnostic evidence only. Run once with HARDCORE_QUANTUM_ABI_MODE=LOCAL
## and once with ABI_SHAM; do not compare runs as an optimization score unless
## the inherited trajectory/event records are first shown comparable.

func _append_scaling_result(result: Dictionary) -> void:
	result["contract"] = {
		"name": "crowd_quantum_abi_sham_20261009",
		"required_modes": ["LOCAL", "ABI_SHAM"],
		"required_callbacks": SCALING_ACTOR_COUNT * SCALING_SAMPLE_TICKS,
		"stock_effects_execute_once": true,
		"same_entry_velocity_writeback": true,
		"comparison_status": "UNKNOWN",
	}
	super._append_scaling_result(result)
