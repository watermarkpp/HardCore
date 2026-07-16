class_name MapAssetCalibrationService
extends RefCounted

const OVERRIDE_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_overrides.json"


static func effective_asset(base_asset: Dictionary, override_path := OVERRIDE_PATH) -> Dictionary:
	var asset := base_asset.duplicate(true)
	var overrides: Dictionary = load_overrides(override_path).get("overrides", {})
	var change: Dictionary = overrides.get(str(asset.get("asset_id", "")), {})
	for key: Variant in change:
		asset[key] = change[key]
	return asset


static func load_overrides(path := OVERRIDE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"asset_schema_version": 2, "content_layer": "personal_expansion", "overrides": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"asset_schema_version": 2, "content_layer": "personal_expansion", "overrides": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {"asset_schema_version": 2, "content_layer": "personal_expansion", "overrides": {}}


static func validate_draft(base_asset: Dictionary, draft: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var footprint: Array = draft.get("footprint_tiles", base_asset.get("footprint_tiles", []))
	var anchor: Array = draft.get("anchor_px", base_asset.get("anchor_px", []))
	if footprint.size() != 2 or int(footprint[0]) <= 0 or int(footprint[1]) <= 0:
		errors.append("invalid_footprint")
	if anchor.size() != 2 or int(anchor[0]) < 0 or int(anchor[1]) < 0:
		errors.append("invalid_anchor")
	var collision_policy := str(draft.get("collision_policy", base_asset.get("collision_policy", "")))
	if collision_policy not in ["none", "preset", "manual", "terrain_stamp_generated", "solid_footprint", "custom_polygon"]:
		errors.append("invalid_collision_policy")
	if str(base_asset.get("asset_type", "")) == "ground_brush" and (int(footprint[0]) != 1 or int(footprint[1]) != 1):
		errors.append("ground_footprint_requires_new_normalized_image")
	return errors


static func save_override(asset_id: String, draft: Dictionary, path := OVERRIDE_PATH) -> Dictionary:
	var base := MapAssetCatalogService.find_base_asset(asset_id)
	if base.is_empty():
		return {"ok": false, "errors": ["asset_not_found"]}
	var errors := validate_draft(base, draft)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var payload := load_overrides(path)
	var overrides: Dictionary = payload.get("overrides", {})
	var allowed := {}
	for key: String in ["anchor_px", "anchor_tile", "anchor_mode", "footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles", "collision_footprint_tiles", "approved_scale", "logical_scale_level", "collision_policy", "navigation_policy", "occlusion", "placeable", "calibration_status"]:
		if draft.has(key):
			allowed[key] = draft[key]
	allowed["content_layer"] = "personal_expansion"
	overrides[asset_id] = allowed
	payload["overrides"] = overrides
	return _write_atomic(path, payload)


static func _write_atomic(path: String, value: Dictionary) -> Dictionary:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var mkdir_error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if mkdir_error != OK:
		return {"ok": false, "errors": ["calibration_mkdir_failed:%d" % mkdir_error]}
	var temporary := resolved + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["calibration_temp_open_failed"]}
	file.store_string(JSON.stringify(value, "  ", true, true) + "\n")
	file.flush(); file.close()
	var backup := resolved + ".bak"
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(resolved):
		var backup_error := DirAccess.rename_absolute(resolved, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["calibration_backup_failed:%d" % backup_error]}
	var promote_error := DirAccess.rename_absolute(temporary, resolved)
	if promote_error != OK:
		if FileAccess.file_exists(backup): DirAccess.rename_absolute(backup, resolved)
		return {"ok": false, "errors": ["calibration_promote_failed:%d" % promote_error]}
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	return {"ok": true, "path": path}
