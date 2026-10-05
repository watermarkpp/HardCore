extends "res://tests/framework/fixtures/lease_probe_root.gd"

# Observe the original descriptor result; never replace admission or factory work.
var _birth_failures_observed := 0
var _ready_failures_observed := 0

func _spawn_staged_actor_descriptor(descriptor: Dictionary) -> Dictionary:
	var result := super._spawn_staged_actor_descriptor(descriptor)
	if not bool(result.get("ok", false)) and _birth_failures_observed < 3:
		_birth_failures_observed += 1
		print("PUBLISHED_DESCRIPTOR_FAILURE ", result, " descriptor=", descriptor)
	return result

func _check_world_ready_contract() -> bool:
	var result := super._check_world_ready_contract()
	if not result and _ready_failures_observed < 2:
		_ready_failures_observed += 1
		print("PUBLISHED_READY_FAILURE bound=", feature_world_capacity_bound(),
			" coordinator=", _world_bootstrap_coordinator.ready_contract_summary())
	return result
