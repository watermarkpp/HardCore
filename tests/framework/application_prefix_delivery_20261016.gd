extends Node
## Actual Source journal -> actual Native FIFO -> actual Main prefix consumer
## -> visible Label write -> Native ACK -> Source journal retirement.
const Source := preload("res://tests/framework/helpers/application_prefix_source_20261016.gd")
const Consumer := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _consumer: RefCounted
var _label: Label
var _writes := 0
var _tick := 0
var _closing := false
var _deadline := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	_label = Label.new(); add_child(_label)
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_consumer = Consumer.new(_host,self)
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"isolated.prefix.protocol.component"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115159,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start(Source,{"world_identity":world},config),"actual Native Source starts for the isolated prefix protocol component")
	_deadline = Time.get_ticks_usec()+20000000
func apply_original_main_journal_event(event: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _consumer.actual_current_original_event()!=event or event.get("kind")!="component_visible_label" or not event.get("text") is String or event.get("source_thread")==OS.get_main_thread_id(): return false
	_label.text = event.text; _writes += 1
	return _label.text == "actual Source journal delivered"
func _process(_delta: float) -> void:
	if _host==null: return
	var held: Dictionary = _host.inspect_next_original_published_prefix()
	if held.get("status")=="READY":
		var result: Dictionary = _consumer.apply_prefix(held.prefix)
		check(result.get("status")=="APPLIED","real Main consumer applies the actual Native FIFO prefix")
		if result.get("status")=="APPLIED":
			var ack := {"bridge_generation":held.prefix.bridge_generation,"journal_generation":held.prefix.journal_generation,"through_ordinal":held.prefix.through_ordinal,"applied":true}
			check(_host.ack_published_original_main_prefix(held.prefix,ack) and _consumer.confirm_prefix_acknowledged(held.prefix,ack),"actual applied Main write produces the exact Native ACK")
	var packet: Dictionary = _host.acquire_presentation(_tick+1,32)
	if not packet.is_empty():
		_tick = packet.tick; _host.ack_events(packet.through_ordinal)
		if packet.frame.get("done")==true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.pass,row.label)
			check(_writes==1 and _label.text=="actual Source journal delivered","physical Main Label changes exactly once despite Source publication replay")
			_closing = true; _host.request_close()
	if _closing and _host.status().get("join_complete")==true:
		check(_host.close_and_join(),"actual Source and Native published FIFO quiesce before Main exit")
		_host = null; _finish()
	elif Time.get_ticks_usec()>_deadline:
		check(false,"bounded prefix protocol component completes"); _host.request_close(); _closing = true
func _finish() -> void:
	set_process(false)
	var written: bool = _proof.write_receipt("application_prefix_delivery_20261016",_proof.records.size(),_failed)
	print("APPLICATION_PREFIX_DELIVERY_20261016_","PASS" if written and _failed==0 else "FAIL")
	get_tree().quit(0 if written and _failed==0 else 1)
