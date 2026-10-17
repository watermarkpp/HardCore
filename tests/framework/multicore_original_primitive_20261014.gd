extends Node

const Core := preload("res://tests/framework/helpers/multicore_original_primitive_core_20261014.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const PrefixConsumer := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
var _proof := Proof.new()
var _prefix_consumer: RefCounted
var _pending_packet: Dictionary = {}
var _normal_ack_done := false
var _host: Object
var _observer: Object
var _label := Label.new()
var _checks := 0
var _failures: Array[String] = []
var _packets: Array[Dictionary] = []
var _stage := "continuation"
var _requested_close := false
var _retried_close := false
var _last_tick := 0
var _generation := 41
var _deadline := 0
var _expected: Array = []
var _results: Array = []
var _applied_events: Dictionary = {}
var _source_prefix_writes := 0
var _withheld_first_event := false

func _check(value: bool, name: String) -> void:
	_checks += 1
	_proof.record(value, name)
	if not value:
		_failures.append(name)

func _ready() -> void:
	add_child(_label)
	seed(314159)
	_expected = [null,randi(),randf(),randi_range(-8,12),randf_range(-1.5,3.0),null,0]
	_observer = ClassDB.instantiate("HardCoreResourceObservation")
	_start("continuation")

func _start(mode: String) -> void:
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_prefix_consumer = PrefixConsumer.new(_host, self)
	_pending_packet = {}
	_normal_ack_done = false
	_requested_close = false
	_retried_close = false
	_last_tick = 0
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":1,"runtime_map_id":913203,"profile_id":"primitive_fixture"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,
		"bridge_generation":_generation,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),
		"primitive_request_capacity":65536,"primitive_result_capacity":65536,
		"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb", 32)) * 256}
	_check(_host.start_clock_fixture(Core,{"mode":mode,"world_identity":world},config),"actual_native_S_fixture_start_"+mode)
	_deadline = Time.get_ticks_usec()+5000000

func _process(_delta: float) -> void:
	if _host == null:
		return
	if _stage == "continuation":
		var packet: Dictionary = _pending_packet
		if packet.is_empty():
			packet = _host.acquire_pending_original_primitive()
			if not packet.is_empty():
				_packets.append(packet)
				_pending_packet = packet
		if not packet.is_empty():
			if not _requested_close:
				_host.request_close()
				_requested_close = true
				_check(not _host.close_and_join(),"Main_close_refuses_live_parked_S_without_waiting")
				_check(_host.status().original_primitive_in_flight,"accepted_original_stack_remains_after_close_request")
			if _apply_and_execute(packet):
				_pending_packet = {}
		var state: Dictionary = _host.status()
		if state.close_failed and not _retried_close:
			_check(state.running and not state.close_quiescent and not state.join_complete,"false_close_keeps_S_model_and_owner")
			_check(not _host.close_and_join(),"false_close_does_not_join_or_destroy")
			_retried_close = true
			_host.request_close()
		if state.join_complete:
			_check(_host.close_and_join(),"Main_final_close_only_after_async_S_join")
			_check(_results == _expected,"actual_Main_global_RNG_and_native_status_results_resume_S")
			_check(_packets.size()==7 and int(state.original_operation_sequence)==7,"resource_and_world_share_one_true_operation_prefix")
			_check(int(state.original_deadline_failures)==7,"all_real_late_continuations_remain_FAIL")
			_check(_retried_close,"explicit_false_close_retry_was_required")
			_check(_source_prefix_writes==1,"normal_and_primitive_overlap_never_double_applies_actual_Label")
			_observer.retire_generation(_generation)
			_host = null
			_stage = "counters"
			_generation += 1
			_start("counters")
	else:
		var presentation: Dictionary = _host.acquire_presentation(_last_tick+1,16)
		if not presentation.is_empty():
			_last_tick = int(presentation.tick)
			var frame: Dictionary = presentation.frame
			_check(frame.frames_valid,"actual_source_frame_increment_sites")
			_check(int(frame.source_physics_frame)==int(frame.physics_seed)+int(frame.publishes),"H_ordinal_is_not_source_physics_frame")
			_check(int(frame.source_process_frame)==int(frame.process_seed)+int(frame.publishes)-1,"process_count_increments_after_PUBLISH_callback")
			_host.ack_events(int(presentation.through_ordinal))
			if _last_tick>=3 and not _requested_close:
				_requested_close = true
				_host.request_close()
		if _requested_close and _host.status().join_complete:
			_check(_host.close_and_join(),"counter_fixture_quiescent_join")
			_host = null
			_finish()
	if _host != null and Time.get_ticks_usec()>_deadline:
		_check(false,"native_continuation_fixture_deadline")
		# This fixture must retain the Host and pump any accepted packet. Root
		# must not force free a stalled owner just to make a test exit green.
		_host.request_close()

func _apply_and_execute(packet: Dictionary) -> bool:
	var request: Dictionary = packet.request
	var prefix: Dictionary = packet.main_prefix
	if int(packet.identity.op_sequence)==1 and not _normal_ack_done:
		if not _apply_source_prefix(prefix): return false
		var normal_ack := {"bridge_generation":_generation,"journal_generation":int(prefix.journal_generation),"through_ordinal":int(prefix.through_ordinal),"applied":true}
		_check(_host.ack_published_original_main_prefix(prefix,normal_ack),"normal_exact_producer_actual_apply_ack")
		_check(_prefix_consumer.confirm_prefix_acknowledged(prefix),"normal_production_consumer_releases_actual_ACK")
		_normal_ack_done = true
		_check(int(_host.status().original_main_applied_prefix)==0,"normal_Main_ack_does_not_mutate_S_applied_ledger")
	if not _apply_source_prefix(prefix): return false
	_check(_label.text=="prefix-before-seed","prefix_consumer_actually_applied_before_primitive")
	var ack := {"bridge_generation":_generation,"journal_generation":int(prefix.journal_generation),
		"through_ordinal":int(prefix.through_ordinal),"applied":true,"main_prefix":prefix}
	_check(_host.ack_original_main_prefix(packet.identity,ack),"exact_applied_Main_prefix_ack")
	_check(_prefix_consumer.confirm_prefix_acknowledged(prefix),"cold_production_consumer_releases_actual_ACK")
	_execute_original(packet)
	return true

func _apply_source_prefix(prefix: Dictionary) -> bool:
	var applied: Dictionary = _prefix_consumer.apply_prefix(prefix)
	if applied.status == "BUSY": return false
	if applied.status == "PENDING":
		_check(_prefix_consumer.has_pending(),"pending actual prefix remains claimed")
		_check(_prefix_consumer.actual_current_original_event()==prefix.events[0],"pending exact original event cursor is retained")
		_check(_source_prefix_writes==0,"pending effect performs no Label write or cursor advance")
		return false
	_check(applied.status == "APPLIED", "production_shared_prefix_consumer_applied")
	for event: Dictionary in prefix.events:
		_check(_applied_events.get(int(event.ordinal))==event,"already_applied_source_ordinal_retains_exact_event_identity")
	return applied.status == "APPLIED"

func apply_original_main_journal_event(event: Dictionary) -> Variant:
	_check(event.operation==&"fixture_label" and event.ordinal==1,"exact_original_Main_prefix_event")
	if event.operation != &"fixture_label" or event.ordinal != 1: return false
	_check(_prefix_consumer.actual_current_original_event()==event,"dispatcher observes same actual Native event")
	if not _withheld_first_event:
		_withheld_first_event=true
		return {"status":"PENDING"}
	_label.text = str(event.arguments[0])
	_applied_events[int(event.ordinal)] = event.duplicate(true)
	_source_prefix_writes += 1
	return true

func _execute_original(packet: Dictionary) -> void:
	var request: Dictionary = packet.request
	var kind := &"original_resource_primitive" if packet.channel=="resource" else &"original_world_primitive"
	var changed := request.duplicate(true)
	changed.site.call_ordinal += 1
	_check(not _host.validate_original_primitive_ticket(changed,kind),"mutated_Main_packet_cannot_change_original_frozen_source")
	_check(_host.validate_original_primitive_ticket(request,kind),"actual_ticket_after_prefix_apply")
	_check(not _host.validate_original_primitive_ticket(request,kind),"duplicate_original_execution_rejected")
	var started := Time.get_ticks_usec()
	var result: Variant
	var native_observation: Dictionary = {}
	var args: Array = request.arguments
	match StringName(request.operation):
		&"global_seed": seed(int(args[0]))
		&"global_randomize": randomize()
		&"global_randi": result=randi()
		&"global_randf": result=randf()
		&"global_randi_range": result=randi_range(int(args[0]),int(args[1]))
		&"global_randf_range": result=randf_range(float(args[0]),float(args[1]))
		&"status":
			var observed: Dictionary = _observer.threaded_status(str(args[0]),int(request.site.observation_process_epoch),_generation)
			_check(observed.ok and observed.observation_process_epoch==request.site.observation_process_epoch,"actual_narrow_status_source_epoch")
			result=int(observed.status)
			native_observation = observed
		_:
			_check(false,"unknown_actual_fixture_primitive")
	var finished := Time.get_ticks_usec()
	_results.append(result)
	var reply := {"request":request,"executed":true,"disposition":&"executed_late","result":result,
		"started_usec":started,"finished_usec":finished,"completed_prefix_ordinal":1}
	if packet.channel=="resource":
		reply["native_observation"] = native_observation
	_check(_host.submit_original_primitive_result(packet.identity,reply),"actual_result_submission")

func _finish() -> void:
	var receipt := {"scope":"actual_Godot_native_original_stack_shared_sequence_prefix_close_source_frames",
		"checks":_checks,"failures":_failures,"packet_count":_packets.size()}
	print("ORIGINAL_PRIMITIVE_NATIVE_RECEIPT "+JSON.stringify(receipt))
	var written: bool = _proof.write_receipt("multicore_original_primitive_20261014", _checks, _failures.size())
	print("MULTICORE_ORIGINAL_PRIMITIVE_", "PASS" if written and _failures.is_empty() else "FAIL")
	get_tree().quit(0 if written and _failures.is_empty() else 1)
