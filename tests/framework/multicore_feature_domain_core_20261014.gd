extends RefCounted

const WorldCore := preload("res://scripts/gameplay/world/world_simulation_core.gd")
const Checks := preload("multicore_feature_domain_checks_20261014.gd")
var _core: RefCounted
var _checks: RefCounted
var _thread := OS.get_thread_caller_id()
func _init(host: Object, boot: Dictionary) -> void:
	_core = WorldCore.new(host,boot)
	assert(_core.has_method("feature_domain_test_fixture") and _core.has_method("update_feature_domain_test_snapshot"))
	_checks = Checks.new(_core.feature_domain_test_fixture())
func on_inputs(domain: String, packets: Array) -> bool: return _core.on_inputs(domain,packets)
func on_phase(name: String, frame: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == _thread)
	if name == "PUBLISH":
		if not _core.update_feature_domain_test_snapshot({"done":_checks.done,"owner":_thread,"checks":_checks.checks}): return false
		return _core.on_phase(name,frame)
	if not _core.on_phase(name,frame): return false
	_checks.after_phase(name,frame,_core.feature_domain_test_fixture())
	return true
func close_session() -> bool:
	_checks.close()
	_checks = null
	var closed: bool = _core.close_session()
	_core = null
	return closed
