class_name SkillDataLoader
extends RefCounted

const SOURCE_OF_TRUTH_PATH := "res://assets/data/vanilla_176/skills_source_of_truth_v1.json"
const PACKAGE_ROOT := "res://assets/data/vanilla_176/skill_source_package_v1_0_1"
const PACKAGE_MANIFEST_PATH := PACKAGE_ROOT + "/manifest.json"
const PACKAGE_TEST_MANIFEST_PATH := PACKAGE_ROOT + "/mir2_176_skill_test_manifest_v1.json"
const SOURCE_OF_TRUTH_SHA256 := "1fdf28d3c575d18d2e7e0f875b008eb4f6f719752e4974cbca399c66c62c7c2c"
const PACKAGE_ZIP_SHA256 := "2dac78d285dff8d5f1ba36a8b83e0e8f11c70b76ace15a34ee7fbfb802862a22"
const RULESET_ID := "cn_mir2_176_vanilla_project_canonical_v1"
const CLASS_COUNTS := {"warrior": 6, "wizard": 14, "taoist": 13}
const RUNTIME_ALLOWED_STATUS_FRAGMENTS := [
	"historical_verified",
	"source_formula_reference",
	"project_canonical",
]
const RUNTIME_FORBIDDEN_STATUS_FRAGMENTS := [
	"candidate",
	"unverified",
	"needs_regression_verification",
	"selected_service_candidate",
	"project_adapter_c_candidate",
	"legacy_project_baseline",
	"rejected_version_mismatch",
]

static var _document: Dictionary = {}
static var _skills_by_id: Dictionary = {}
static var _ids_by_alias: Dictionary = {}


static func document() -> Dictionary:
	if _document.is_empty():
		var parsed := _read_json(SOURCE_OF_TRUTH_PATH)
		var validation := validate_document(parsed)
		if not bool(validation.get("valid", false)):
			push_error("技能唯一真源无效：%s" % "; ".join(validation.get("errors", [])))
			return {}
		_document = parsed
		_build_indexes()
	return _document


static func reload_data() -> Dictionary:
	_document.clear()
	_skills_by_id.clear()
	_ids_by_alias.clear()
	var loaded := document()
	return validate_document(loaded)


static func skill_ids() -> PackedStringArray:
	document()
	var ordered_ids: Array[String] = []
	for skill_id: String in _skills_by_id:
		ordered_ids.append(skill_id)
	ordered_ids.sort_custom(func(left: String, right: String) -> bool:
		return int(_skills_by_id[left].get("order", 0)) < int(_skills_by_id[right].get("order", 0))
	)
	return PackedStringArray(ordered_ids)


static func skill(skill_name_or_id: String) -> Dictionary:
	document()
	var stable_id := stable_skill_id(skill_name_or_id)
	return _skills_by_id.get(stable_id, {}).duplicate(true)


static func stable_skill_id(skill_name_or_id: String) -> String:
	document()
	if _skills_by_id.has(skill_name_or_id):
		return skill_name_or_id
	return str(_ids_by_alias.get(skill_name_or_id, ""))


static func display_name(skill_name_or_id: String) -> String:
	var definition := skill(skill_name_or_id)
	return str(definition.get("display_name", ""))


static func rank_record(skill_name_or_id: String, rank: int) -> Dictionary:
	var definition := skill(skill_name_or_id)
	var safe_rank := clampi(rank, 0, 3)
	var ranks: Array = definition.get("ranks", [])
	if safe_rank >= ranks.size():
		return {}
	var result: Dictionary = ranks[safe_rank].duplicate(true)
	result["skill_id"] = str(definition.get("skill_id", ""))
	result["display_name"] = str(definition.get("display_name", ""))
	result["class"] = str(definition.get("class", ""))
	var mp_costs: Array = definition.get("mp_cost_by_rank", [])
	result["mp_cost"] = int(mp_costs[safe_rank]) if safe_rank < mp_costs.size() else 0
	return result


static func legacy_records() -> Array:
	var records: Array = []
	for skill_id: String in skill_ids():
		var definition := skill(skill_id)
		for rank in range(4):
			var rank_data := rank_record(skill_id, rank)
			var raw_fields: Dictionary = definition.get("magic_db_reference", {}).get("raw_fields", {})
			records.append({
				"skillName": str(definition.get("display_name", "")),
				"profession": _legacy_profession_name(str(definition.get("class", ""))),
				"skillLevel": rank,
				"requiredCharacterLevel": int(rank_data.get("player_level_required", 1)),
				"trainingPoints": int(rank_data.get("proficiency_required_to_reach_rank", 0)),
				"manaCost": int(rank_data.get("mp_cost", 0)),
				"legacy_delay": raw_fields.get("legacy_delay"),
				"contentLayer": "vanilla_core",
				"profession_id": str(definition.get("class", "")),
				"skill_id": skill_id,
				"display_name": str(definition.get("display_name", "")),
				"source_contract": RULESET_ID,
				"source_status": {
					"membership": str(definition.get("membership_status", "")),
					"progression": str(definition.get("progression_status", "")),
					"mp": str(definition.get("mp_cost_status", "")),
				},
			})
	return records


static func package_test_manifest() -> Dictionary:
	return _read_json(PACKAGE_TEST_MANIFEST_PATH)


static func source_identity() -> Dictionary:
	return {
		"distribution": "project.hardcore.mir2_176_skill_sot.v1.0.1",
		"ruleset_id": RULESET_ID,
		"authority": "user_authoritative_override",
		"source_kind": "explicit_user_primary_override",
		"runtime_path": SOURCE_OF_TRUTH_PATH,
		"sot_sha256": SOURCE_OF_TRUTH_SHA256,
		"package_zip_sha256": PACKAGE_ZIP_SHA256,
		"package_manifest_path": PACKAGE_MANIFEST_PATH,
	}


static func runtime_status_allowed(status: String) -> bool:
	var errors: Array[String] = []
	_validate_status_string(status, "status_probe", errors)
	return errors.is_empty()


static func validate_package_integrity() -> Dictionary:
	var errors: Array[String] = []
	var manifest := _read_json(PACKAGE_MANIFEST_PATH)
	var checked := 0
	for raw_entry: Variant in manifest.get("files", []):
		if not raw_entry is Dictionary:
			errors.append("manifest_file_entry_not_dictionary")
			continue
		var relative_path := str(raw_entry.get("path", ""))
		var expected_hash := str(raw_entry.get("sha256", "")).to_lower()
		var path := PACKAGE_ROOT.path_join(relative_path)
		if not FileAccess.file_exists(path):
			errors.append("missing_package_file:%s" % relative_path)
			continue
		var actual_hash := FileAccess.get_sha256(path).to_lower()
		if actual_hash != expected_hash:
			errors.append("package_hash_mismatch:%s" % relative_path)
		checked += 1
	var runtime_hash := FileAccess.get_sha256(SOURCE_OF_TRUTH_PATH).to_lower()
	if runtime_hash != SOURCE_OF_TRUTH_SHA256:
		errors.append("runtime_sot_hash_mismatch")
	return {
		"valid": errors.is_empty() and checked == 10,
		"checked_files": checked,
		"errors": errors,
		"runtime_sot_sha256": runtime_hash,
	}


static func validate_document(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"valid": false, "errors": ["document_not_dictionary"]}
	var parsed := value as Dictionary
	if str(parsed.get("document_status", "")) != "project_canonical_source_of_truth":
		errors.append("document_status")
	var policy: Dictionary = parsed.get("global_policy", {})
	if str(policy.get("ruleset_id", "")) != RULESET_ID:
		errors.append("ruleset_id")
	if int(policy.get("exact_skill_count", -1)) != 33:
		errors.append("global_skill_count")
	var skills: Array = parsed.get("skills", [])
	if skills.size() != 33:
		errors.append("skill_count")
	var ids: Dictionary = {}
	var orders: Dictionary = {}
	var counts := {"warrior": 0, "wizard": 0, "taoist": 0}
	var names: Dictionary = {}
	for raw_skill: Variant in skills:
		if not raw_skill is Dictionary:
			errors.append("skill_not_dictionary")
			continue
		var definition := raw_skill as Dictionary
		var skill_id := str(definition.get("skill_id", ""))
		var profession_id := str(definition.get("class", ""))
		var order := int(definition.get("order", -1))
		if skill_id.is_empty() or ids.has(skill_id):
			errors.append("duplicate_or_empty_skill_id:%s" % skill_id)
		ids[skill_id] = true
		if order < 1 or order > 33 or orders.has(order):
			errors.append("duplicate_or_invalid_order:%d" % order)
		orders[order] = true
		if not counts.has(profession_id):
			errors.append("invalid_class:%s" % profession_id)
		else:
			counts[profession_id] += 1
		names[str(definition.get("display_name", ""))] = true
		if str(definition.get("content_layer", "")) != "vanilla":
			errors.append("non_vanilla_skill:%s" % skill_id)
		if str(definition.get("version_scope", "")) != "CN_MIR2_1_76":
			errors.append("invalid_version_scope:%s" % skill_id)
		var ranks: Array = definition.get("ranks", [])
		if ranks.size() != 4:
			errors.append("rank_count:%s" % skill_id)
		else:
			for rank in range(4):
				if int(ranks[rank].get("rank", -1)) != rank:
					errors.append("rank_order:%s" % skill_id)
		if definition.get("mp_cost_by_rank", []).size() != 4:
			errors.append("mp_rank_count:%s" % skill_id)
		_validate_runtime_status(definition, "membership_status", skill_id, errors)
		_validate_runtime_status(definition, "progression_status", skill_id, errors)
		_validate_runtime_status(definition, "mp_cost_status", skill_id, errors)
		for nested_key: String in ["timing", "geometry", "resource", "mechanics"]:
			var nested: Variant = definition.get(nested_key, {})
			if nested is Dictionary and nested.has("status"):
				_validate_status_string(str(nested.get("status", "")), "%s.%s" % [skill_id, nested_key], errors)
	for class_id: String in CLASS_COUNTS:
		if int(counts.get(class_id, 0)) != int(CLASS_COUNTS[class_id]):
			errors.append("class_count:%s" % class_id)
	for excluded: Variant in parsed.get("excluded_from_vanilla_core", []):
		var excluded_name := str(excluded).split("/")[0]
		if names.has(excluded_name):
			errors.append("excluded_skill_present:%s" % excluded_name)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"skill_count": skills.size(),
		"class_counts": counts,
		"unique_skill_ids": ids.size(),
	}


static func _build_indexes() -> void:
	_skills_by_id.clear()
	_ids_by_alias.clear()
	for raw_skill: Variant in _document.get("skills", []):
		if not raw_skill is Dictionary:
			continue
		var definition := raw_skill as Dictionary
		var skill_id := str(definition.get("skill_id", ""))
		_skills_by_id[skill_id] = definition
		_ids_by_alias[str(definition.get("display_name", ""))] = skill_id
		for alias: Variant in definition.get("aliases", []):
			_ids_by_alias[str(alias)] = skill_id


static func _validate_runtime_status(definition: Dictionary, key: String, skill_id: String, errors: Array[String]) -> void:
	_validate_status_string(str(definition.get(key, "")), "%s.%s" % [skill_id, key], errors)


static func _validate_status_string(status: String, field: String, errors: Array[String]) -> void:
	var lowered := status.to_lower()
	for forbidden: String in RUNTIME_FORBIDDEN_STATUS_FRAGMENTS:
		if lowered.contains(forbidden):
			errors.append("runtime_forbidden_status:%s:%s" % [field, status])
			return
	for allowed: String in RUNTIME_ALLOWED_STATUS_FRAGMENTS:
		if lowered.contains(allowed):
			return
	errors.append("runtime_unknown_status:%s:%s" % [field, status])


static func _legacy_profession_name(profession_id: String) -> String:
	return {"warrior": "战士", "wizard": "法师", "taoist": "道士"}.get(profession_id, "")


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}
