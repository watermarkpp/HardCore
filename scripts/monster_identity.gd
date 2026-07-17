class_name MonsterIdentity
extends RefCounted

const BEHAVIOR_PATH := "res://assets/data/monster_behavior_profiles.json"
const ANIMATION_PATH := "res://assets/data/runtime/monster_animation_catalog.json"
const SERVICE_RUNTIME_PATH := "res://assets/data/service_monster_runtime_catalog.json"

static var _behavior_catalog: Dictionary = {}
static var _animation_by_id: Dictionary = {}
static var _service_runtime_catalog: Dictionary = {}


static func monster_id(monster_data: Dictionary) -> int:
	return int(monster_data.get("monsterId", monster_data.get("monster_id", -1)))


static func stable_key(monster_data: Dictionary) -> String:
	var value := monster_id(monster_data)
	return str(value) if value >= 0 else ""


static func behavior_profile(monster_data: Dictionary) -> Dictionary:
	var runtime_entry := service_runtime_entry(monster_data)
	var runtime_profile: Variant = runtime_entry.get("behaviorProfile", {})
	var profile: Dictionary = runtime_profile.duplicate(true) if runtime_profile is Dictionary else {}
	var catalog := _behavior()
	var profile_id := ""
	var key := stable_key(monster_data)
	if not key.is_empty():
		profile_id = str(catalog.get("profileByMonsterId", {}).get(key, ""))
	if profile_id.is_empty():
		for legacy_name: String in _legacy_names(monster_data):
			profile_id = str(catalog.get("legacyNameToProfile", {}).get(legacy_name, ""))
			if not profile_id.is_empty():
				break
	var authored: Variant = catalog.get("profiles", {}).get(profile_id, {})
	if authored is Dictionary:
		_merge_recursive(profile, authored)
	return profile


static func service_runtime_entry(monster_data: Dictionary) -> Dictionary:
	var catalog := _service_runtime()
	var key := stable_key(monster_data)
	var by_id: Variant = catalog.get("runtimeByMonsterId", {})
	if not key.is_empty() and by_id is Dictionary:
		var direct: Variant = by_id.get(key, {})
		if direct is Dictionary and not direct.is_empty():
			return direct.duplicate(true)
	var legacy_ids: Variant = catalog.get("legacyNameToMonsterId", {})
	if legacy_ids is Dictionary and by_id is Dictionary:
		for legacy_name: String in _legacy_names(monster_data):
			if not legacy_ids.has(legacy_name):
				continue
			var legacy_key := str(int(legacy_ids.get(legacy_name, -1)))
			var legacy: Variant = by_id.get(legacy_key, {})
			if legacy is Dictionary and not legacy.is_empty():
				return legacy.duplicate(true)
	return {}


static func boss_rule(monster_data: Dictionary, rules: Dictionary) -> Dictionary:
	var key := stable_key(monster_data)
	var by_id: Variant = rules.get("runtimeRulesByMonsterId", {})
	if not key.is_empty() and by_id is Dictionary:
		var direct: Variant = by_id.get(key, {})
		if direct is Dictionary and not direct.is_empty():
			return direct.duplicate(true)
	var legacy_rules: Variant = rules.get("runtimeRules", {})
	if legacy_rules is Dictionary:
		for legacy_name: String in _legacy_names(monster_data):
			var legacy: Variant = legacy_rules.get(legacy_name, {})
			if legacy is Dictionary and not legacy.is_empty():
				return legacy.duplicate(true)
	var legacy_ids: Variant = rules.get("legacyNameToMonsterId", {})
	if legacy_ids is Dictionary and by_id is Dictionary:
		for legacy_name: String in _legacy_names(monster_data):
			var legacy_id := str(int(legacy_ids.get(legacy_name, -1)))
			var canonical: Variant = by_id.get(legacy_id, {})
			if canonical is Dictionary and not canonical.is_empty():
				return canonical.duplicate(true)
	return {}


static func animation_lookup_name(monster_data: Dictionary) -> String:
	_ensure_animation_index()
	var key := stable_key(monster_data)
	if not key.is_empty():
		var row: Variant = _animation_by_id.get(key, {})
		if row is Dictionary and str(row.get("status", "")) == "formal":
			return str(row.get("resource_lookup", row.get("name", "")))
	for legacy_name: String in _legacy_names(monster_data):
		if not legacy_name.is_empty():
			return legacy_name
	return ""


static func reset_caches_for_test() -> void:
	_behavior_catalog.clear()
	_animation_by_id.clear()
	_service_runtime_catalog.clear()


static func _legacy_names(monster_data: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for candidate: String in [str(monster_data.get("name", "")), str(monster_data.get("baseName", ""))]:
		if not candidate.is_empty() and not names.has(candidate):
			names.append(candidate)
	return names


static func _behavior() -> Dictionary:
	if _behavior_catalog.is_empty():
		_behavior_catalog = _load_json(BEHAVIOR_PATH)
	return _behavior_catalog


static func _service_runtime() -> Dictionary:
	if _service_runtime_catalog.is_empty():
		_service_runtime_catalog = _load_json(SERVICE_RUNTIME_PATH)
	return _service_runtime_catalog


static func _ensure_animation_index() -> void:
	if not _animation_by_id.is_empty():
		return
	var catalog := _load_json(ANIMATION_PATH)
	for value: Variant in catalog.get("monsters", []):
		if value is Dictionary:
			var key := str(int(value.get("monster_id", -1)))
			if key != "-1":
				_animation_by_id[key] = value


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


static func _merge_recursive(target: Dictionary, overlay: Dictionary) -> void:
	for key: Variant in overlay:
		var value: Variant = overlay[key]
		if value is Dictionary and target.get(key, null) is Dictionary:
			var nested: Dictionary = target[key]
			_merge_recursive(nested, value)
			target[key] = nested
		else:
			target[key] = value.duplicate(true) if value is Dictionary or value is Array else value
