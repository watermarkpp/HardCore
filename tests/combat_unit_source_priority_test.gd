extends Node

const POLICY_PATH := "res://assets/data/source_priority_policy.json"
const CONTRACT_PATH := "res://assets/data/combat_unit_contract_v1.json"
const DOCUMENT_PATH := "res://docs/COMBAT-UNIT-V1.md"


func _ready() -> void:
	var policy := _load_json(POLICY_PATH)
	var contract := _load_json(CONTRACT_PATH)
	assert(str(policy.routing.combat_movement_ai_projectile_distance_units) == "combat_units")
	var lane: Dictionary = policy.lanes.combat_units
	assert(lane.sources.size() == 1)
	var primary: Dictionary = lane.sources[0]
	assert(str(primary.tier) == "primary")
	assert(int(primary.order) == 0)
	assert(bool(primary.eligible))
	assert(str(primary.contractId) == "combat.unit.gu_gs_px.v1")
	assert(str(primary.rootPrefix) == "assets/data/combat_unit_contract_v1.json")
	assert(str(contract.contractId) == str(primary.contractId))
	assert(str(contract.authority.evidenceSha256) == str(primary.evidenceSha256))
	assert(FileAccess.get_sha256(DOCUMENT_PATH).to_upper() == str(primary.evidenceSha256))
	assert(float(contract.rangesGu.normalMelee) == 2.0)
	assert(float(contract.rangesGu.fireSword) == 2.0)
	assert(float(contract.rangesGu.halfMoon) == 2.0)
	assert(float(contract.rangesGu.thrust) == 3.0)
	assert(float(contract.rangesGu.hellfire) == 5.0)
	assert(float(contract.rangesGu.laser) == 8.0)
	assert(float(contract.rangesGu.attackLock) == 10.0)
	assert(float(contract.rangesGu.spellLock) == 12.0)
	print("COMBAT_UNIT_SOURCE_PRIORITY_PASS: explicit user GU contract is the unique primary unit source")
	get_tree().quit(0)


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, path)
	return parsed as Dictionary
