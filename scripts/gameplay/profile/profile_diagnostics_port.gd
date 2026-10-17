extends RefCounted
const Numeric := preload("res://scripts/gameplay/profile/profile_diagnostics_core.gd")
var _core: Numeric
var _owner_thread := OS.get_thread_caller_id()
func _init(policy: Dictionary) -> void:
	assert(OS.get_thread_caller_id() != OS.get_main_thread_id())
	_core = Numeric.new()
	_core.configure_policy(policy,"simulation")
func performance_detail_enabled() -> bool:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return _core.performance_detail_enabled()
func increment_performance_counter(category: StringName, amount := 1) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	_core.increment_performance_counter(category,amount)
func record_performance_max(category: StringName, value: float) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	_core.record_performance_max(category,value)
func apply_policy(policy: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if policy.get("contract_id") != "profile.diagnostics.policy.v1" or not policy.get("enabled") is bool or not policy.get("detail_enabled") is bool or policy.get("detail_mode") not in ["frame_only","full"]: return false
	if policy.detail_enabled and not policy.enabled: return false
	_core.configure_policy(policy,"simulation")
	return true
func numeric_owner() -> Numeric:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return _core
