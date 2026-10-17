extends Node
const Core := preload("res://tests/framework/helpers/multicore_closing_process_core_20261014.gd")
const Producer := preload("res://scripts/gameplay/source/main_close_process_frame_producer.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _host: Object
var _producer: RefCounted
var _checks := 0
var _failed := 0
var _deadline := 0
var _closing := false
var _reported := false
var _final: Dictionary = {}
class FatalReceipt extends RefCounted:
	var rejected: Array[Dictionary] = []
	func reject_original_main_profile_writer(fault: Dictionary) -> void: rejected.append(fault)
var _fatal := FatalReceipt.new()
func _check(value: bool, label: String) -> void:
	_checks+=1; _failed+=0 if value else 1; _proof.record(value,label)
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	# Main SceneTree must finish adding this scene before the independent
	# session listener is attached to its root. Use the genuine tree phase.
	await get_tree().process_frame
	get_tree().paused=true
	Engine.time_scale=0.5
	_host=ClassDB.instantiate("HardCoreSimulationHost")
	for method: String in ["bind_original_close_process_producer","enqueue_original_close_process_frame","original_close_process_signal_highwater","request_original_close_process_producer_stop","acquire_original_close_process_producer_stop_request","confirm_original_close_process_producer_stopped","verify_original_close_process_producer_terminal_receipt"]:
		_check(_host.has_method(method),"actual Native closing-P ABI "+method)
	if _failed>0:
		_host=null; _finish(); return
	var boot := {"actual_tree_paused":get_tree().paused,"actual_time_scale":Engine.time_scale,"settings":{
		"hardcore/performance/frame_optional_budget_usec":ProjectSettings.get_setting("hardcore/performance/frame_optional_budget_usec",1200),
		"hardcore/performance/frame_progress_budget_usec":ProjectSettings.get_setting("hardcore/performance/frame_progress_budget_usec",6000)},"area":{
		"gravity":ProjectSettings.get_setting("physics/2d/default_gravity"),"gravity_vector":ProjectSettings.get_setting("physics/2d/default_gravity_vector"),
		"linear_damp":ProjectSettings.get_setting("physics/2d/default_linear_damp"),"angular_damp":ProjectSettings.get_setting("physics/2d/default_angular_damp")}}
	var capacity := 4
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":capacity,"event_capacity":64,"bridge_generation":109,
		"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),
		"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var started: bool = _host.start(Core,boot,config)
	_check(started,"actual production Host.start creates S owner and original physics backend")
	if not started:
		_host=null
		_finish()
		return
	_producer=Producer.new()
	var bound: Dictionary = _producer.configure_main(_host,get_tree(),109,1,capacity,_fatal)
	_check(bound.get("success")==true,"fixed-path genuine Main producer and always listener bound by Native Script SHA")
	_deadline=Time.get_ticks_usec()+8000000
func _process(_delta: float) -> void:
	if _host==null: return
	var packet: Dictionary = _host.acquire_presentation(0,64)
	if not packet.is_empty():
		_host.ack_events(int(packet.through_ordinal))
		var frame: Dictionary = packet.frame
		if frame.get("ready")==true and not _closing:
			_check(_producer.arm_at_original_close_request(),"real producer arms before original asynchronous request_close")
			_host.request_close(); _closing=true
		if frame.get("done")==true: _final=frame
	if Time.get_ticks_usec()>_deadline and not _reported:
		_reported=true
		_check(false,"actual component deadline; accepted Host remains retained")
		print("CLOSING_PROCESS_DEADLINE ",_host.status(),_producer.capture_actual_closing_process_obligations())
	if _closing and _host.status().join_complete:
		_check(_host.close_and_join(),"Host closes only after genuine phases, actual STOP watermark and Main receipt ACKs")
		_check(not _final.is_empty(),"actual S completed phase report present")
		for row: Dictionary in _final.get("checks",[]): _check(bool(row.get("pass",false)),str(row.get("label","missing")))
		var obligations: Dictionary = _producer.capture_actual_closing_process_obligations()
		_check(_fatal.rejected.is_empty() and obligations.fault.is_empty(),"Main Native producer validation did not reject genuine callbacks")
		_check(obligations.capture_stopped and obligations.accepted.is_empty() and obligations.pending_service.is_empty(),"STOP stopped new capture and all actual accepted pair receipts drained")
		_check(_producer.finish_at_actual_Host_close(obligations.stop_receipt),"actual Native terminal watermark authorizes unique listener final free")
		_check(get_tree().root.get_node_or_null("HardCoreOriginalCloseProcessFrame")==null,"always listener retained until terminal proof then actually freed")
		_host=null; _finish()
func _finish() -> void:
	get_tree().paused=false; Engine.time_scale=1.0
	var written: bool = _proof.write_receipt("multicore_closing_process_frame_20261014",_checks,_failed)
	print("MULTICORE_CLOSING_PROCESS_FRAME_","PASS" if written and _failed==0 else "FAIL")
	get_tree().quit(0 if written and _failed==0 else 1)
