class_name SkillFootprintDiagnosticLog
extends RefCounted

## Debug-build JSONL sink for the immutable skill-footprint pipeline. This is
## observational only: gameplay damage is resolved in ground GU before any
## projected PX fields are recorded here.

const CONTRACT_ID := "skills.footprint_snapshot.runtime_diagnostic.jsonl.v1"
const SCHEMA_ID := "hardcore.skill_footprint_diagnostic.v1"
const LOG_PREFIX := "HARDCORE_SKILL_FOOTPRINT_DIAG "
const LOG_PATH := "user://combat_diagnostics/skill_footprint.jsonl"
const MAX_LOG_BYTES := 8 * 1024 * 1024
const MAX_RECENT_EVENTS := 256

static func _is_enabled() -> bool:
	return OS.is_debug_build() and RuntimeDiagnostics.file_output_enabled() and RuntimeDiagnostics.skill_geometry_enabled()
static var _recent_events: Array[Dictionary] = []


static func record(raw_event: Dictionary) -> Dictionary:
	var event: Dictionary = _json_safe(raw_event)
	event["schema"] = SCHEMA_ID
	event["contract_id"] = CONTRACT_ID
	event["timestamp_ms"] = Time.get_ticks_msec()
	event["physics_tick"] = Engine.get_physics_frames()
	_recent_events.append(event.duplicate(true))
	if _recent_events.size() > MAX_RECENT_EVENTS:
		_recent_events.pop_front()
	if not _is_enabled():
		return event
	var encoded := JSON.stringify(event)
	print(LOG_PREFIX + encoded)
	_append_json_line(encoded)
	return event


static func recent_events() -> Array[Dictionary]:
	return _recent_events.duplicate(true)


static func clear_recent_events() -> void:
	_recent_events.clear()


static func runtime_log_path() -> String:
	return LOG_PATH


static func _append_json_line(encoded: String) -> void:
	var directory_path := LOG_PATH.get_base_dir()
	var absolute_directory := ProjectSettings.globalize_path(directory_path)
	if not DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.make_dir_recursive_absolute(absolute_directory)
	if not FileAccess.file_exists(LOG_PATH):
		var created := FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if created == null:
			return
		created.close()
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		return
	if file.get_length() >= MAX_LOG_BYTES:
		file.close()
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE_READ)
		if file == null:
			return
	else:
		file.seek_end()
	file.store_line(encoded)
	file.close()


static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			var vector: Vector2 = value
			return {"x": vector.x, "y": vector.y}
		TYPE_VECTOR2I:
			var vector: Vector2i = value
			return {"x": vector.x, "y": vector.y}
		TYPE_PACKED_VECTOR2_ARRAY:
			var result: Array = []
			for point: Vector2 in value:
				result.append(_json_safe(point))
			return result
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var result := {}
			for key: Variant in source.keys():
				result[str(key)] = _json_safe(source[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in value:
				result.append(_json_safe(item))
			return result
	return value
