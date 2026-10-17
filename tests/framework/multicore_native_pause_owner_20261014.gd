extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Core := preload("res://tests/framework/multicore_native_lifecycle_core_20261014.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")
var _proof := Proof.new()
var _failures := 0
var _host: Object
var _last_tick := 0
var _deadline_usec := 0

func _check(value: bool, label: String) -> void:
	_proof.record(value, label)
	if not value: _failures += 1

func _ready() -> void:
	var exists := ClassDB.class_exists("HardCoreSimulationWorld2D") and ClassDB.class_exists("HardCoreSimulationActorMotion2D")
	_check(exists, "compiled native world and source-shared controller are registered")
	if not exists:
		_finish()
		return
	# Exact production numeric publisher: no Shape2D crosses to S and the same
	# ProjectSettings defaults used by original World2D are captured on Main.
	var points := PackedVector2Array()
	for index: int in range(Spatial.ACTOR_FOOTPRINT_SEGMENTS):
		points.append(Spatial.actor_footprint_offset_px(index, 8.0))
	var boot := {"points": points, "area": {
		"gravity": ProjectSettings.get_setting("physics/2d/default_gravity"),
		"gravity_vector": ProjectSettings.get_setting("physics/2d/default_gravity_vector"),
		"linear_damp": ProjectSettings.get_setting("physics/2d/default_linear_damp"),
		"angular_damp": ProjectSettings.get_setting("physics/2d/default_angular_damp"),
	}}
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var started: bool = _host.call("start", Core, boot,
		{"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":32,"input_capacity":32,"event_capacity":32})
	_check(started, "production host claims the one external-owner physics server before world factory")
	if not started:
		_finish()
		return
	_deadline_usec = Time.get_ticks_usec() + 3000000

func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.call("acquire_presentation", _last_tick + 1, 32)
	if not packet.is_empty():
		_last_tick = int(packet.get("tick", 0))
		_host.call("ack_events", int(packet.get("through_ordinal", 0)))
		var frame: Dictionary = packet.get("frame", {})
		if frame.get("done", false):
			_check(frame.get("owner", 0) != OS.get_main_thread_id(), "live world and all motion execute on S")
			for record: Dictionary in frame.get("checks", []):
				_check(record.get("pass", false), record.get("label", "missing check label"))
			_finish()
	elif Time.get_ticks_usec() > _deadline_usec:
		_check(false, "native world completes real H/step/P tests and retirement within deadline")
		_finish()

func _finish() -> void:
	set_process(false)
	if _host != null:
		_check(_host.call("close_and_join"), "S world closes before host releases physics and Main joins")
		_host = null
	var okay: bool = _proof.write_receipt("multicore_native_pause_owner_20261014", _proof.records.size(), _failures)
	print("MULTICORE_NATIVE_PAUSE_OWNER_20261014_", "PASS" if okay and _failures == 0 else "FAIL")
	get_tree().quit(0 if okay and _failures == 0 else 1)
