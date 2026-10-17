extends Node
const Failure := preload("res://scripts/gameplay/source/main_source_failure.gd")
const MainPrimitives := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Source := preload("res://tests/framework/helpers/persistent_close_scope_source_20261018.gd")
const Capture := preload("res://scripts/gameplay/source/main_original_process_scope.gd")
const Pump := preload("res://scripts/layers/runtime/execution/paused_receipt_pump.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Observe := preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
const Admission := preload("res://scripts/gameplay/source/main_source_admission.gd")
const RootCapture := preload("res://scripts/gameplay/source/source_persistent_path_main.gd")
const ClosingProducer := preload("res://scripts/gameplay/source/main_close_process_frame_producer.gd")
var _closing_producer: RefCounted
var _close_checks_reported := false
var _proof := Proof.new()
var _failed := 0
var _host: Object
@export var reject_main_after_completed_writer := false
@export var exercise_main_resource_pump := false
@export var exercise_main_world_pump := false
@export var exercise_main_live_feature := false
@export var exercise_model_close_once := false
var _close_diag_recorded := false
var _live_closed := false
var _resource_pump: RefCounted
var _streaming_primitives: RefCounted
var _streaming_catalog: Dictionary
var _fatal: RefCounted
var _main_primitives: RefCounted
var _feature: Node
var _last_tick := 0
var _deadline := 0
var _paused := false
var _closing := false
var _internal_front: Node
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok:
		_failed += 1
		print("PERSISTENT_MAIN_CHECK_FAILED ",label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	if exercise_main_live_feature:
		var code: Script = load("res://scripts/gameplay/source/main_original_resource_pump.gd")
		var present := false
		for method: Dictionary in code.get_script_method_list():
			if method.name == &"service_original_live_feature_resources": present = true
		check(present,"actual production Main async Feature resource pump exists")
		if not present: _finish(); return
	if exercise_main_resource_pump:
		check(FileAccess.file_exists("res://scripts/gameplay/source/main_original_resource_pump.gd"),"actual Main resource pump implementation exists")
		if _failed != 0: _finish(); return
	_internal_front = Node.new()
	get_tree().root.add_child(_internal_front,false,Node.INTERNAL_MODE_FRONT)
	_feature = ContentLayers._feature_resources()
	var pump: Node
	for child: Node in PlayerState.get_children():
		if child.get_script() == Pump: pump = child
	check(pump != null,"capture the actual existing paused receipt child, not a new receipt clock")
	if pump == null: _finish(); return
	pump.process_priority = -7 # Actual nondefault priority in this isolated tree.
	var origins := {"profile":Capture.capture_existing(PlayerState),"feature":Capture.capture_existing(_feature),"profile_receipts":Capture.capture_existing(pump)}
	for key: String in origins: check(origins[key].get("success") == true,"actual Main callback origin captured:"+key)
	var admission := Admission.new()
	admission.set("_legacy_resources",_feature)
	var idle: Dictionary = admission.capture_original_resource_idle_state()
	check(idle.get("success") == true,"actual existing ContentLayers coordinator has no accepted queue obligations before capture")
	if idle.get("success") != true: _finish(); return
	var membership: Dictionary = {}
	var capture_api: Script = RootCapture
	for method: Dictionary in capture_api.get_script_method_list():
		if method.name == &"capture_actual_root_membership": membership = capture_api.call("capture_actual_root_membership",get_tree())
	check(membership.get("success") == true,"the actual persistent root producer captures internal-front and normal sibling positions")
	if membership.get("success") == true:
		var found := false
		for row: Dictionary in membership.root_children:
			if row.node_id == PlayerState.get_instance_id():
				found = true
				check(row.index == PlayerState.get_index(true),"global membership and Main scope use the same internal-inclusive index")
		check(found,"actual PlayerState identity is present in the root membership ledger")
		check(origins.profile.get("root_child_id") == PlayerState.get_instance_id() and origins.feature.get("root_child_id") == ContentLayers.get_instance_id(),"nested scopes carry their genuine top-level owner identity")
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115154,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	if exercise_main_live_feature: config.live_primitive_capacity = 2
	_main_primitives = MainPrimitives.new()
	var observer: Object = ClassDB.instantiate("HardCoreResourceObservation")
	var validator: Callable = Callable(_host,"validate_original_primitive_ticket") if exercise_main_resource_pump else _unexpected_main_resource_call
	check(_main_primitives.configure_main(_feature,observer,validator,_unexpected_main_resource_call,_unexpected_main_resource_call,config.bridge_generation),"actual Main primitive registry exports genuine object descriptors")
	if exercise_main_resource_pump:
		var prefix := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd").new(_host,self)
		_resource_pump = load("res://scripts/gameplay/source/main_original_resource_pump.gd").new()
		check(_resource_pump.configure_main(_host,prefix,_main_primitives,config.bridge_generation),"actual resource pump binds the same Main executor and Native bridge")
		_streaming_primitives = preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd").new()
		check(_streaming_primitives.configure_main(validator,observer,config.bridge_generation),"actual streaming vault uses the same genuine Native cold ticket validator")
		_streaming_catalog = _streaming_primitives.capture_catalog(PackedInt32Array())
		check(_resource_pump.bind_actual_original_streaming(_streaming_primitives),"same Main pump binds the actual streaming vault without a second request queue")
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"isolated.persistent_process.component"}
	var boot := {"exercise_main_live_feature":exercise_main_live_feature,"streaming_catalog":_streaming_catalog,"exercise_main_resource_pump":exercise_main_resource_pump,"origins":origins,"settings":Observe.settings(),"coordinator_idle":idle.publication,"root_membership":membership,"world_identity":world,"feature_resources":{"lease_owner":_main_primitives.export_boot_value(_feature),"scene_tree":_main_primitives.export_boot_value(get_tree())}}
	boot.exercise_main_world_pump = exercise_main_world_pump
	_fatal = Failure.new()
	check(_fatal.configure_main(_host),"actual failure owner binds before the real Source factory starts")
	var factory: Script = Source
	if exercise_model_close_once: factory = preload("res://tests/framework/helpers/model_close_once_source_20261016.gd")
	var started: bool = _host.start(factory,boot,config)
	check(started,"actual Native Host starts this persistent-Profile component on S")
	if not started: _host = null; _finish(); return
	check(_host.bind_original_main_feature_claim_producer(_main_primitives,_main_primitives.get_script().get_source_code().sha256_text()),"actual Native Main binding accepts the reviewed matching source seal")
	if exercise_main_live_feature:
		check(_resource_pump.bind_actual_original_live_feature(),"actual Native LIVE Feature Main source is bound to this same vault")
	_closing_producer = ClosingProducer.new()
	var bound: Dictionary = _closing_producer.configure_main(_host,get_tree(),115154,115154,16,_fatal)
	check(bound.get("success") == true,"genuine Main closing producer bound to same persistent Session component")
	_deadline = Time.get_ticks_usec()+25000000
func _unexpected_main_resource_call(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> Dictionary:
	check(false,"pure Profile callback component must not invoke a Main resource body")
	return {"success":false,"error":"unexpected Main resource operation"}
func apply_original_main_journal_event(_event: Dictionary) -> bool:
	check(false,"read-only resource probe must not invent presentation writes")
	return false
func _process(_delta: float) -> void:
	if _host == null: return
	if _resource_pump != null:
		var serviced: Dictionary = _resource_pump.service_original_main_resources() if exercise_main_world_pump else _resource_pump.service_original_cold_resources()
		if serviced.get("status") not in ["PENDING","SERVICED"]:
			check(false,"actual Main resource service:"+str(serviced))
			_finish(); return
	if exercise_main_live_feature and _last_tick >= 3:
		var async_serviced: Dictionary = _resource_pump.service_original_live_feature_resources()
		if async_serviced.get("status") not in ["PENDING","SERVICED"]:
			check(false,"actual async Main Feature service:"+str(async_serviced)); _finish(); return
	if exercise_main_live_feature and _closing and not _live_closed and (not exercise_model_close_once or _host.status().get("source_model_close_completed") == true):
		var first_close: bool = not _close_diag_recorded
		if first_close:
			_close_diag_recorded = true
			print("PROFILE_MAIN_FEATURE_CLOSE_ENTER ",_host.status())
		var retired: Dictionary = _resource_pump.service_original_live_feature_retirement()
		if first_close: print("PROFILE_MAIN_FEATURE_CLOSE_RETURN ",retired)
		_live_closed = retired.get("status") == "READY"
	var packet: Dictionary = _host.acquire_presentation(0 if _closing else _last_tick+1,32)
	if not packet.is_empty():
		_last_tick = int(packet.tick)
		_host.ack_events(int(packet.through_ordinal))
		if packet.frame.get("need_pause") == true and not _paused:
			_paused = true
			check(_host.submit_input({"kind":"persistent_process_fixture_pause"}),"Main admits pause input; only real S mutates simulation pause")
		if packet.frame.get("done") == true and not _closing:
			if exercise_main_live_feature: print("PROFILE_MAIN_DONE ",{"tick":packet.tick,"host":_host.status()})
			for row: Dictionary in packet.frame.checks: check(row.passed,row.label)
			if _resource_pump != null:
				check(_resource_pump.inspect_actual_original_pending_resources().get("completed") == (5 if exercise_main_world_pump else 4),"all interleaved actual Native requests execute once on the shared sequence")
			if exercise_main_live_feature:
				check(_resource_pump.inspect_actual_original_pending_resources().get("live_completed") == 1,"one actual async Feature body/reply completes without replay")
			_closing = true
			if reject_main_after_completed_writer:
				_fatal.reject_original_main_profile_writer({"method":"isolated.refused_Main_write_after_real_Source_writer","state":"S"})
				check(_host.status().get("close_requested") == true,"actual Main refusal requests genuine Source closure without waiting on Main")
			else:
				check(_closing_producer.arm_at_original_close_request(),"actual closing producer arms before Source close")
				_host.request_close()
		if packet.frame.get("close_checks") is Array and not _close_checks_reported:
			_close_checks_reported = true
			for row: Dictionary in packet.frame.close_checks: check(row.passed,row.label)
	if _closing and _host.status().get("join_complete") == true:
		# Join may become visible after this Main frame's first acquire.
		var final_packet: Dictionary = _host.acquire_presentation(0,32)
		if not _close_checks_reported and final_packet.get("frame",{}).get("close_checks") is Array:
			_close_checks_reported = true
			for row: Dictionary in final_packet.frame.close_checks: check(row.passed,row.label)
			_host.ack_events(int(final_packet.through_ordinal))
		check(_close_checks_reported,"actual Source published terminal closing checks before join")
		var obligations: Dictionary = _closing_producer.capture_actual_closing_process_obligations()
		check(obligations.capture_stopped and obligations.accepted.is_empty() and obligations.pending_service.is_empty(),"genuine STOP watermark and all accepted closing pairs drained")
		check(_closing_producer.finish_at_actual_Host_close(obligations.stop_receipt),"actual terminal proof frees the closing listener")
		var actual_closed: bool = _host.close_and_join()
		if reject_main_after_completed_writer:
			var status: Dictionary = _host.status()
			check(not actual_closed and status.get("fault") == "original_main_source_fault:isolated.refused_Main_write_after_real_Source_writer","actual joined Source retains expected formal Main-writer fault instead of relabeling it success")
			check(status.get("running") == false and status.get("close_quiescent") == true and status.get("join_complete") == true,"real Source closure and external physics release complete before Main drops the faulted Host")
			check(status.get("original_main_source_fault",{}).get("fact",{}).get("state") == "S","Native fault receipt preserves the real admitted Source ownership state")
		else: check(actual_closed,"actual Source closes before Main joins")
		_host = null
		_closing_producer = null
		_finish()
	elif Time.get_ticks_usec()>_deadline:
		print("PERSISTENT_MAIN_DEADLINE ",{"host":_host.status(),"last_tick":_last_tick,"closing":_closing,"pump":_resource_pump.inspect_actual_original_pending_resources() if _resource_pump!=null else {}})
		check(false,"persistent Profile component completed before its explicit deadline")
		_finish()
func _finish() -> void:
	set_process(false)
	if _host != null:
		_host.close_and_join()
		_host = null
	_resource_pump = null
	_streaming_primitives = null
	_main_primitives = null
	_feature = null # Actual autoload child retains its ordinary Main lifetime.
	if is_instance_valid(_internal_front): _internal_front.free()
	var scene_id: String = scene_file_path.get_file().get_basename()
	var written: bool = _proof.write_receipt(scene_id,_proof.records.size(),_failed)
	print(scene_id.to_upper()+"_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
