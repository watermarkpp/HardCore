extends "res://tests/framework/helpers/persistent_profile_process_source_20261015.gd"
## COMPONENT: genuine existing persistent Session/Profile/Feature scopes and
## Native closing SIGNAL/SERVICE producer. No World/renderer acceptance claim.
var _close_started := false
var _close_supported := false
var _close_reported := false
var _close_checks_start := 0
var _close_signals := 0
var _close_services := 0
var _released_waiters := 0
var _ordinary_signal_before := 0
var _buff_before := 0.0
var _frozen_clock: Dictionary = {}
func _await_actual_resource_signal() -> void:
	await _session.get("_profile").runtime.next_service()
	_released_waiters += 1
func _actual_persistent_receipts() -> bool:
	_profile.service_receipts()
	_close_services += 1
	return not _session.is_faulted()
func on_original_close_process_phase(frame: Dictionary) -> bool:
	if not _close_started or frame != _host.current_clock_frame(): return false
	if frame.get("source_boundary") == "PROCESS_SIGNAL": _close_signals += 1
	if _close_supported:
		return _session.service_original_close_session_obligations(frame,_actual_persistent_receipts)
	# RED-only physical cleanup after an already recorded missing-method FAIL.
	# These genuine methods drain the Native pair; this cannot make RED PASS.
	if frame.get("source_boundary") == "PROCESS_SIGNAL": return _session.service_original_close_process_signal_without_world(frame)
	return _actual_persistent_receipts()
func close_session() -> bool:
	if not _close_started:
		_close_started = true
		_close_checks_start = _checks.size()
		_close_supported = _session.has_method("service_original_close_session_obligations")
		_check(_close_supported,"real Session implements no-world persistent closing service, not a placeholder interface")
		_ordinary_signal_before = _signal_count
		_buff_before = float(_profile.temporary_item_buffs.isolated_process_probe.remaining)
		_frozen_clock = _host.current_clock_frame()
		if _close_supported: _await_actual_resource_signal()
	if _close_supported and _released_waiters == 0: return false
	if not _host.request_original_close_process_producer_stop(): return false
	if not _host.original_close_process_producer_drained(): return false
	if not _close_reported:
		_close_reported = true
		if _close_supported:
			_check(_released_waiters == 1 and _close_signals > 0 and _close_services > 0,"actual eligible Main SIGNAL resumes resource waiter once and SERVICE consumes real persistent receipts")
			_check(_signal_count == _ordinary_signal_before,"closing service never emits ordinary gameplay service_frame")
			_check(float(_profile.temporary_item_buffs.isolated_process_probe.remaining) == _buff_before,"closing service does not advance original buff/gameplay timers")
			_check(_budget.snapshot().open_scopes == 0 and _session.get("_feature").primitives.get("_site").is_empty(),"same persistent Feature resource scope is closed after every actual pair")
			var actual: Dictionary = _host.current_clock_frame()
			for key: String in ["epoch","h_ordinal","source_physics_frame","simulation_elapsed"]: _check(actual.get(key)==_frozen_clock.get(key),"closing persistent service preserves frozen Native "+key)
		var extra: Array[Dictionary] = []
		for index: int in range(_close_checks_start,_checks.size()): extra.append(_checks[index])
		_host.publish_snapshot({"done":true,"close_checks":extra},[])
	return super.close_session()
