extends RefCounted
## Main's reliable transport owns only packets, receipts and detached views.
## Original Profile algorithms execute in source_profile_command_owner on S.
const ListenerScript := preload("res://scripts/gameplay/source/main_session_transport_listener.gd")
const Catalog := preload("res://scripts/gameplay/source/profile_original_command_catalog.gd")
const RuntimeScript := preload("res://scripts/gameplay/source/source_session_runtime.gd")
signal actual_main_progress
var _host: Object
var _tree: SceneTree
var _facade: Node
var _prefix: RefCounted
var _bootstrap: RefCounted
var _main_pump: RefCounted
var _io: RefCounted
var _fatal: RefCounted
var _listener: Node
var _state := "MAIN"
var _world: Dictionary = {}
var _prepared: Dictionary = {}
var _admission: RefCounted
var _session_id := 0
var _model_id := 0
var _pending: Dictionary = {}
var _acks: Dictionary = {}
var _ack_submitted: Dictionary = {}
var _results: Dictionary = {}
var _adopted: Dictionary = {}
var _notifications: Array[Dictionary] = []
var _hud: Array[Dictionary] = []
var _capacity := 0
var _input_sequence := 0
var _view_sequence := 0
var _close_authorized := false
var _terminal: Dictionary = {}
var _actual_terminal_intent := ""
var _actual_terminal_listener_retired := false
var _input_publisher: RefCounted

func finish_after_actual_prestart_abort() -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _state != "MAIN" or not _prepared.is_empty() or not _world.is_empty(): return false
	var state: Dictionary = _host.status()
	if state.get("main_channels_aborted") != true or state.get("started") != false or state.get("physics_handoff_prepared") != false: return false
	for held: Variant in [_pending,_acks,_ack_submitted,_results,_notifications,_hud,_feature_calls,_feature_acks,_feature_ack_submitted]:
		if not held.is_empty(): return false
	_state = "CLOSED"
	if is_instance_valid(_listener): _listener.free()
	_listener = null; _bootstrap = null; _main_pump = null; _prefix = null
	_io = null; _fatal = null; _admission = null; _input_publisher = null
	_host = null; _facade = null; _tree = null
	return true
const FeatureCalls := preload("res://scripts/gameplay/source/feature_original_command_catalog.gd")
const CommandDigest := preload("res://scripts/gameplay/source/source_command_digest.gd")
var _feature_calls: Dictionary = {}
var _feature_acks: Dictionary = {}
var _feature_ack_submitted: Dictionary = {}
var _feature_call_sequence := 0
func configure_main(host: Object, tree: SceneTree, facade: Node, prefix_consumer: RefCounted, bootstrap: RefCounted, main_pump: RefCounted, io: RefCounted, fatal: RefCounted, actual_capacity: int) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host!=null or tree==null or actual_capacity<=0: return _fail("actual_Main_once_capacity_required")
	if not is_instance_valid(facade) or facade!=tree.root.get_node_or_null("PlayerState"): return _fail("actual_PlayerState_required")
	for row: Array in [[host,["start","submit_input","status","request_close","close_and_join"]],[prefix_consumer,["actual_current_original_event"]],[bootstrap,["prepare_original_character_blueprint","publish_original_source_session_bootstrap"]],[main_pump,["service_actual_original_main_transport","actual_original_main_terminal_receipt"]],[io,["inspect_actual_original_main_warm_io"]],[fatal,["reject_original_main_profile_writer"]]]:
		for method: String in row[1]:
			if row[0]==null or not row[0].has_method(method): return _fail("MISSING:actual_Main_transport:"+method)
	_host=host;_tree=tree;_facade=facade;_prefix=prefix_consumer;_bootstrap=bootstrap;_main_pump=main_pump;_io=io;_fatal=fatal;_capacity=actual_capacity
	_listener=ListenerScript.new()
	if not _listener.configure_main(self): return _fail("actual_Main_listener_rejected")
	# Caller executes from an actual process-frame-safe Main creation boundary.
	# The constructor never uses deferred addition as a false admission barrier.
	_listener.name="HardCoreMainSessionTransport";tree.root.add_child(_listener)
	if not _listener.is_inside_tree(): return _fail("actual_Main_listener_not_inside_tree")
	return {"success":true,"listener":_listener}
func actual_original_profile_command_arities() -> Dictionary: return Catalog.ARITIES.duplicate(true)
func actual_original_character_world(receiver: Node) -> Dictionary:
	if _state!="MAIN" or receiver!=_tree.current_scene: return {}
	var actual: Dictionary=_bootstrap.prepare_original_character_blueprint(receiver)
	if actual.get("success")!=true or not actual.get("world") is Dictionary: return {}
	_world=actual.world
	return _world.duplicate(true)
func request_original_source_session_adoption(admission: RefCounted, prepared: Dictionary, world: Dictionary) -> Dictionary:
	if _state!="MAIN" or world!=_world or prepared.get("success")!=true or admission.get("_committed")!=false: return _fail("actual_epoch0_loaded_preparation_required")
	var built: Dictionary=_bootstrap.publish_original_source_session_bootstrap(admission,prepared,world)
	if built.get("success")!=true: return built
	if not built.get("boot") is Dictionary or not built.get("config") is Dictionary or built.get("prepared_receipt")!=prepared.get("receipt"): return _abort_actual_Path_before_Source_start(admission,prepared,"actual_same_loaded_bootstrap_required")
	# The exact production publisher just Native-captured this same immutable
	# graph. Do not traverse millions of values again in this routing layer.
	# Host.start still independently captures/validates the full receiving graph
	# BEFORE physics handoff or Source construction (simulation_host.cpp).
	var code: Script = _bootstrap.get_script()
	if code != null and code.resource_path == "res://scripts/gameplay/source/main_original_boot_publisher.gd":
		if not built.boot.is_read_only() or not is_same(_bootstrap.get("_boot"),built.boot): return _abort_actual_Path_before_Source_start(admission,prepared,"actual_retained_owned_boot_required")
	else:
		var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
		if graph.validate(built.boot,false).get("success")!=true: return _abort_actual_Path_before_Source_start(admission,prepared,"actual_plain_runtime_boot_required")
	_admission=admission;_prepared=prepared;_state="PREPARED"
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_NATIVE_HOST_START")
	if not _host.start(RuntimeScript,built.boot,built.config):
		return _abort_actual_Path_before_Source_start(admission,prepared,"actual_Host_start_rejected")
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"ACTUAL_NATIVE_HOST_STARTED")
	while _adopted.is_empty():
		var status: Dictionary=_host.status()
		if not str(status.get("fault","")).is_empty() or status.get("close_requested")==true:
			# Never allow Driver.abort to reenable Main while a started S owner
			# still exists. Failure recovery requires actual terminal IO proof.
			_host.request_close();_state="CLOSING"
			while _terminal.is_empty(): await actual_main_progress
			_state="FAILED"
			return _fail("actual_Source_start_fault_after_terminal",status)
		await actual_main_progress
	if admission.get("_committed")!=true or admission.get("_gate").state()!="S" or _adopted.prepared_receipt!=prepared.receipt: return _fail("actual_Main_commit_and_loaded_S_receipt_required")
	_state="S"
	return {"success":true,"prepared_receipt":prepared.receipt,"source_receipt":_adopted}
func _abort_actual_Path_before_Source_start(admission: RefCounted, prepared: Dictionary, reason: String) -> Dictionary:
	# Restore the captured actual Main callback only while Native confirms no
	# running Source and the original PREPARED owner proves abort eligibility.
	if _host.status().get("running")==true or not _bootstrap.has_method("abort_original_path_preparation") or not _bootstrap.abort_original_path_preparation(prepared.receipt):
		_state="FAILED";_admission=admission;_prepared=prepared
		return _fail("actual_Path_preparation_abort_failed",{"cause":reason})
	_state="MAIN";_admission=null;_prepared={}
	return _fail(reason)
func submit_original_profile_command(packet: Dictionary) -> Dictionary:
	if _state!="S" or _pending.size()>=_capacity or not Catalog.accepts(str(packet.get("method")),packet.get("arguments",[]).size()): return _fail("actual_Source_command_admission_unavailable")
	var id: int=int(packet.get("command_id",0))
	if id<=0 or _pending.has(id) or _results.has(id): return _fail("actual_unique_UI_command_required")
	_pending[id]={"packet":packet.duplicate(true),"submitted":false}
	# Rejected Native admission remains pending on Main; later serials cannot
	# bypass it. A real Source outcome is awaited, never an admission boolean.
	_flush_actual_input()
	while not _results.has(id):
		if _state=="FAILED": return _fail("actual_Source_command_fault")
		await actual_main_progress
	return _results[id]
func verify_original_profile_command_receipt(packet: Dictionary, received: Dictionary) -> bool:
	var id: int=int(packet.get("command_id",0))
	return _results.has(id) and _results[id]==received and received.get("owner_session_id")==_session_id and received.get("profile_model_id")==_model_id and received.get("command_sha256")==preload("res://scripts/gameplay/source/source_command_digest.gd").sha256(packet) and received.get("command_id")==id and received.get("profile_id")==packet.get("profile_id") and received.get("method")==packet.get("method")
func acknowledge_original_profile_command_receipt(received: Dictionary) -> bool:
	var id: int=int(received.get("command_id",0))
	if not _results.has(id) or _results[id]!=received: return false
	var ack: Dictionary={"contract_id":"hardcore.profile.ui.command_ack.v1","owner_session_id":_session_id,"command_id":id,"receipt_sha256":preload("res://scripts/gameplay/source/source_command_digest.gd").sha256(received)}
	_acks[id]=ack
	_flush_actual_input()
	return true # Receipt is retained until the actual Source ACK fact returns.
func request_original_profile_notification(what: int) -> bool:
	if _state not in ["S","DRAINING"] or _notifications.size()>=_capacity: return false
	_notifications.append({"contract_id":"hardcore.profile.notification.v1","owner_session_id":_session_id,"what":what})
	_flush_actual_input()
	return true
func submit_original_world_hud_event(world: Dictionary, name: StringName, args: Array, context: Dictionary, sequence: int) -> Dictionary:
	if world!=_world or sequence<=0 or _input_publisher==null: return {"status":"INVALID"}
	# Construction binds real views before Source adoption. Keep unaccepted
	# caller work; do not call it INVALID or fabricate Native acceptance.
	if _state in ["MAIN","PREPARED"]: return {"status":"BACKPRESSURE","reason":"actual_Source_adoption_pending"}
	if _state not in ["S","DRAINING"] or _host.status().get("close_requested") == true: return {"status":"INVALID"}
	if _hud.size()>=_capacity: return {"status":"BACKPRESSURE"}
	# Caller retains BACKPRESSURE; no artificial ACCEPTED result is produced.
	var actual: Dictionary=_input_publisher.capture_original_main_input(_input_sequence+1,name,args,context)
	if actual.get("success")!=true or not actual.get("publication") is Dictionary: return _fail("MISSING:actual_InputMap_and_button_publication",actual)
	_input_sequence+=1
	_hud.append(actual.publication)
	_flush_actual_input()
	return {"status":"ACCEPTED","sequence":sequence}
func original_world_hud_input_admission_current(world: Dictionary) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and _state == "S" and world == _world and _input_publisher != null and _host.status().get("close_requested") != true
func bind_actual_original_world_input(publisher: RefCounted,world: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host==null or _input_publisher!=null or _state not in ["MAIN","PREPARED"] or world!=_world: return false
	if publisher==null or publisher.get_script()!=preload("res://scripts/gameplay/source/main_original_world_input.gd") or publisher.get("_world")!=world or publisher.get("_last_sequence")!=0: return false
	_input_publisher=publisher
	return true
func can_commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _state not in ["PREPARED","S"] or _world != transaction.get("before_world") or _session_id != transaction.get("owner_session_id") or _input_publisher == null: return false
	var event: Dictionary = _prefix.actual_current_original_event()
	return event.get("operation") == &"source_map_arrival" and event.get("arguments") == [transaction] and _host.verify_committed_original_map_arrival(transaction) and _input_publisher.can_commit_actual_original_map_arrival(transaction)
func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_commit_actual_original_map_arrival(transaction) or not _input_publisher.commit_actual_original_map_arrival(transaction): return false
	_world = transaction.after_world.duplicate(true)
	# Already accepted packets retain their original world/sequence. Source's
	# input identity validator must consume or reject those exact packets.
	return true
func apply_original_transport_journal_event(event: Dictionary) -> bool:
	if _prefix.actual_current_original_event()!=event: return false
	if event.get("operation") in [&"original_feature_call_admitted",&"original_feature_call_result",&"original_feature_call_acknowledged"]: return _apply_actual_original_feature_call_event(event)
	var args: Variant=event.get("arguments")
	if not args is Array or args.size()!=1 or not args[0] is Dictionary: return false
	var receipt: Dictionary=args[0]
	match str(event.get("operation")):
		"original_profile_terminal_export":
			if not receipt.get("global_random_terminal") is Dictionary or receipt.global_random_terminal.is_empty(): return false
			if _actual_terminal_intent!="CHARACTER_SELECT" or _state!="CLOSING" or not _profile_terminal_export.is_empty() or receipt.get("contract_id")!="hardcore.profile.Source_terminal_export.v1" or receipt.get("owner_session_id")!=_session_id or receipt.get("source_profile_model_id")!=_model_id or receipt.get("bridge_generation")!=_host.capabilities().bridge_generation or receipt.get("actual_host_id")!=_host.get_instance_id() or not receipt.get("intent",{}).get("intent_event_ordinal") is int or receipt.intent.intent_event_ordinal<=0 or receipt.intent.intent_event_ordinal>=event.ordinal or receipt.get("world_context")!=_world or receipt.get("intent",{}).get("world_context")!=_world or receipt.get("intent",{}).get("owner_session_id")!=_session_id or receipt.get("intent",{}).get("profile_id")!=_world.get("profile_id"): return false
			var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
			var captured: Dictionary=graph.capture(receipt,true,false)
			if captured.get("success")!=true: return false
			_profile_terminal_export=captured.value
			_profile_terminal_event_identity={"bridge_generation":receipt.bridge_generation,"journal_event_ordinal":event.ordinal,"owner_session_id":_session_id}
		"original_profile_session_adopted":
			if _state!="PREPARED" or receipt.get("prepared_receipt")!=_prepared.get("receipt") or receipt.get("original_loaded_handoff_applied")!=true or int(receipt.get("owner_session_id",0))<=0 or int(receipt.get("profile_model_id",0))==0: return false
			_session_id=receipt.owner_session_id;_model_id=receipt.profile_model_id;_adopted=receipt
		"original_profile_command_receipt":
			var id: int=int(receipt.get("command_id",0))
			if not _pending.has(id) or not _pending[id].submitted or receipt.get("owner_session_id")!=_session_id or receipt.get("profile_model_id")!=_model_id or receipt.get("command_sha256")!=preload("res://scripts/gameplay/source/source_command_digest.gd").sha256(_pending[id].packet): return false
			if not receipt.get("profile_view") is Dictionary or int(receipt.profile_view.get("sequence",0))<=_view_sequence: return false
			if not _facade.get("_source_domain_gate").update_original_profile_view(receipt.profile_view.fields): return false
			_view_sequence=receipt.profile_view.sequence;_results[id]=receipt
		"original_profile_command_acknowledged":
			var id: int=int(receipt.get("command_id",0))
			if not _acks.has(id) or receipt.get("owner_session_id")!=_session_id or receipt.get("receipt_sha256")!=_acks[id].receipt_sha256: return false
			_pending.erase(id);_results.erase(id);_acks.erase(id);_ack_submitted.erase(id)
		"original_application_close_authorized":
			if receipt.get("owner_session_id")!=_session_id or receipt.get("original_logout_committed")!=true: return false
			_close_authorized=true
		_: return false
	return true
func request_original_application_close(what: Variant) -> Variant:
	if what is Dictionary:
		# The original S Root has already performed its logout algorithm. Main
		# accepts the currently executing journal event, then ACK can proceed.
		var event: Dictionary=_prefix.actual_current_original_event()
		if event.get("operation")!=&"original_tree_quit" or what!=_world: return false
		if not _actual_terminal_intent.is_empty() and _actual_terminal_intent != "QUIT": return false
		_actual_terminal_intent = "QUIT"
		_close_authorized=true;_begin_actual_close();return true
	if not what is int: return _fail("actual_original_close_request_required")
	if not request_original_profile_notification(what): return _fail("original_close_notification_not_admitted")
	_begin_actual_close()
	while _terminal.is_empty() and _state!="FAILED": await actual_main_progress
	return _terminal if not _terminal.is_empty() else _fail("actual_original_close_failed")
func request_original_character_select_transition(world: Dictionary) -> bool:
	var event: Dictionary=_prefix.actual_current_original_event()
	if world!=_world or event.get("operation")!=&"original_character_select_transition": return false
	if not _actual_terminal_intent.is_empty() and _actual_terminal_intent != "CHARACTER_SELECT": return false
	_actual_terminal_intent = "CHARACTER_SELECT"
	_close_authorized=true;_begin_actual_close()
	# Actual Main scene change/reload is forbidden until terminal proof. Root's
	# bootstrap publisher owns the original code-retained scene transition.
	return true
func _begin_actual_close() -> void:
	if _state=="S": _state="DRAINING"
func service_actual_original_Main_phase(listener: Node) -> void:
	if listener!=_listener or not listener.is_inside_tree() or OS.get_thread_caller_id()!=OS.get_main_thread_id(): return
	# Preallocation installs this same listener before PREPARED. Until Native
	# has actually launched S there is no packet or view owner to service.
	# Once launched, epoch-zero adoption itself needs this pump, so neither
	# the S state nor the adoption journal may be used as a service gate.
	if _host.status().get("started") != true:
		actual_main_progress.emit()
		return
	# The unique existing Main prefix/primitive executor services its actual
	# Native packets; this transport never builds an alternate resource queue.
	if (_state == "DRAINING" and _close_authorized) or _state == "CLOSING":
		# Only the bound real IO owner exposes this same World. No independent
		# HUD retirement queue or fabricated producer is created by transport.
		var views: Variant = _io.get("_session_views")
		if not views is RefCounted or _io.get("_session_transport") != self or views.get("_transport") != self or views.get("_world") != _world:
			_reject("actual_same_World_UI_close_owner_required",{}); return
		if not views.close_original_view_input_admission(_world):
			_reject("actual_accepted_World_UI_input_not_drained",{}); return
		var ui: Dictionary = views.service_actual_original_ui_close()
		if ui.get("success") != true:
			_reject("actual_World_UI_close_service_failed",ui); return
	var served: Dictionary=_main_pump.service_actual_original_main_transport(_host,_prefix,self)
	if served.get("status") not in ["SERVICED","PENDING"]: _reject("actual_Main_transport_service_failed",served)
	_flush_actual_input()
	if _state=="DRAINING" and _close_authorized and _pending.is_empty() and _acks.is_empty() and _feature_calls.is_empty() and _feature_acks.is_empty() and _notifications.is_empty() and _hud.is_empty() and _host.status().get("input_queue_size") == 0:
		_state="CLOSING";_host.request_close()
	if _state=="CLOSING":
		var terminal: Dictionary=actual_original_main_closing_receipt()
		if terminal.get("success")==true: _terminal=terminal;_state="CLOSED"
	actual_main_progress.emit()
func _flush_actual_input() -> void:
	if _host==null or _state not in ["S","DRAINING"]: return
	for id: int in _pending.keys():
		if _pending[id].submitted: continue
		if not _host.submit_input(_pending[id].packet): return
		_pending[id].submitted=true
	for id: int in _acks.keys():
		# Repeat admission is prevented by actual submitted marker; the result
		# obligation remains until Source's reliable journal ACK is observed.
		if _ack_submitted.has(id): continue
		if not _host.submit_input(_acks[id]): return
		_ack_submitted[id]=true
	while not _notifications.is_empty():
		if not _host.submit_input(_notifications[0]): return
		_notifications.pop_front()
	while not _hud.is_empty():
		if not _host.submit_input(_hud[0]): return
		_hud.pop_front()
	for id: int in _feature_calls:
		var call: Dictionary = _feature_calls[id]
		if call.submitted: continue
		if not _host.submit_input(call.packet): return
		call.submitted = true
	for id: int in _feature_acks:
		if _feature_ack_submitted.has(id): continue
		if not _host.submit_input(_feature_acks[id]): return
		_feature_ack_submitted[id] = true
func actual_original_main_closing_receipt() -> Dictionary:
	if _state=="CLOSED": return _terminal
	if _state!="CLOSING" or not _pending.is_empty() or not _acks.is_empty() or not _feature_calls.is_empty() or not _feature_acks.is_empty(): return {"status":"PENDING","success":false}
	var io: Dictionary=_io.inspect_actual_original_main_warm_io()
	if io.get("status")!="READY": return io
	var status: Dictionary=_host.status()
	# Native close_failed is a retained-owner progress observation. The closing
	# loop deliberately sets it while accepted IO/leases are still draining and
	# clears it at real quiescence; it is not a permanent application failure.
	if status.get("close_quiescent")!=true or status.get("join_complete")!=true: return {"status":"PENDING","success":false}
	var proof: Dictionary=_main_pump.actual_original_main_terminal_receipt(_host,_prefix,_session_id,io)
	if proof.get("success")!=true or not proof.get("receipt") is Dictionary: return proof
	if not _host.close_and_join(): return {"status":"PENDING","success":false}
	return proof
func actual_original_terminal_intent() -> String: return _actual_terminal_intent

func retire_actual_started_terminal_listener(terminal: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _state != "CLOSED" or terminal.get("success") != true or terminal != _terminal: return false
	if _actual_terminal_listener_retired: return true
	var native: Dictionary = _host.status()
	if native.get("close_quiescent") != true or native.get("join_complete") != true or native.get("running") != false: return false
	for held: Variant in [_pending,_acks,_ack_submitted,_results,_notifications,_hud,_feature_calls,_feature_acks,_feature_ack_submitted]:
		if not held.is_empty(): return false
	if is_instance_valid(_listener): _listener.free()
	_listener = null; _bootstrap = null; _main_pump = null; _prefix = null
	_io = null; _fatal = null; _admission = null; _input_publisher = null
	_actual_terminal_listener_retired = true
	return true

func finish_actual_started_terminal_references(unbound: Dictionary, terminal: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _state != "CLOSED" or not _actual_terminal_listener_retired or terminal != _terminal or terminal.get("success") != true or unbound.get("success") != true or unbound.get("status") != "UNBOUND_AFTER_CLOSE" or unbound.get("host_object_id") != _host.get_instance_id(): return false
	var native: Dictionary = _host.status()
	if native.get("main_channels_unbound_after_close") != true or native.get("close_quiescent") != true or native.get("join_complete") != true: return false
	_host = null; _facade = null; _tree = null; _world = {}; _prepared = {}; _adopted = {}
	return true

func original_main_transport_listener_exit(listener: Node) -> void:
	if listener==_listener and _state!="CLOSED": _reject("actual_Main_listener_retired_before_terminal",{})
func _reject(code: String, details: Dictionary) -> void:
	_state="FAILED";_fatal.reject_original_main_profile_writer({"method":code,"details":details})
func _fail(code: String, details: Dictionary={}) -> Dictionary: return {"success":false,"status":"INVALID","errors":[code],"details":details}

func _actual_feature_main() -> RefCounted:
	# The composition binds the actual executor directly; it is not discovered
	# through a UI name, a second service or an arbitrary callable provider.
	if _main_pump == null: return null
	var feature: Variant = _main_pump.get("_feature")
	return feature if feature is RefCounted and feature.get_script().resource_path == "res://scripts/features/runtime/feature_resource_main_primitives.gd" else null

func admit_original_feature_owner_call(method: String, arguments: Array, consume_automatically := false) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _state != "S" or _host.status().get("close_requested") == true or _session_id <= 0 or not FeatureCalls.accepts(method,arguments): return _fail("actual_original_Feature_command_admission_required")
	if _feature_calls.size()+_pending.size() >= _capacity: return {"success":false,"status":"BACKPRESSURE"}
	if consume_automatically and method not in FeatureCalls.VOID_CALLS: return _fail("actual_Feature_result_consumer_required")
	var feature: RefCounted = _actual_feature_main()
	if feature == null: return _fail("actual_same_Feature_executor_required")
	var id: int = _feature_call_sequence+1
	var captured: Dictionary = feature.capture_original_feature_command_loans(id,arguments,_tree.current_scene)
	if captured.get("success") != true: return captured
	var packet: Dictionary = {"contract_id":"hardcore.feature.Main_command.v1","owner_session_id":_session_id,"command_id":id,"method":method,"arguments":captured.arguments,"scene":captured.scene,"loan_id":captured.loan_id,"actual_main_process_frame":Engine.get_process_frames()}
	var ticket: Dictionary = {"contract_id":"hardcore.feature.Main_command_ticket.v1","owner_session_id":_session_id,"command_id":id,"command_sha256":CommandDigest.sha256(packet)}
	_feature_calls[id] = {"packet":packet,"ticket":ticket,"submitted":false,"imported":false,"result":{},"consumed":false,"automatic":consume_automatically}
	_feature_call_sequence = id
	_flush_actual_input()
	return {"success":true,"status":"MAIN_HELD","ticket":ticket.duplicate(true)}

func await_original_feature_owner_result(ticket: Dictionary) -> Variant:
	var id: int = int(ticket.get("command_id",0))
	if not _feature_calls.has(id) or _feature_calls[id].ticket != ticket or _feature_calls[id].automatic: return _fail("actual_same_Feature_result_ticket_required")
	while _feature_calls.has(id) and _feature_calls[id].result.is_empty():
		if _state == "FAILED": return _fail("actual_Feature_command_failed_retained_obligation")
		await actual_main_progress
	if not _feature_calls.has(id): return _fail("actual_Feature_result_consumed_twice")
	var record: Dictionary = _feature_calls[id]
	var feature: RefCounted = _actual_feature_main()
	if feature == null or record.consumed: return _fail("actual_Feature_result_owner_required")
	var value: Variant = feature.decode_original_source_value(record.result.result)
	if feature.get("_failed") == true: return _fail("actual_Feature_result_reference_unproved")
	if not _acknowledge_actual_feature_result(id): return _fail("actual_Feature_result_ack_retained")
	return value

func _acknowledge_actual_feature_result(id: int) -> bool:
	if not _feature_calls.has(id): return false
	var record: Dictionary = _feature_calls[id]
	if record.result.is_empty() or record.consumed: return false
	record.consumed = true
	_feature_acks[id] = {"contract_id":"hardcore.feature.Main_command_ack.v1","owner_session_id":_session_id,"command_id":id,"result_sha256":CommandDigest.sha256(record.result)}
	_flush_actual_input()
	return true

func _apply_actual_original_feature_call_event(event: Dictionary) -> bool:
	var args: Variant = event.get("arguments")
	if not args is Array or args.size() != 1 or not args[0] is Dictionary: return false
	var fact: Dictionary = args[0]
	var id: int = int(fact.get("command_id",0))
	if not _feature_calls.has(id) or fact.get("owner_session_id") != _session_id: return false
	var record: Dictionary = _feature_calls[id]
	var feature: RefCounted = _actual_feature_main()
	if feature == null or not record.submitted: return false
	if event.operation == &"original_feature_call_acknowledged":
		if not record.consumed or not _feature_acks.has(id) or fact.get("result_sha256") != _feature_acks[id].result_sha256: return false
		if not feature.retire_actual_feature_command_loan_association(id): return false
		_feature_calls.erase(id); _feature_acks.erase(id); _feature_ack_submitted.erase(id)
		return true
	if fact.get("command_sha256") != record.ticket.command_sha256 or fact.get("loans_imported") != true: return false
	if not feature.acknowledge_actual_feature_command_import(id,record.packet.arguments,record.packet.scene): return false
	record.imported = true
	if event.operation == &"original_feature_call_admitted": return true
	if event.operation != &"original_feature_call_result" or not fact.has("result") or not record.result.is_empty(): return false
	# The original void operations return null. An admission error is a real
	# failed cleanup obligation, never a successfully consumed void callback.
	if record.automatic and fact.result != null: return false
	record.result = fact.duplicate(true)
	if record.automatic: return _acknowledge_actual_feature_result(id)
	return true

func actual_original_feature_closing_acknowledgements() -> Array:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _state not in ["DRAINING","CLOSING"]: return []
	# A fault close may stop ordinary Native input before these accepted result
	# ACKs. The real closing MainIO publication carries these same exact values;
	# it does not make new commands or infer their Source consumption.
	return _feature_acks.values().duplicate(true)

var _profile_terminal_export: Dictionary
var _profile_terminal_event_identity: Dictionary
func actual_profile_terminal_export() -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _actual_terminal_intent!="CHARACTER_SELECT" or _state!="CLOSED" or _terminal.get("success")!=true: return {}
	return _profile_terminal_export
