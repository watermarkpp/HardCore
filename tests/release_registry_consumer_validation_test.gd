extends Node

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const REG_PATH := "user://p0_3r_consumer_registry.json"
const MISSING_PATH := "user://p0_3r_consumer_missing.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	var base_entry := Fixtures.make_entry(
		4, "bich_province", "0000000000000000000000000000000000000000000000000000000000000000",
		"res://assets/data/runtime/map_editor/bich_province.runtime.json",
		1
	)
	var variants: Array[Dictionary] = [
		{
			"name": "wrong_schema_version",
			"mutate": func(reg: Dictionary) -> void:
				reg["schema_version"] = 2,
		},
		{
			"name": "wrong_contract_id",
			"mutate": func(reg: Dictionary) -> void:
				reg["registry_contract_id"] = "not.the.contract",
		},
		{
			"name": "duplicate_runtime_map_id",
			"mutate": func(reg: Dictionary) -> void:
				reg.maps.append((reg.maps[0] as Dictionary).duplicate(true)),
		},
		{
			"name": "duplicate_map_key",
			"mutate": func(reg: Dictionary) -> void:
				var other: Dictionary = (reg.maps[0] as Dictionary).duplicate(true)
				other["runtime_map_id"] = 217
				reg.maps.append(other),
		},
		{
			"name": "missing_runtime_path",
			"mutate": func(reg: Dictionary) -> void:
				reg.maps[0]["runtime_path"] = "",
		},
		{
			"name": "missing_approved_hash",
			"mutate": func(reg: Dictionary) -> void:
				reg.maps[0]["approved_build_sha256"] = "",
		},
		{
			"name": "unknown_release_state",
			"mutate": func(reg: Dictionary) -> void:
				reg.maps[0]["release_state"] = "mystery",
		},
		{
			"name": "invalid_runtime_map_id",
			"mutate": func(reg: Dictionary) -> void:
				reg.maps[0]["runtime_map_id"] = 0,
		},
	]
	for variant: Dictionary in variants:
		var registry := {
			"schema_version": 1,
			"registry_contract_id": "mse.map.runtime.release.v1",
			"maps": [base_entry.duplicate(true)],
		}
		(variant.mutate as Callable).call(registry)
		Fixtures.write_json(REG_PATH, registry)
		Bridge.test_override_release_registry_path(REG_PATH)
		assert(
			not Bridge.is_formal_playable(4),
			"%s must not be playable" % variant.name
		)
		assert(
			str(Bridge.release_rejection_reason(4))
				== str(Bridge.REASON_RUNTIME_RELEASE_REGISTRY_INVALID),
			"%s must fail-closed with registry_invalid" % variant.name
		)
		assert(
			Bridge.released_map_ids().is_empty(),
			"%s must not partially load entries" % variant.name
		)
		assert(
			not bool(Bridge.registry_load_state().get("valid", true)),
			"%s load state must be invalid" % variant.name
		)
		assert(
			not Bridge.runtime_artifact_exists(4),
			"%s must not expose artifacts" % variant.name
		)
	# Positive control: valid registry loads; playable still gated by hash.
	var valid_registry := {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": [base_entry],
	}
	Fixtures.write_json(REG_PATH, valid_registry)
	Bridge.test_override_release_registry_path(REG_PATH)
	assert(bool(Bridge.registry_load_state().get("valid", false)))
	assert(Bridge.released_map_ids() == [4])
	assert(not Bridge.is_formal_playable(4))
	assert(
		str(Bridge.release_rejection_reason(4))
			== str(Bridge.REASON_RUNTIME_BUILD_NOT_APPROVED)
	)
	# Missing registry -> global fail-closed reason.
	Bridge.test_override_release_registry_path(MISSING_PATH)
	assert(not Bridge.is_formal_playable(4))
	assert(
		str(Bridge.release_rejection_reason(4))
			== str(Bridge.REASON_RUNTIME_RELEASE_REGISTRY_MISSING)
	)
	assert(Bridge.released_map_ids().is_empty())
	Fixtures.reset_seams()
	print("RELEASE_REGISTRY_CONSUMER_VALIDATION_PASS")
	get_tree().quit(0)
