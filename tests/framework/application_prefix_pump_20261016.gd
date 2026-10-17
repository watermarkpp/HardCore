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
var _pump: RefCounted
var _feature: RefCounted
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	_pump = preload("res://scripts/gameplay/source/main_original_resource_pump.gd").new()
	check(_pump.has_method("service_original_main_publications"),"production Main resource pump also owns genuine ordinary-prefix execution")
	if _failed != 0: _finish(); return
	_label = Label.new(); add_child(_label)
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_consumer = Consumer.new(_host,self)
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"isolated.prefix.protocol.component"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115159,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	_feature = preload("res://scripts/features/runtime/feature_resource_main_primitives.gd").new()
	check(_feature.configure_main(ContentLayers._feature_resources(),ClassDB.instantiate("HardCoreResourceObservation"),Callable(_host,"validate_original_primitive_ticket"),_unexpected_resource,_unexpected_resource,config.bridge_generation),"same actual Main Feature vault is configured without running a resource body in this ordinary-publication probe")
	check(_pump.configure_main(_host,_consumer,_feature,config.bridge_generation),"one Main pump owns the same prefix consumer and bridge")
	check(_host.start(Source,{"world_identity":world},config),"actual Native Source starts for the isolated prefix protocol component")
	_deadline = Time.get_ticks_usec()+20000000
func apply_original_main_journal_event(event: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _consumer.actual_current_original_event()!=event or event.get("kind")!="component_visible_label" or not event.get("text") is String or event.get("source_thread")==OS.get_main_thread_id(): return false
	_label.text = event.text; _writes += 1
	return _label.text == "actual Source journal delivered"
func _unexpected_resource(_a: Variant = null,_b: Variant = null,_c: Variant = null,_d: Variant = null) -> Dictionary:
	check(false,"ordinary prefix must not execute an invented Feature resource body")
	return {}
func _process(_delta: float) -> void:
	if _host==null: return
	var served: Dictionary = _pump.service_original_main_publications()
	if served.get("status") not in ["PENDING","SERVICED"]:
		check(false,"actual production Main ordinary prefix service:"+str(served)); _host.request_close(); _closing = true
	var packet: Dictionary = _host.acquire_presentation(_tick+1,32)
	if not packet.is_empty():
		_tick = packet.tick; _host.ack_events(packet.through_ordinal)
		if packet.frame.get("done")==true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.pass,row.label)
			check(_writes==1 and _label.text=="actual Source journal delivered","physical Main Label changes exactly once despite Source publication replay")
			check(_pump.inspect_actual_original_pending_resources().get("published_completed")==1,"one actual Native ordinary prefix is executed and acknowledged by the production pump")
			_closing = true; _host.request_close()
	if _closing and _host.status().get("join_complete")==true:
		check(_host.close_and_join(),"actual Source and Native published FIFO quiesce before Main exit")
		_host = null; _finish()
	elif Time.get_ticks_usec()>_deadline:
		check(false,"bounded prefix protocol component completes"); _host.request_close(); _closing = true
func _finish() -> void:
	set_process(false)
	var scene_id: String = scene_file_path.get_file().get_basename()
	var written: bool = _proof.write_receipt(scene_id,_proof.records.size(),_failed)
	print(scene_id.to_upper()+"_","PASS" if written and _failed==0 else "FAIL")
	get_tree().quit(0 if written and _failed==0 else 1)
