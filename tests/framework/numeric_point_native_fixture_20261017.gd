extends Node
const Core := preload("res://tests/framework/helpers/numeric_point_source_core_20261017.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _host: Object
var _failures := 0
var _deadline := 0
var _last_tick := 0
var _closing := false
var _final: Dictionary = {}
func _check(value: bool, label: String) -> void:
	_proof.record(value,label)
	_failures += 0 if value else 1
func _ready() -> void:
	_check(ClassDB.class_exists("HardCoreSimulationHost") and ClassDB.class_exists("HardCoreSimulationWorld2D"),"actual fixed Native classes registered")
	_check(ProjectSettings.get_setting("physics/2d/external_owner_mode",false) == true,"runner supplied scoped external-owner override")
	if _failures != 0: _finish(); return
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var boot := {"area":{"gravity":ProjectSettings.get_setting("physics/2d/default_gravity"),"gravity_vector":ProjectSettings.get_setting("physics/2d/default_gravity_vector"),"linear_damp":ProjectSettings.get_setting("physics/2d/default_linear_damp"),"angular_damp":ProjectSettings.get_setting("physics/2d/default_angular_damp")}}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":215,
		"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,
		"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var started: bool = _host.start(Core,boot,config)
	_check(started,"real Host.start claims actual sole Source physics owner")
	if not started: _host = null; _finish(); return
	_deadline = Time.get_ticks_usec() + 25000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.acquire_presentation(_last_tick + 1,32)
	if not packet.is_empty():
		_last_tick = int(packet.tick)
		_host.ack_events(int(packet.through_ordinal))
		if packet.frame.get("done") == true and _final.is_empty():
			_final = packet.frame
			_host.request_close(); _closing = true
	if _closing and _host.status().join_complete:
		_check(_host.close_and_join(),"actual S world/RIDs/identities close before nonblocking Main final join")
		_check(_final.get("owner") != OS.get_main_thread_id(),"reference and numeric queries both ran on actual S")
		_check(_final.get("comparisons") == 9 and int(_final.get("empty_cases",0)) > 0 and int(_final.get("blocked_cases",0)) > 0,"all9actualqueries include both result branches")
		for row: Dictionary in _final.get("checks",[]): _check(row.get("pass") == true,str(row.get("label","missing source assertion")))
		_host = null; _finish()
	elif Time.get_ticks_usec() > _deadline:
		_check(false,"25s internal deadline, runner remains strict30s; accepted Host is not force-freed")
		print("NUMERIC_POINT_DEADLINE ",_host.status())
		_finish() # Runner owns process teardown; no unsafe close/free/join on Main.
func _finish() -> void:
	set_process(false)
	var written: bool = _proof.write_receipt("numeric_point_native_fixture_20261017",_proof.records.size(),_failures)
	print("NUMERIC_POINT_NATIVE_FIXTURE_", "PASS" if written and _failures == 0 else "FAIL")
	get_tree().quit(0 if written and _failures == 0 else 1)
