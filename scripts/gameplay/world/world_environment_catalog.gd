extends RefCounted

const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _values: Dictionary
var _world_ref: WeakRef
var _world: Object:
	get:
		return _world_ref.get_ref() if _world_ref != null else null
	set(value):
		_world_ref = weakref(value) if value != null else null

func owner_thread_id() -> int:
	return _owner_thread

func configure_owner(publication: Dictionary, world: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread or world == null or world is Node or world is Resource or not world.has_method("owner_thread_id") or world.owner_thread_id() != _owner_thread or not world.has_method("fault"):
		push_error("Environment catalog requires S owner world")
		return false
	_world = world
	for field: String in ["profiles", "themes", "region_content", "resource_exists"]:
		if not publication.get(field) is Dictionary:
			_world.fault("environment_catalog_publication_missing", {"field": field})
			return false
	var copied := Graph.copy_and_seal({"profiles": publication.profiles, "themes": publication.themes, "region_content": publication.region_content, "resource_exists": publication.resource_exists})
	if not copied.ok:
		_world.fault("environment_publication_live_value", {"errors": copied.errors})
		return false
	_values = copied.value
	_configured = true
	return true

func _value(table: String, key: Variant) -> Variant:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not _values[table].has(key):
		_world.fault("environment_catalog_value_not_published", {"table": table, "key": key})
		return null
	return _values[table][key]

func get_map_profile(map_id: int) -> Dictionary:
	var value: Variant = _value("profiles", map_id)
	return value if value is Dictionary else {}

func require_background_values(runtime_id: int, presentation_id: int) -> bool:
	if not _configured or not _values.profiles.has(presentation_id) or not _values.region_content.has(runtime_id):
		_world.fault("environment_background_catalog_missing", {"runtime_id": runtime_id, "presentation_id": presentation_id})
		return false
	var profile: Variant = _values.profiles[presentation_id]
	if not profile is Dictionary or not _values.region_content[runtime_id] is Dictionary:
		_world.fault("environment_background_catalog_invalid", {"runtime_id": runtime_id})
		return false
	var theme_id := str(profile.get("theme", ""))
	if not _values.themes.has(theme_id) or not _values.themes[theme_id] is Dictionary:
		_world.fault("environment_background_theme_missing", {"theme_id": theme_id})
		return false
	var path := str(profile.get("collision_mask_path", ""))
	if not path.is_empty() and (not _values.resource_exists.has(path) or not _values.resource_exists[path] is bool):
		_world.fault("environment_background_mask_qualification_missing", {"path": path})
		return false
	return true

func get_theme(theme_id: String) -> Dictionary:
	var value: Variant = _value("themes", theme_id)
	return value if value is Dictionary else {}

func get_map_content(map_id: int) -> Dictionary:
	var value: Variant = _value("region_content", map_id)
	return value.duplicate(true) if value is Dictionary else {}

func resource_exists(path: String) -> bool:
	var value: Variant = _value("resource_exists", path)
	return value if value is bool else false
