extends Node

const Core := preload("res://tests/framework/multicore_service_registry_core_20261014.gd")
const OriginalDriver := preload("res://scripts/map_editor/polygon/poly_pursuit_driver.gd")
const OriginalScheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
var _host: Object
var _tick := 0
var _deadline := 0
var _checks: Array[Dictionary] = []
var _failures := 0

func _check(value: bool, label: String) -> void:
	_checks.append({"pass": value, "label": label})
	if not value: _failures += 1

func _scope(node: Node, life: int) -> Dictionary:
	return {"runtime_present": is_instance_valid(node), "life_generation": life,
		"inside_world": node.is_inside_tree(), "queued_for_retirement": node.is_queued_for_deletion(),
		"parent_scope_id": node.get_parent().get_instance_id() if node.get_parent() != null else 0,
		"can_process": node.can_process(), "process_processing_enabled": node.is_processing(),
		"physics_processing_enabled": node.is_physics_processing(),
		"ordinary_p_enabled": false, "raw_h_enabled": false, "physics_priority": node.process_physics_priority}

func _driver_state(node: Node) -> Dictionary:
	return {"token": node.token, "pending": node.pending, "route": node.route.duplicate(),
		"route_index": node.route_index, "retry_msec": node.retry_msec}

func _ready() -> void:
	_check(ClassDB.class_exists("HardCoreSimulationHost"), "actual native S host is present")
	if not ClassDB.class_exists("HardCoreSimulationHost"):
		_finish()
		return
	var oracle: Node = OriginalDriver.new()
	add_child(oracle)
	oracle.token = 17
	oracle.pending = true
	oracle.route = PackedVector2Array([Vector2(1.25, 2.5), Vector2(-0.125, 9.5)])
	oracle.route_index = 1
	oracle.retry_msec = 997
	var before := _driver_state(oracle)
	var driver_scope := _scope(oracle, 1)
	remove_child(oracle)
	var after := _driver_state(oracle)
	oracle.free()
	var source_scheduler: Node = OriginalScheduler.for_tree(get_tree())
	var scheduler_scope := _scope(source_scheduler, 1)
	_check(source_scheduler.process_physics_priority == 100, "actual source for_tree assigns priority100 at creation")
	source_scheduler.free()
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_check(_host.has_method("start_clock_fixture"), "native isolated S clock fixture ABI is available")
	if not _host.has_method("start_clock_fixture"):
		_finish()
		return
	var started: bool = _host.call("start_clock_fixture", Core,
		{"driver_scope": driver_scope, "scheduler_scope": scheduler_scope, "driver_reset_before": before, "driver_reset_after": after},
		{"physics_hz": 60, "max_epochs_per_turn": 8, "timer_capacity": 32, "input_capacity": 32, "event_capacity": 32})
	_check(started, "registry and original staged models construct on real S owner")
	if not started:
		_finish()
		return
	_deadline = Time.get_ticks_usec() + 5000000

func _process(_delta: float) -> void:
	if _host == null: return
	if Time.get_ticks_usec() > _deadline:
		_check(false, "native service protocol completes in fixture deadline")
		_finish()
		return
	var packet: Dictionary = _host.call("acquire_presentation", _tick + 1, 32)
	if not packet.is_empty():
		_tick = packet.get("tick", 0)
		_host.call("ack_events", int(packet.get("through_ordinal", 0)))
		var frame: Dictionary = packet.get("frame", {})
		if frame.get("done", false):
			_check(frame.get("owner", 0) != OS.get_main_thread_id(), "sole S owner differs from Main")
			for record: Dictionary in frame.get("checks", []):
				_check(record.get("pass", false), record.get("label", "missing source assertion"))
			_finish()

func _finish() -> void:
	set_process(false)
	if _host != null:
		_check(_host.call("close_and_join"), "all S service Objects close before Main join")
		_host = null
	var result := {"status": "PASS" if _failures == 0 else "FAIL", "checks": _checks,
		"scope": "real native S service identity/lifecycle plus original kernel retire callbacks; production Scope/WorldCore integration NOT_RUN", "native_world": "NOT_RUN"}
	var file := FileAccess.open("user://multicore_service_registry_20261014.result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("SERVICE_REGISTRY_RESULT ", JSON.stringify(result))
	print("SERVICE_REGISTRY_", "PASS" if _failures == 0 else "FAIL")
	get_tree().quit(0 if _failures == 0 else 1)
