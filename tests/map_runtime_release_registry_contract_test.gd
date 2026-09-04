extends Node

const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var base_entry := {
		"runtime_map_id": 1,
		"map_key": "map_one",
		"runtime_path": "res://x.runtime.json",
		"release_state": "implemented_playable",
		"approved_build_sha256": "abc",
	}
	# Valid registry passes.
	var valid := {"schema_version": 1, "registry_contract_id": "mse.map.runtime.release.v1", "maps": [base_entry]}
	assert(Bridge.validate_release_registry(valid).is_empty(), "valid registry must pass")
	# Duplicate runtime_map_id.
	var dup_id := valid.duplicate(true)
	dup_id["maps"] = [base_entry, base_entry.duplicate(true)]
	assert(
		Bridge.validate_release_registry(dup_id).has("duplicate_runtime_map_id"),
		"duplicate runtime_map_id must fail"
	)
	# Duplicate map_key.
	var dup_key := valid.duplicate(true)
	var other := base_entry.duplicate(true)
	other["runtime_map_id"] = 2
	dup_key["maps"] = [base_entry, other]
	assert(
		Bridge.validate_release_registry(dup_key).has("duplicate_map_key"),
		"duplicate map_key must fail"
	)
	# Missing runtime_path.
	var no_path := base_entry.duplicate(true)
	no_path["runtime_path"] = ""
	assert(
		Bridge.validate_release_registry({
			"schema_version": 1, "registry_contract_id": "mse.map.runtime.release.v1",
			"maps": [no_path]}).has("missing_runtime_path"),
		"missing runtime_path must fail"
	)
	# Missing approved hash.
	var no_hash := base_entry.duplicate(true)
	no_hash["approved_build_sha256"] = ""
	assert(
		Bridge.validate_release_registry({
			"schema_version": 1, "registry_contract_id": "mse.map.runtime.release.v1",
			"maps": [no_hash]}).has("missing_approved_hash"),
		"missing approved hash must fail"
	)
	# Unknown release state.
	var bad_state := base_entry.duplicate(true)
	bad_state["release_state"] = "mystery"
	assert(
		Bridge.validate_release_registry({
			"schema_version": 1, "registry_contract_id": "mse.map.runtime.release.v1",
			"maps": [bad_state]}).has("unknown_release_state"),
		"unknown release state must fail"
	)
	# Invalid runtime_map_id.
	var bad_id := base_entry.duplicate(true)
	bad_id["runtime_map_id"] = 0
	assert(
		Bridge.validate_release_registry({
			"schema_version": 1, "registry_contract_id": "mse.map.runtime.release.v1",
			"maps": [bad_id]}).has("invalid_runtime_map_id"),
		"invalid runtime_map_id must fail"
	)
	await get_tree().process_frame
	print("MAP_RUNTIME_RELEASE_REGISTRY_CONTRACT_PASS")
	get_tree().quit(0)
