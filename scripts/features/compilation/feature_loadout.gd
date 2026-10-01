extends RefCounted

const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Effective := preload("res://scripts/features/adapters/effective_skill_definition.gd")
var _bundle: Dictionary = {}
var _signature := ""
var compile_count := 0
var last_errors: Array = []

func synchronize(catalog: Dictionary, sources: Array, authority: Dictionary, base_stats: Dictionary = {}) -> bool:
	var base_revision := preload("res://scripts/skills/skill_data_loader.gd").configuration_revision()
	var signature := (str(catalog.get("revision", "")) + base_revision + JSON.stringify(sources)).sha256_text()
	if signature == _signature:
		return _validate_numeric_candidate(_bundle, base_stats, false)
	var result := Compiler.compile_loadout(catalog, sources, authority)
	if not bool(result.success):
		last_errors = result.errors
		return false
	if not _validate_numeric_candidate(result.bundle, base_stats):
		return false
	_bundle = result.bundle
	_signature = signature
	compile_count += 1
	last_errors = []
	return true


func _validate_numeric_candidate(candidate: Dictionary, base_stats: Dictionary, validate_skills := true) -> bool:
	var preview := _apply_stats_from(candidate, base_stats)
	if not bool(preview.success):
		last_errors = [preview.reason]
		return false
	for identity: String in candidate.get("skill_operations", {}) if validate_skills else {}:
		var definition := preload("res://scripts/skills/skill_data_loader.gd").skill(identity)
		var applied := Effective.build(definition, candidate.skill_operations[identity],
			preload("res://scripts/features/adapters/feature_authority.gd").SKILL_FIELDS)
		if not bool(applied.success):
			last_errors = [applied.reason]
			return false
	last_errors = []
	return true

func bundle() -> Dictionary:
	return _bundle

func effective_definition(base: Dictionary) -> Dictionary:
	var id := str(base.get("entity_id", ""))
	var operations: Array = _bundle.get("skill_operations", {}).get(id, [])
	if operations.is_empty():
		return {"success":true,"definition":base,"reason":""}
	return Effective.build(base, operations, preload("res://scripts/features/adapters/feature_authority.gd").SKILL_FIELDS)

func apply_stats(base: Dictionary) -> Dictionary:
	return _apply_stats_from(_bundle, base)


func _apply_stats_from(bundle_value: Dictionary, base: Dictionary) -> Dictionary:
	var operations: Array = bundle_value.get("stat_operations", [])
	if operations.is_empty():
		return {"success":true,"stats":base}
	if base.is_empty():
		return {"success":false,"reason":"feature_base_stats_required"}
	var result := base.duplicate(true)
	var grouped := {}
	for operation: Dictionary in operations:
		var key: String = operation.stat
		var list: Array = grouped.get(key, [])
		list.append(operation)
		grouped[key] = list
	for key: String in grouped:
		if not result.get(key) is int and not result.get(key) is float:
			return {"success":false,"reason":"feature_unknown_base_stat:" + key}
		var value := float(result[key])
		for operation: Dictionary in grouped[key]:
			if operation.op == "add":
				value += float(operation.value)
		for operation: Dictionary in grouped[key]:
			if operation.op == "multiply":
				value *= float(operation.value)
		if not is_finite(value) or value < 0.0 or value > 2147483647.0:
			return {"success":false,"reason":"feature_stat_range:" + key}
		result[key] = roundi(value) if base[key] is int else value
	for prefix: String in ["attack", "magic", "tao"]:
		if not result.has(prefix + "_min") and not result.has(prefix + "_max"):
			continue
		if not Compiler._number(result.get(prefix + "_min")) or not Compiler._number(result.get(prefix + "_max")):
			return {"success":false,"reason":"feature_missing_stat_pair:" + prefix}
		if result[prefix + "_min"] > result[prefix + "_max"]:
			return {"success":false,"reason":"feature_inverted_stat:" + prefix}
	return {"success":true,"stats":result}
