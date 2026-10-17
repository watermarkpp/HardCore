extends Node
## Real Host, real S, real ordinary prefix and physical Main Label. The only
## normal closing progress event is the held prefix's actual ACK. No closing
## producer, timer, resource result or unrelated input can wake the Source.
const Source := preload("res://tests/framework/helpers/close_prefix_ack_source_20261018.gd")
const Consumer := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _consumer: RefCounted
var _held: Dictionary={}
var _label: Label
var _writes := 0
var _requested := false
var _ack_usec := 0
var _cleanup_wake := false
var _deadline := 0
var _generation := 115181
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed+=1
func _ready() -> void:
	_label=Label.new();add_child(_label)
	_host=ClassDB.instantiate("HardCoreSimulationHost")
	_consumer=Consumer.new(_host,self)
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":1,"runtime_map_id":913203,"profile_id":"actual_prefix_close_wake"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,"bridge_generation":_generation,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start_clock_fixture(Source,{"world_identity":world},config),"real Native Source/ordinary mailbox starts")
	_deadline=Time.get_ticks_usec()+5000000
func _process(_delta: float) -> void:
	if _host==null: return
	if _held.is_empty() and _ack_usec==0:
		var packet: Dictionary=_host.inspect_next_original_published_prefix()
		if packet.get("status")=="READY": _held=packet.prefix
	var presentation: Dictionary=_host.acquire_presentation(0,16)
	if not presentation.is_empty():
		_host.ack_events(int(presentation.through_ordinal))
		if not _requested and presentation.frame.get("ready_for_close_without_ACK")==true and not _held.is_empty():
			_host.request_close();_requested=true
	var state: Dictionary=_host.status()
	if _requested and _ack_usec==0 and state.get("close_attempts",0)>=1:
		check(state.get("source_model_close_completed")==false and state.get("unsettled_original_published_prefixes")==1,"Source really entered close retaining one unacknowledged original prefix")
		var applied: Dictionary=_consumer.apply_prefix(_held)
		check(applied.get("status")=="APPLIED" and _writes==1,"actual physical Main write precedes Native ACK")
		var ack := {"bridge_generation":_generation,"journal_generation":_generation,"through_ordinal":1,"applied":true}
		check(_host.ack_published_original_main_prefix(_held,ack),"exact accepted ordinary prefix ACK")
		check(_consumer.confirm_prefix_acknowledged(_held,ack),"original Main cursor confirms the same real ACK")
		_ack_usec=Time.get_ticks_usec();_held={}
	if _ack_usec>0 and not state.get("join_complete",false) and Time.get_ticks_usec()-_ack_usec>500000 and not _cleanup_wake:
		check(false,"actual final prefix ACK alone must wake Source to consume receipt and close; no unrelated wake")
		print("ACTUAL_CLOSE_ACK_WAKE_RED ",JSON.stringify(_host.status()))
		_cleanup_wake=true
		# Failure is already recorded and cannot turn PASS. One explicit teardown
		# close request wakes the retained Host so the RED exits without leaks.
		_host.request_close()
	if _requested and _host.status().get("join_complete")==true:
		check(_host.close_and_join(),"real Source closes and joins after original prefix retirement")
		check(_writes==1 and _label.text=="written-before-real-ACK","physical event never replays across close")
		check(_host.status().get("unsettled_original_published_prefixes")==0,"actual original prefix debt reaches zero")
		print("ACTUAL_CLOSE_ACK_WAKE_RESULT ",JSON.stringify({"cleanup_wake_required":_cleanup_wake,"ACK_to_join_usec":Time.get_ticks_usec()-_ack_usec,"status":_host.status()}))
		_host=null;_finish()
	elif Time.get_ticks_usec()>_deadline:
		check(false,"real close wake component deadline; retained accepted owners")
		_deadline=Time.get_ticks_usec()+5000000
func apply_original_main_journal_event(event: Dictionary) -> bool:
	if event.get("operation")!=&"close_wake_actual_label" or event.get("ordinal")!=1 or _consumer.actual_current_original_event()!=event: return false
	_label.text=str(event.arguments[0]);_writes+=1
	return true
func _finish() -> void:
	var written: bool=_proof.write_receipt("close_prefix_ack_wake_20261018",_proof.records.size(),_failed)
	print("CLOSE_PREFIX_ACK_WAKE_20261018_","PASS" if written and _failed==0 else "FAIL")
	get_tree().quit(0 if written and _failed==0 else 1)
