extends RefCounted

var _host: Object
var _owner: int
var _pairs := 0
var _phase_order_valid := true
var _callback_owner_valid := true
var _phases: Array[String] = []
var _timeouts: Array[String] = []
const ORDER := ["U_BEGIN","H_INPUT","H_PREPARE","H_GROUP","H_AFTER_TIMERS","H_STEP","P_INPUT","P_GROUP","P_AFTER_TIMERS","U_END","PUBLISH"]

func _init(host: Object, _boot: Dictionary) -> void:
	_host = host
	_owner = OS.get_thread_caller_id()
	var h_timer: RefCounted = _host.call("create_timer", 0.0, true, true, false)
	h_timer.timeout.connect(_on_h)
	var p_timer: RefCounted = _host.call("create_timer", 0.0, true, false, false)
	p_timer.timeout.connect(_on_timeout.bind("p"))

func _on_h() -> void:
	_on_timeout("h")
	var cross: RefCounted = _host.call("create_timer", 0.0, true, false, false)
	cross.timeout.connect(_on_timeout.bind("cross_p"))

func _on_timeout(name: String) -> void:
	_callback_owner_valid = _callback_owner_valid and OS.get_thread_caller_id() == _owner
	_timeouts.append(name)

func on_phase(name: String, frame: Dictionary) -> bool:
	if name == "U_WAKE": return true
	if name == "U_BEGIN": _phases.clear()
	_phases.append(name)
	if name == "P_AFTER_TIMERS": _pairs += 1
	if name == "PUBLISH":
		_phase_order_valid = _phase_order_valid and _phases == ORDER
		return _host.call("publish_snapshot", {"owner_thread":_owner,"h_p_pairs":_pairs,
			"phase_order_valid":_phase_order_valid,"timeouts":_timeouts,
			"callback_owner_valid":_callback_owner_valid,"simulation_elapsed":frame.simulation_elapsed}, [])
	return true

func on_inputs(_domain: String, _packets: Array) -> bool:
	return OS.get_thread_caller_id() == _owner

func close_session() -> bool:
	_host = null
	return OS.get_thread_caller_id() == _owner
