class_name MapEditorPathSafety
extends RefCounted

## Path and identity primitives shared by destructive map-editor operations.
##
## This helper deliberately works with lexical, normalized paths plus Godot's
## reparse-point probe.  It does not claim to resolve every platform-specific
## filesystem race; callers must validate immediately before mutating.

const MAP_ID_PATTERN := "^[A-Za-z0-9][A-Za-z0-9_-]*$"


static func map_id_error(map_id: String) -> String:
	if map_id.is_empty():
		return "map_id_empty"
	if map_id != map_id.strip_edges():
		return "map_id_invalid_component"
	var pattern := RegEx.new()
	if pattern.compile(MAP_ID_PATTERN) != OK:
		return "map_id_pattern_unavailable"
	if pattern.search(map_id) == null:
		return "map_id_invalid_component"
	return ""


static func normalize_path(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return ""
	return normalized.simplify_path()


static func absolute_path(path: String) -> String:
	var normalized := normalize_path(path)
	if normalized.is_empty():
		return ""
	var absolute := normalized
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		absolute = ProjectSettings.globalize_path(normalized)
	return normalize_path(absolute)


static func path_key(path: String) -> String:
	var normalized := absolute_path(path)
	if OS.get_name() == "Windows":
		return normalized.to_lower()
	return normalized


static func strict_child_path(root: String, target: String) -> Dictionary:
	var root_absolute := absolute_path(root)
	var target_absolute := absolute_path(target)
	if root_absolute.is_empty() or target_absolute.is_empty():
		return {"ok": false, "error": "path_empty"}
	var root_key := path_key(root_absolute)
	var target_key := path_key(target_absolute)
	if root_key == target_key:
		return {"ok": false, "error": "target_is_workspace_root"}
	var root_prefix := root_key
	if not root_prefix.ends_with("/"):
		root_prefix += "/"
	if not target_key.begins_with(root_prefix):
		return {"ok": false, "error": "path_escape_attempt"}
	var relative := target_key.substr(root_prefix.length())
	if relative.is_empty() or relative.contains("/"):
		return {"ok": false, "error": "target_not_single_child"}
	return {
		"ok": true,
		"root_absolute": root_absolute,
		"target_absolute": target_absolute,
		"relative": relative,
	}


static func link_status(path: String) -> Dictionary:
	var absolute := absolute_path(path)
	if absolute.is_empty():
		return {"ok": false, "error": "link_probe_path_empty"}
	var parent := DirAccess.open(absolute.get_base_dir())
	if parent == null:
		return {"ok": false, "error": "link_probe_parent_unavailable"}
	var leaf := absolute.get_file()
	if leaf.is_empty():
		return {"ok": false, "error": "link_probe_leaf_empty"}
	return {
		"ok": true,
		"path": absolute,
		"is_link": parent.is_link(leaf),
	}
