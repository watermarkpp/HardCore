extends Node
const Core := preload("res://tests/framework/helpers/journal_overlap_source_20261017.gd")
const Consumer := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
var _host: Object
var _consumer: RefCounted
var _held: Dictionary={}
var _label := Label.new()
var _last_tick := 0
var _deadline := 0
var _pending_once := false
var _close_requested := false
var _writes := 0
var _acks: Array[int]=[]
var _source_saw_first := false
var _generation := 115171
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed+=1
func _ready() -> void:
	add_child(_label)
	_host=ClassDB.instantiate("HardCoreSimulationHost")
	check(_host.has_method("inspect_next_original_published_prefix"),"actual Native can discover ordinary Source publication without caster event")
	if _failed>0:
		_host=null
		_finish()
		return
	check(_host.inspect_next_original_published_prefix().get("status")=="PENDING","pre-start Main delivery pump is nonfaulting and does not manufacture a prefix")
	_consumer=Consumer.new(_host,self)
	var world: Dictionary={"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":1,"runtime_map_id":913203,"profile_id":"published_prefix_fixture"}
	var config: Dictionary={"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,"bridge_generation":_generation,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	check(_host.start_clock_fixture(Core,{"world_identity":world},config),"actual Native Source publishes on its sole journal")
	_deadline=Time.get_ticks_usec()+5000000
func _process(_delta: float) -> void:
	if _host==null: return
	if _held.is_empty() and (_acks.is_empty() or _source_saw_first):
		var packet: Dictionary=_host.inspect_next_original_published_prefix()
		if packet.get("status")=="READY":
			check(packet.get("prefix") is Dictionary,"actual registered prefix returned")
			_held=packet.prefix
		elif packet.get("status") not in ["PENDING","BUSY"]:
			check(false,"unexpected Native discovery error")
	if not _held.is_empty():
		var applied: Dictionary=_consumer.apply_prefix(_held)
		if applied.get("status")=="PENDING":
			check(_consumer.has_pending(),"actual pending event retains unique prefix consumer cursor")
			check(_host.inspect_next_original_published_prefix().get("status")=="BUSY","Main-held partial prefix blocks second discovery")
		elif applied.get("status")=="APPLIED":
			var ack: Dictionary={"bridge_generation":_generation,"journal_generation":_generation,"through_ordinal":int(_held.through_ordinal),"applied":true}
			check(_host.ack_published_original_main_prefix(_held,ack),"actual Main effects acknowledged on original mailbox")
			check(_consumer.confirm_prefix_acknowledged(_held,ack),"same production consumer releases original prefix cursor")
			_acks.append(int(_held.through_ordinal))
			_held={}
		elif applied.get("status")!="BUSY": check(false,"actual Main prefix application rejected")
	var presentation: Dictionary=_host.acquire_presentation(_last_tick+1,16)
	if not presentation.is_empty():
		_last_tick=int(presentation.tick)
		_host.ack_events(int(presentation.through_ordinal))
		if presentation.frame.get("first_ack_consumed")==true: _source_saw_first=true
		if presentation.frame.get("ready_to_close")==true and not _close_requested:
			check(presentation.frame.source_valid,"Source journal consumed exact overlapping actual Main ACKs")
			for result: Dictionary in presentation.frame.get("checks",[]): check(result.pass,result.label)
			_close_requested=true
			_host.request_close()
	if _close_requested and _host.status().join_complete:
		check(_host.close_and_join(),"Source publication obligations permit genuine close")
		check(_acks==[1,2],"two genuinely overlapping journal prefixes are consumed in original order")
		check(_writes==2 and _label.text=="published-2","actual Label writes occur once per source event")
		check(_pending_once,"backpressure path actually executed")
		check(not _consumer.has_pending() and _held.is_empty(),"no retained Main prefix after final close")
		_host=null
		_finish()
	elif Time.get_ticks_usec()>_deadline:
		if not _close_requested:
			check(false,"actual Source prefix delivery deadline")
			_close_requested=true
			_host.request_close()
func apply_original_main_journal_event(event: Dictionary) -> Variant:
	check(event.operation==&"actual_delivery_label" and int(event.ordinal) in [1,2],"actual exact Source event in original Main consumer")
	check(_consumer.actual_current_original_event()==event,"same Native-claimed event reaches physical writer")
	if int(event.ordinal)==1 and not _pending_once:
		_pending_once=true
		return {"status":"PENDING"}
	_label.text=str(event.arguments[0])
	_writes+=1
	return true
func _finish() -> void:
	var written: bool=_proof.write_receipt("journal_overlap_native_20261017",_proof.records.size(),_failed)
	print("JOURNAL_OVERLAP_NATIVE_20261017_", "PASS" if written and _failed==0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed==0 else 1)
