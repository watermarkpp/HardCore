extends RefCounted
## Borrowed view of the SAME original rule/model authority. No state copy.
const Source := preload("res://scripts/gameplay/profile/profile_diagnostics_core.gd")
var _owner := OS.get_thread_caller_id()
var _target: WeakRef
var _settings: WeakRef
var _world: WeakRef
var _last_actual_main_frame := -1
func _init(target: RefCounted, settings: RefCounted) -> void:
	assert(_owner != OS.get_main_thread_id())
	assert(settings != null and settings.owner_thread_id() == _owner and settings.has_method("get_setting"))
	_target = weakref(target)
	_settings = weakref(settings)
	_world = settings.get("_world")
	assert(_world != null and _world.get_ref().owner_thread_id() == _owner)
func owner_thread_id() -> int: return _owner
func input_gate_enabled() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	var settings: RefCounted = _settings.get_ref()
	return bool(settings.get_setting("hardcore/debug/diagnostics/enabled",false)) and bool(settings.get_setting("hardcore/debug/diagnostics/input_gate",false))
func _get(field: StringName) -> Variant:
	var source_script: Script=Source
	var constants: Dictionary=source_script.get_script_constant_map()
	return constants[String(field)] if constants.has(String(field)) else _target.get_ref().get(field)
func _set(field: StringName, value: Variant) -> bool:
	_target.get_ref().set(field, value)
	return true

func configure_policy(policy: Dictionary, measurement_domain: String) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("configure_policy", [policy, measurement_domain])

func performance_enabled() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("performance_enabled", [])

func performance_detail_enabled() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("performance_detail_enabled", [])

func performance_timing_enabled() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("performance_timing_enabled", [])

func device_lab_detail_mode() -> String:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("device_lab_detail_mode", [])

func increment_performance_counter(field: StringName, amount := 1) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("increment_performance_counter", [field, amount])

func add_performance_value(field: StringName, amount: float) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("add_performance_value", [field, amount])

func set_performance_value(field: StringName, value: float) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("set_performance_value", [field, value])

func record_performance_max(field: StringName, value: float) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("record_performance_max", [field, value])

func record_frame_time_ms(frame_ms: float) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("record_frame_time_ms", [frame_ms])

func wall_frame_interval_ms() -> float:
	assert(OS.get_thread_caller_id() == _owner)
	# Source may consume only an actual Main measurement, once per Main frame.
	# Its own callback wall time remains simulation timing, never display FPS.
	var actual: Dictionary = _world.get_ref().input.actual_main_frame_observation()
	if actual.is_empty() or actual.main_process_frame <= _last_actual_main_frame: return -1.0
	_last_actual_main_frame = actual.main_process_frame
	return float(actual.interval_ms)

func reset_wall_frame_interval() -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if not _world.get_ref().emit_original_main_event(&"original_Main_frame_boundary_reset",[]): _world.get_ref().fault("actual_Main_frame_boundary_reset_not_published",{})

func wall_boundary_discard_count() -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("wall_boundary_discard_count", [])

func record_device_lab_frame_interval() -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("record_device_lab_frame_interval", [])

func reset_device_lab_frame_interval() -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("reset_device_lab_frame_interval", [])

func frame_sampling_snapshot() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("frame_sampling_snapshot", [])

func timing_start() -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("timing_start", [])

func timing_now() -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("timing_now", [])

func timing_elapsed_usec(started_usec: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("timing_elapsed_usec", [started_usec])

func record_timing_usec(field: StringName, started_usec: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("record_timing_usec", [field, started_usec])

func begin_timed_segment(call_field: StringName) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("begin_timed_segment", [call_field])

func end_timed_segment(duration_field: StringName, started_usec: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("end_timed_segment", [duration_field, started_usec])

func record_timing_ms(field: StringName, started_usec: int) -> float:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("record_timing_ms", [field, started_usec])

func performance_counter(field: StringName) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("performance_counter", [field])

func set_performance_release_context(release_id: String, skill_id: String) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("set_performance_release_context", [release_id, skill_id])

func mark_performance_release_context(release_id: String, skill_id: String) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("mark_performance_release_context", [release_id, skill_id])

func performance_release_context() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("performance_release_context", [])

func performance_counters() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("performance_counters", [])

func reset_performance_window() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("reset_performance_window", [])

func reset_window() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("reset_window", [])

func read_performance_window(context: Dictionary = {}) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("read_performance_window", [context])

func read_window(context: Dictionary = {}) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("read_window", [context])

func owner_window_snapshot(context: Dictionary = {}) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("owner_window_snapshot", [context])

var _combat_log: WeakRef
var _footprint_log: WeakRef
func configure_original_logs(combat_log: RefCounted, footprint_log: RefCounted) -> bool:
	if _combat_log != null or combat_log.owner_thread_id() != _owner or footprint_log.owner_thread_id() != _owner: return false
	for log_owner: RefCounted in [combat_log, footprint_log]:
		for method: String in ["capture_enabled", "record"]:
			if not log_owner.has_method(method): return false
	_combat_log = weakref(combat_log)
	_footprint_log = weakref(footprint_log)
	return true
func combat_capture_enabled() -> bool: return _combat_log.get_ref().capture_enabled()
func combat_record(raw_event: Dictionary) -> Dictionary: return _combat_log.get_ref().record(raw_event)
func footprint_capture_enabled() -> bool: return _footprint_log.get_ref().capture_enabled()
func footprint_record(raw_event: Dictionary) -> Dictionary: return _footprint_log.get_ref().record(raw_event)
