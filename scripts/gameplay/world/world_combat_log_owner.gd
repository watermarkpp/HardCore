extends RefCounted
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _policy: Dictionary
func _init(core: RefCounted, policy: Dictionary) -> void:
	_core=weakref(core); _policy=policy
func owner_thread_id() -> int: return _owner

## Debug-build JSONL sink for tracing one melee action from input through
## geometry, accuracy and damage commit.  This service is observational only:
## it must never decide whether an attack is accepted or mutate combat state.

const CONTRACT_ID := "combat.melee.runtime_diagnostic.jsonl.v1"
const SCHEMA_ID := "hardcore.melee_diagnostic.v1"
const LOG_PREFIX := "HARDCORE_MELEE_DIAG "
const LOG_PATH := "user://combat_diagnostics/melee.jsonl"
const MAX_LOG_BYTES := 8 * 1024 * 1024
const MAX_RECENT_EVENTS := 256

func capture_enabled() -> bool:
	return bool(_policy.combat_enabled)

func _file_output_enabled() -> bool:
	return capture_enabled() and bool(_policy.file_output_enabled)

var _recent_events: Array[Dictionary] = []


func record(raw_event: Dictionary) -> Dictionary:
	if not capture_enabled():
		return {}
	var event: Dictionary = _json_safe(raw_event)
	event["schema"] = SCHEMA_ID
	event["contract_id"] = CONTRACT_ID
	event["timestamp_ms"] = Time.get_ticks_msec()
	event["physics_tick"] = int(_core.get_ref().clock_ports.get_physics_frames())
	_recent_events.append(event.duplicate(true))
	if _recent_events.size() > MAX_RECENT_EVENTS:
		_recent_events.pop_front()
	if not _file_output_enabled():
		return event
	var encoded := JSON.stringify(event)
	pass # Main prints once with the same actual file-output leaf.
	_append_json_line(encoded)
	return event


func recent_events() -> Array[Dictionary]:
	return _recent_events.duplicate(true)


func clear_recent_events() -> void:
	_recent_events.clear()


func runtime_log_path() -> String:
	return LOG_PATH


func _append_json_line(encoded: String) -> void:
	_core.get_ref().emit_original_main_event(&"original_diagnostic_line",["combat",encoded])

func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			var vector: Vector2 = value
			return {"x": vector.x, "y": vector.y}
		TYPE_VECTOR2I:
			var vector: Vector2i = value
			return {"x": vector.x, "y": vector.y}
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
