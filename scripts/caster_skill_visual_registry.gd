class_name CasterSkillVisualRegistry
extends RefCounted

const MANIFEST_PATH := "res://assets/data/caster_skill_visuals.json"

static var _manifest_cache: Dictionary = {}


static func profile(skill_name_or_id: String) -> Dictionary:
	var skill_id := ProfessionRules.skill_id(skill_name_or_id)
	if skill_id.is_empty():
		return {}
	var coverage: Dictionary = _manifest().get("skillCoverage", {}).get(skill_id, {})
	if coverage.is_empty():
		return {}
	var result := coverage.duplicate(true)
	result["skill_id"] = skill_id
	var asset_id := str(result.get("asset_id", ""))
	if not asset_id.is_empty():
		result.merge(_manifest().get("assets", {}).get(asset_id, {}), true)
		result["asset_id"] = asset_id
		result["resource_path"] = "res://%s" % str(result.get("path", ""))
	return result


static func texture(skill_name_or_id: String) -> Texture2D:
	var entry := profile(skill_name_or_id)
	if entry.get("status", "") != "formal_primary_client_pixel":
		return null
	var path := str(entry.get("resource_path", ""))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func has_formal_visual(skill_name_or_id: String) -> bool:
	var entry := profile(skill_name_or_id)
	return entry.get("status", "") == "formal_primary_client_pixel" and texture(skill_name_or_id) != null


static func active_skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id: String in _manifest().get("skillCoverage", {}):
		if _manifest().skillCoverage[skill_id].get("status", "") == "formal_primary_client_pixel":
			result.append(skill_id)
	return result


static func _manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_manifest_cache = parsed if parsed is Dictionary else {}
	return _manifest_cache
