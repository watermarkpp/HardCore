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
	if entry.get("status", "") != "formal_primary_client_animation":
		return null
	var path := str(entry.get("resource_path", ""))
	return load_texture_path(path)


static func icon_texture(skill_name_or_id: String) -> Texture2D:
	var entry := profile(skill_name_or_id)
	if entry.get("status", "") != "formal_primary_client_animation":
		return null
	var icon: Dictionary = entry.get("icon", {})
	var path := "res://%s" % str(icon.get("path", entry.get("icon_path", "")))
	return load_texture_path(path)


static func load_texture_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			return imported
	# Clean worktrees can run the safe headless test runner before Godot has
	# imported newly generated PNGs. Decode the exact source PNG directly so
	# tests and runtime use the same pixels; exports still use normal imports.
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


static func animation_duration(skill_name_or_id: String) -> float:
	var animation: Dictionary = profile(skill_name_or_id).get("animation", {})
	return (
		float(animation.get("frame_count", 0))
		* float(animation.get("frame_time_ms", 0))
		/ 1000.0
	)


static func direction_index(direction: Vector2) -> int:
	if direction.length_squared() <= 0.0:
		return 8
	# MirClient.GetFlyDirection16: 0=up, 4=right, 8=down, 12=left.
	var normalized_angle := fposmod(direction.angle() + PI / 2.0, TAU)
	return posmod(int(round(normalized_angle / TAU * 16.0)), 16)


static func has_formal_visual(skill_name_or_id: String) -> bool:
	var entry := profile(skill_name_or_id)
	return (
		entry.get("status", "") == "formal_primary_client_animation"
		and entry.get("animation", {}).get("contract", "") == "caster_skill_animation.v1"
		and texture(skill_name_or_id) != null
		and icon_texture(skill_name_or_id) != null
	)


static func active_skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id: String in _manifest().get("skillCoverage", {}):
		if _manifest().skillCoverage[skill_id].get("status", "") == "formal_primary_client_animation":
			result.append(skill_id)
	return result


static func _manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_manifest_cache = parsed if parsed is Dictionary else {}
	return _manifest_cache
