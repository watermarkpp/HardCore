extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Core := preload("res://tests/framework/helpers/multicore_host_clock_core_20261014.gd")
var _proof := Proof.new()
var _failures := 0
var _host: Object
var _last_tick := 0
var _deadline_usec := 0

func _check(value: bool, label: String) -> void:
	_proof.record(value, label)
	if not value: _failures += 1

func _ready() -> void:
	var exists := ClassDB.class_exists("HardCoreSimulationHost")
	_check(exists, "native resident simulation host is compiled in the fixed engine")
	if not exists:
		_finish()
		return
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var started: bool = _host.call("start_clock_fixture", Core, {},
		{"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":128,"input_capacity":64,"event_capacity":64})
	_check(started, "clock fixture creates the sole model inside a Godot simulation thread")
	if not started:
		_finish()
		return
	_deadline_usec = Time.get_ticks_usec() + 2000000

func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.call("acquire_presentation", _last_tick + 1, 64)
	if not packet.is_empty():
		var frame: Dictionary = packet.get("frame", {})
		_last_tick = int(packet.get("tick", 0))
		_host.call("ack_events", int(packet.get("through_ordinal", 0)))
		if _last_tick >= 8:
			_check(int(frame.get("owner_thread", 0)) != OS.get_main_thread_id(), "phase and timer bodies execute away from display Main")
			_check(frame.get("h_p_pairs", 0) == _last_tick, "each serviced H has exactly its dependent P")
			_check(frame.get("phase_order_valid", false), "native clock preserves U H timer step P timer publish phase order")
			_check(frame.get("timeouts", []) == ["h", "p", "cross_p"], "H-created P continuation follows original shared timer-list cutoff")
			_check(frame.get("callback_owner_valid", false), "await-compatible timeout callbacks stay on sole S owner")
			_check(frame.get("simulation_elapsed", 0.0) > 0.0, "clock publishes accumulated H simulation time")
			_finish()
	elif Time.get_ticks_usec() > _deadline_usec:
		_check(false, "resident host publishes a complete frame within the fixture deadline")
		_finish()

func _finish() -> void:
	if _host != null:
		_check(_host.call("close_and_join"), "shutdown destroys S model/timers then joins before Main drops host")
		_host = null
	var okay: bool = _proof.write_receipt("multicore_host_clock_20261014", _proof.records.size(), _failures)
	print("MULTICORE_HOST_CLOCK_20261014_", "PASS" if okay and _failures == 0 else "FAIL")
	get_tree().quit(0 if okay and _failures == 0 else 1)
