extends Node

const DIAGNOSTICS_PATH := "res://scripts/runtime_diagnostics.gd"
const PASS_MARKER := "HC_FIXED_COUNTER_BACKEND_CONTRACT_20261009_PASS"

var _failures := 0

func _check(condition: bool, detail: String) -> void:
	if not condition:
		_failures += 1
		push_error("FIXED_COUNTER_BACKEND_FAIL: " + detail)

func _call(script: Script, method: StringName, args: Array = []) -> Variant:
	return script.callv(method, args)

func _ready() -> void:
	var diagnostics_script: Script = load(DIAGNOSTICS_PATH)
	if diagnostics_script == null:
		print("HC_TEST_FAIL: diagnostics script unavailable")
		get_tree().quit(1)
		return
	var required_methods: Array[StringName] = [
		&"counter_id",
		&"increment_performance_counter_id",
		&"begin_timed_segment_id",
		&"end_timed_segment_id",
		&"begin_timed_segment",
		&"end_timed_segment",
		&"performance_counter",
		&"performance_counters",
		&"performance_enabled",
		&"performance_detail_enabled",
		&"set_device_lab_performance_enabled",
		&"set_device_lab_detail_mode",
		&"reset_performance_window",
		&"read_performance_window",
		&"set_performance_value",
		&"record_performance_max",
	]
	for method: StringName in required_methods:
		if not diagnostics_script.has_method(method):
			print("HC_TEST_FAIL: missing method %s" % method)
			get_tree().quit(1)
			return
	var fields_variant: Variant = diagnostics_script.get("PERFORMANCE_COUNTER_FIELDS")
	if not (fields_variant is Array):
		print("HC_TEST_FAIL: fixed field declaration unavailable")
		get_tree().quit(1)
		return
	var fields: Array = fields_variant
	_check(not fields.is_empty(), "fixed field contract is nonempty")
	var ids: Dictionary = {}
	for raw_field: Variant in fields:
		var field: StringName = StringName(str(raw_field))
		var id: int = int(_call(diagnostics_script, &"counter_id", [field]))
		_check(id >= 0, "fixed field resolves to an id: %s" % field)
		_check(not ids.has(id), "fixed ids are unique: %s" % field)
		ids[id] = field
	_check(int(_call(diagnostics_script, &"counter_id", [StringName("unknown_fixed_backend_field")])) == -1, "unknown id is -1")

	var initial_enabled: bool = bool(_call(diagnostics_script, &"performance_enabled"))
	var target_field: StringName = StringName(str(fields[0]))
	var target_id: int = int(_call(diagnostics_script, &"counter_id", [target_field]))
	if not initial_enabled:
		_call(diagnostics_script, &"increment_performance_counter_id", [target_id, 10])
		_check(int(_call(diagnostics_script, &"performance_counter", [target_field])) == 0, "non-override disabled gate suppresses fixed counter writes")
	_call(diagnostics_script, &"set_device_lab_performance_enabled", [true])
	_call(diagnostics_script, &"set_device_lab_detail_mode", ["full"])
	_check(not bool(diagnostics_script.get("_performance_fields_initialized")), "fresh script has no performance window before cold end")
	var cold_legacy_usec: int = int(_call(diagnostics_script, &"end_timed_segment", [target_field, Time.get_ticks_usec() - 5000]))
	var cold_id: int = int(_call(diagnostics_script, &"counter_id", [StringName(str(fields[1]))]))
	var cold_id_usec: int = int(_call(diagnostics_script, &"end_timed_segment_id", [cold_id, Time.get_ticks_usec() - 5000]))
	_check(cold_legacy_usec > 0 and cold_id_usec > 0, "cold end paths return positive elapsed")
	_check(int(_call(diagnostics_script, &"performance_counter", [target_field])) == cold_legacy_usec, "cold legacy end is immediately readable")
	_check(int(_call(diagnostics_script, &"performance_counter", [StringName(str(fields[1]))])) == cold_id_usec, "cold ID end is immediately readable")
	var cold_snapshot: Dictionary = _call(diagnostics_script, &"performance_counters")
	_check(int(cold_snapshot.get(str(target_field), -1)) == 0, "first snapshot clears cold legacy value")
	_check(int(cold_snapshot.get(str(fields[1]), -1)) == 0, "first snapshot clears cold ID value")
	_call(diagnostics_script, &"reset_performance_window")
	for raw_field: Variant in fields:
		var field: StringName = StringName(str(raw_field))
		var field_id: int = int(_call(diagnostics_script, &"counter_id", [field]))
		_call(diagnostics_script, &"increment_performance_counter_id", [field_id, 2])
		_call(diagnostics_script, &"increment_performance_counter", [field, 3])
		_call(diagnostics_script, &"increment_performance_counter_id", [field_id, -1])
		_call(diagnostics_script, &"increment_performance_counter_id", [field_id, 0])
		_check(int(_call(diagnostics_script, &"performance_counter", [field])) == 4, "id and legacy increments share backend for %s" % field)
	_call(diagnostics_script, &"increment_performance_counter", [StringName("unknown_fixed_backend_field"), 7])
	_call(diagnostics_script, &"increment_performance_counter_id", [-1, 100])
	_call(diagnostics_script, &"increment_performance_counter_id", [fields.size(), 100])
	_call(diagnostics_script, &"set_performance_value", [target_field, 2.5])
	_call(diagnostics_script, &"record_performance_max", [target_field, 3.5])
	_call(diagnostics_script, &"record_performance_max", [target_field, 4.5])
	var fixed_snapshot: Dictionary = _call(diagnostics_script, &"performance_counters")
	var packed_values: Variant = diagnostics_script.get("_performance_counter_values")
	_check(packed_values is PackedInt64Array, "fixed backend storage is PackedInt64Array")
	_check((packed_values as PackedInt64Array).size() == fields.size(), "packed backend covers every fixed field")
	for raw_field: Variant in fields:
		var packed_field: StringName = StringName(str(raw_field))
		var packed_id: int = int(_call(diagnostics_script, &"counter_id", [packed_field]))
		_check(int((packed_values as PackedInt64Array)[packed_id]) == 4, "packed backend value matches shared counter for %s" % packed_field)
	_check(int(_call(diagnostics_script, &"performance_counter", [target_field])) == 4, "value/max overlays retain integer counter read")
	_check(is_equal_approx(float(fixed_snapshot.get(str(target_field), -1.0)), 4.5), "max overlays value for same fixed field")
	var fixed_keys: Array = fixed_snapshot.keys()
	for index: int in range(fields.size()):
		_check(str(fixed_keys[index]) == str(fields[index]), "fixed snapshot key order remains canonical at %d" % index)
	_check(not fixed_snapshot.has("unknown_fixed_backend_field"), "unknown legacy field is not added to fixed snapshot")
	_check(int(_call(diagnostics_script, &"performance_counter", [StringName("unknown_fixed_backend_field")])) == 7, "unknown legacy field remains dynamically readable")

	var call_id: int = int(_call(diagnostics_script, &"counter_id", [StringName(str(fields[1]))]))
	var duration_id: int = int(_call(diagnostics_script, &"counter_id", [StringName(str(fields[2]))]))
	var call_before: int = int(_call(diagnostics_script, &"performance_counter", [StringName(str(fields[1]))]))
	var duration_before: int = int(_call(diagnostics_script, &"performance_counter", [StringName(str(fields[2]))]))
	var begin_usec: int = int(_call(diagnostics_script, &"begin_timed_segment_id", [call_id]))
	_check(begin_usec > 0, "fixed-id timing begin returns timestamp in full mode")
	var synthetic_start: int = Time.get_ticks_usec() - 5000
	var elapsed_usec: int = int(_call(diagnostics_script, &"end_timed_segment_id", [duration_id, synthetic_start]))
	_check(elapsed_usec > 0, "fixed-id timing end returns positive elapsed range")
	var timed_snapshot: Dictionary = _call(diagnostics_script, &"performance_counters")
	_check(int(timed_snapshot.get(str(fields[1]), 0)) == call_before + 1, "timing begin increments call counter exactly once")
	_check(int(timed_snapshot.get(str(fields[2]), 0)) == duration_before + elapsed_usec, "timing end delta equals returned duration")
	var legacy_call_before: int = int(_call(diagnostics_script, &"performance_counter", [StringName(str(fields[1]))]))
	var legacy_duration_before: int = int(_call(diagnostics_script, &"performance_counter", [StringName(str(fields[2]))]))
	var legacy_begin_usec: int = int(_call(diagnostics_script, &"begin_timed_segment", [StringName(str(fields[1]))]))
	var legacy_elapsed_usec: int = int(_call(diagnostics_script, &"end_timed_segment", [StringName(str(fields[2])), Time.get_ticks_usec() - 5000]))
	var mixed_snapshot: Dictionary = _call(diagnostics_script, &"performance_counters")
	_check(legacy_begin_usec > 0, "legacy timing begin returns timestamp")
	_check(legacy_elapsed_usec > 0, "legacy timing duration returns positive elapsed")
	_check(int(mixed_snapshot.get(str(fields[1]), 0)) == legacy_call_before + 1, "legacy begin shares fixed array with ID begin")
	_check(int(mixed_snapshot.get(str(fields[2]), 0)) == legacy_duration_before + legacy_elapsed_usec, "legacy timing duration shares fixed array with ID end")
	var slow_events: Variant = diagnostics_script.get("_recent_slow_events")
	_check(slow_events is Array and (slow_events as Array).size() >= 1, "timing slow-event entry remains observable")

	_call(diagnostics_script, &"set_device_lab_detail_mode", ["frame_only"])
	var before_frame_only: int = int(_call(diagnostics_script, &"performance_counter", [target_field]))
	_call(diagnostics_script, &"increment_performance_counter_id", [target_id, 10])
	var frame_only_begin: int = int(_call(diagnostics_script, &"begin_timed_segment_id", [call_id]))
	var frame_only_end: int = int(_call(diagnostics_script, &"end_timed_segment_id", [duration_id, 123]))
	_check(int(_call(diagnostics_script, &"performance_counter", [target_field])) == before_frame_only, "frame_only suppresses fixed counter writes")
	_check(frame_only_begin == 0, "frame_only suppresses fixed timing start")
	_check(frame_only_end == 0, "frame_only suppresses fixed timing end")
	_call(diagnostics_script, &"set_device_lab_detail_mode", ["full"])
	_call(diagnostics_script, &"set_device_lab_performance_enabled", [false])
	var before_disabled: int = int(_call(diagnostics_script, &"performance_counter", [target_field]))
	_call(diagnostics_script, &"increment_performance_counter_id", [target_id, 10])
	var disabled_end: int = int(_call(diagnostics_script, &"end_timed_segment_id", [duration_id, 123]))
	_check(int(_call(diagnostics_script, &"performance_counter", [target_field])) == before_disabled, "disabled override suppresses fixed counter writes")
	_check(not bool(_call(diagnostics_script, &"performance_detail_enabled")), "disabled override disables detail")
	_check(disabled_end == 0, "disabled override suppresses fixed timing end")
	_call(diagnostics_script, &"reset_performance_window")
	var reset_snapshot: Dictionary = _call(diagnostics_script, &"performance_counters")
	_check(int(reset_snapshot.get(str(target_field), -1)) == 0, "reset clears fixed counter values")
	_check((diagnostics_script.get("_recent_slow_events") as Array).size() == 0, "reset clears slow-event entries")
	var window: Dictionary = _call(diagnostics_script, &"read_performance_window", [{"contract": "fixed_counter_backend"}])
	_check(window.has("counters") and window.has("schema") and window.has("window_id"), "window snapshot retains schema and counters")

	if _failures == 0:
		print(PASS_MARKER)
		get_tree().quit(0)
	else:
		print("HC_TEST_FAIL: %d fixed counter backend checks failed" % _failures)
		get_tree().quit(1)
