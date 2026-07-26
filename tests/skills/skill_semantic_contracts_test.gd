extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const WarriorContracts := preload("res://tests/skills/warrior_skill_semantic_contracts.gd")
const WizardContracts := preload("res://tests/skills/wizard_skill_semantic_contracts.gd")
const TaoistContracts := preload("res://tests/skills/taoist_skill_semantic_contracts.gd")

var _suites: Array[RefCounted] = []


func _ready() -> void:
	assert(Loader.reload_data().valid)
	var manifest := Loader.package_test_manifest()
	var expected: Dictionary = {}
	for entry_value: Variant in manifest.get("skill_tests", []):
		assert(entry_value is Dictionary)
		var entry: Dictionary = entry_value
		var contract_id := str(entry.get("id", ""))
		assert(not contract_id.is_empty())
		assert(str(entry.get("priority", "")) == "P1")
		assert(not expected.has(contract_id))
		expected[contract_id] = true
	assert(expected.size() == 150)

	var validators: Dictionary = {}
	_suites = [
		WarriorContracts.new(),
		WizardContracts.new(),
		TaoistContracts.new(),
	]
	for suite: RefCounted in _suites:
		var suite_validators: Dictionary = suite.call("validators")
		for contract_id: String in suite_validators:
			assert(not validators.has(contract_id), "duplicate semantic validator: %s" % contract_id)
			validators[contract_id] = suite_validators[contract_id]
	assert(validators.size() == 150)
	for contract_id: String in expected:
		assert(validators.has(contract_id), "missing semantic validator: %s" % contract_id)
	for contract_id: String in validators:
		assert(expected.has(contract_id), "extra semantic validator: %s" % contract_id)

	var executed: Dictionary = {}
	for contract_id: String in expected:
		var validator: Callable = validators[contract_id]
		assert(validator.is_valid(), "invalid semantic validator: %s" % contract_id)
		var passed := bool(validator.call())
		executed[contract_id] = true
		assert(passed, "semantic contract failed: %s" % contract_id)
	assert(executed.size() == 150)
	print("SKILL_SEMANTIC_CONTRACTS_PASS: 150/150 P1 validators executed with exact manifest key coverage")
	get_tree().quit()
