class_name MonsterIdentity
extends RefCounted

## Canonical monster identity boundary.
##
## Production callers may provide either ``monster_id`` (canonical) or the
## historical ``monsterId`` transport spelling.  The value is normalized to
## an integer and every downstream lookup is performed against the
## ID-keyed canonical catalog.  Display text is intentionally never a lookup
## key; old name/alias/suffix compatibility belongs to an offline migration
## tool, not this runtime class.

const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"

static var _catalog_cache: Dictionary = {}
static var _entry_cache: Dictionary = {}
static var _appearance_cache: Dictionary = {}
static var _drop_cache: Dictionary = {}


static func monster_id(monster_data: Dictionary) -> int:
	if monster_data.has("monster_id"):
		return _coerce_positive_id(monster_data.get("monster_id"))
	if monster_data.has("monsterId"):
		return _coerce_positive_id(monster_data.get("monsterId"))
	return -1


static func _coerce_positive_id(value: Variant) -> int:
	# JSON integer IDs are the only numeric runtime form.  Do not let int()
	# silently turn empty, decimal, boolean, or alphanumeric transport tokens
	# into zero; zero and every non-positive value are outside the catalog.
	if value is int:
		var integer_value := int(value)
		return integer_value if integer_value > 0 else -1
	if value is String:
		var token := String(value)
		if token.is_empty():
			return -1
		for index in range(token.length()):
			var codepoint := token.unicode_at(index)
			if codepoint < 48 or codepoint > 57:
				return -1
		var parsed := int(token)
		return parsed if parsed > 0 else -1
	return -1


static func stable_key(monster_data: Dictionary) -> String:
	var value := monster_id(monster_data)
	return str(value) if value >= 0 else ""


static func catalog_entry(id: int) -> Dictionary:
	var key := _id_key(id)
	if key.is_empty():
		return {}
	if _entry_cache.has(key):
		return _entry_cache[key].duplicate(true)
	var value: Variant = _catalog().get("entries_by_id", {}).get(key, {})
	if value is Dictionary and not value.is_empty():
		_entry_cache[key] = value
		return value.duplicate(true)
	return {}


static func require_catalog_entry(id: int, use_context := "runtime") -> Dictionary:
	var entry := catalog_entry(id)
	if entry.is_empty():
		return {}
	var context := str(use_context)
	if context in ["runtime", "spawn", "combat"] and not bool(entry.get("runtime_allowed", false)):
		return {}
	if context == "editor" and not bool(entry.get("editor_placement", {}).get("allowed", false)):
		return {}
	if context == "appearance":
		var profile := appearance_profile(id)
		if profile.is_empty() or str(profile.get("status", "")) != "formal":
			return {}
	return entry


static func appearance_profile(id: int) -> Dictionary:
	var key := _id_key(id)
	if key.is_empty():
		return {}
	if _appearance_cache.has(key):
		return _appearance_cache[key].duplicate(true)
	var entry := catalog_entry(id)
	if entry.is_empty():
		return {}
	var profile_id := str(entry.get("appearance_profile_id", ""))
	var value: Variant = _catalog().get("appearance_profiles", {}).get(profile_id, {})
	if value is Dictionary and not value.is_empty():
		_appearance_cache[key] = value
		return value.duplicate(true)
	return {}


static func drop_profile(id: int) -> Dictionary:
	var key := _id_key(id)
	if key.is_empty():
		return {}
	if _drop_cache.has(key):
		return _drop_cache[key].duplicate(true)
	var entry := catalog_entry(id)
	if entry.is_empty():
		return {}
	var profile_id := str(entry.get("drop_profile_id", ""))
	var value: Variant = _catalog().get("drop_profiles", {}).get(profile_id, {})
	if value is Dictionary and not value.is_empty():
		_drop_cache[key] = value
		return value.duplicate(true)
	return {}


static func is_runtime_allowed(id: int) -> bool:
	return not require_catalog_entry(id, "runtime").is_empty()


static func service_runtime_entry(monster_data: Dictionary) -> Dictionary:
	# Kept as a narrow method name for callers migrating from the old service
	# catalog.  Its result is the canonical entry and still requires an ID.
	return catalog_entry(monster_id(monster_data))


static func behavior_profile(monster_data: Dictionary) -> Dictionary:
	var entry := catalog_entry(monster_id(monster_data))
	if entry.is_empty():
		return {}
	var combat: Variant = entry.get("combat", {})
	if not combat is Dictionary:
		return {}
	var profile: Variant = combat.get("behavior_profile", {})
	var result: Dictionary = profile.duplicate(true) if profile is Dictionary else {}
	var timing: Variant = combat.get("timing", {})
	if timing is Dictionary:
		result["timing"] = {
			"attackIntervalMs": int(timing.get("attack_interval_ms", 0)),
			"moveIntervalMs": int(timing.get("move_interval_ms", 0)),
			"confidence": str(timing.get("confidence", "")),
			"resolutionStatus": str(timing.get("resolution_status", "")),
		}
	var ai: Variant = combat.get("ai", {})
	if ai is Dictionary:
		result["serviceBehavior"] = {
			"aiCode": int(ai.get("ai_code", -1)),
			"image": int(ai.get("image", -1)),
			"viewRange": int(ai.get("view_range", 0)),
			"resolutionStatus": str(ai.get("resolution_status", "")),
			"sourceDistribution": str(ai.get("source_distribution", "")),
		}
	return result


static func boss_rule(monster_data: Dictionary, _ignored_rules: Dictionary = {}) -> Dictionary:
	var entry := catalog_entry(monster_id(monster_data))
	if entry.is_empty():
		return {}
	var combat: Variant = entry.get("combat", {})
	if not combat is Dictionary:
		return {}
	var rule: Variant = combat.get("boss_rule", {})
	return rule.duplicate(true) if rule is Dictionary else {}


static func animation_lookup_name(monster_data: Dictionary) -> String:
	# The return value is an opaque appearance profile token.  It is not a
	# display-name lookup and deliberately has no fallback path.
	var profile := appearance_profile(monster_id(monster_data))
	if profile.is_empty() or str(profile.get("status", "")) != "formal":
		return ""
	return str(profile.get("appearance_profile_id", ""))


static func reset_caches_for_test() -> void:
	_catalog_cache.clear()
	_entry_cache.clear()
	_appearance_cache.clear()
	_drop_cache.clear()


static func _id_key(id: int) -> String:
	var value := int(id)
	return str(value) if value >= 0 else ""


static func _catalog() -> Dictionary:
	if not _catalog_cache.is_empty():
		return _catalog_cache
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_catalog_cache = parsed if parsed is Dictionary else {}
	return _catalog_cache
