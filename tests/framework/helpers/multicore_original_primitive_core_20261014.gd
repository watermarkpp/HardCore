extends RefCounted

var _host: Object
var _boot: Dictionary
var _mode := ""
var _calls := 0
var _close_calls := 0
var _results: Array = []
var _stack_valid := true
var _frames_valid := true
var _publishes := 0
var _world: Dictionary
var _generation := 0
var _process_seed := 0
var _physics_seed := 0
var _source_site: Dictionary

func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_boot = boot
	_mode = boot.mode
	_world = boot.world_identity
	_generation = int(host.capabilities().bridge_generation)
	_process_seed = int(host.current_clock_frame().source_process_frame)
	_physics_seed = int(host.current_clock_frame().source_physics_frame)
	if _mode == "continuation":
		# Each native call parks this actual GDScript stack with local intact.
		var local := "original-stack-local-73"
		_results.append(_exchange(&"global_seed", [314159], false))
		_stack_valid = local == "original-stack-local-73"
		_results.append(_exchange(&"global_randi", [], false))
		_results.append(_exchange(&"global_randf", [], false))
		_results.append(_exchange(&"global_randi_range", [-8,12], false))
		_results.append(_exchange(&"global_randf_range", [-1.5,3.0], false))
		_results.append(_exchange(&"global_randomize", [], false))
		_results.append(_exchange(&"status", ["res://tests/framework/no_accepted_threaded_claim_for_primitive_fixture.png"], true))
		_stack_valid = _stack_valid and local == "original-stack-local-73"
		_stack_valid = _stack_valid and _host.finish_original_call_site(_source_site)

func _exchange(operation: StringName, arguments: Array, resource: bool) -> Variant:
	_calls += 1
	var sequence: int = _host.next_original_operation_sequence()
	var prefix := {"bridge_generation":_generation,"journal_generation":_generation,"through_ordinal":1,
		"events":[{"ordinal":1,"operation":&"fixture_label","arguments":["prefix-before-seed"]}] if sequence == 1 else []}
	assert(_host.stage_original_main_prefix(prefix))
	if sequence == 1:
		assert(_host.register_published_original_main_prefix(prefix))
		assert(_host.register_published_original_main_prefix(prefix))
	var frame: Dictionary = _host.current_clock_frame()
	var site := {"clock_epoch":int(frame.epoch),"domain":&"P","entry_id":"primitive_fixture_original_stack",
		"entry_ordinal":1,"bootstrap":int(frame.epoch)==0,"observation_process_epoch":int(frame.source_process_frame),
		"world_context":_world,"deadline_usec":1}
	_source_site = site.duplicate(true)
	site["call_ordinal"] = _host.next_original_call_ordinal(_source_site)
	_stack_valid = _stack_valid and int(site.call_ordinal)==_calls
	var identity := {"bridge_generation":_generation,"op_sequence":sequence}
	# A numeric transport fixture, not a gameplay FrameBudget replacement. The
	# production same-ledger guard and no-reentrancy require their own source run.
	var budget := {"identity":identity,"site":site,"ledger_epoch":-1,"logical_process_epoch":int(frame.source_process_frame),
		"scopes":[],"started_usec":Time.get_ticks_usec(),"spent_usec":0,"lane_spent":[0,0,0],"service_sequence":0,"pending_sequence":0}
	var request := {"protocol":"hardcore.streaming.primitives.v2" if resource else "hardcore.world.primitives.v1",
		"identity":identity,"site":site,"operation":operation,"arguments":arguments,"budget":budget,
		"predecessor_receipt":sequence-1,"output_slot":0,"main_prefix":_host.ordered_main_prefix(),"submitted_usec":Time.get_ticks_usec()}
	if not resource:
		request["world"] = _world
		request["source_site"] = site
	var reply: Dictionary = _host.exchange_original_primitive(request) if resource else _host.exchange_world_primitive(request)
	if reply.is_empty():
		print("COLD_ACTUAL_REJECTION ", {"request":request,"status":_host.status()})
		_stack_valid = false
		return null
	_stack_valid = _stack_valid and reply.request == request and reply.executed == true and reply.disposition == &"executed_late"
	_stack_valid = _stack_valid and _host.completed_original_operation_sequence() == sequence
	_stack_valid = _stack_valid and reply.native_main_prefix_receipt == {"bridge_generation":_generation,"journal_generation":_generation,"through_ordinal":1,"applied":true}
	_stack_valid = _stack_valid and _host.completed_original_main_prefix_receipt() == {"bridge_generation":_generation,"journal_generation":_generation,"through_ordinal":1,"applied":true}
	return reply.result

func on_inputs(_domain: String, _packets: Array) -> bool:
	return true

func on_phase(phase: String, frame: Dictionary) -> bool:
	if _mode != "counters":
		return true
	var elapsed: int = int(frame.epoch)-1
	var before_prepare := phase in ["U_BEGIN","H_INPUT","U_WAKE"]
	_frames_valid = _frames_valid and int(frame.source_physics_frame) == _physics_seed+elapsed+(0 if before_prepare else 1)
	_frames_valid = _frames_valid and int(frame.source_process_frame) == _process_seed+elapsed
	_frames_valid = _frames_valid and int(frame.next_release_usec) > int(frame.release_usec)
	if phase == "PUBLISH":
		_publishes += 1
		return _host.publish_snapshot({"frames_valid":_frames_valid,"publishes":_publishes,"h_ordinal":frame.h_ordinal,
			"source_process_frame":frame.source_process_frame,"source_physics_frame":frame.source_physics_frame,
			"process_seed":_process_seed,"physics_seed":_physics_seed}, [])
	return true

func close_session() -> bool:
	_close_calls += 1
	if _mode == "continuation" and _close_calls == 1:
		# Root Main must observe this retained owner and explicitly retry. It
		# must not spin, join, release physics/model, or report closed here.
		return false
	if _mode == "continuation":
		return _stack_valid and _results.size()==7 and _results[6]==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	return _frames_valid
