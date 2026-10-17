extends Node
const Failure := preload("res://scripts/gameplay/source/main_source_failure.gd")
const MainPrimitives := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Source := preload("res://tests/framework/helpers/feature_live_jobs_source_20261016.gd")
const Capture := preload("res://scripts/gameplay/source/main_original_process_scope.gd")
const Pump := preload("res://scripts/layers/runtime/execution/paused_receipt_pump.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Observe := preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
const Admission := preload("res://scripts/gameplay/source/main_source_admission.gd")
const RootCapture := preload("res://scripts/gameplay/source/source_persistent_path_main.gd")
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
	await _prepare_actual_code_cover()
	if _failed > 0: _finish(); return
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
	check(_main_primitives.configure_original_source_owned_main(_physical_facade,observer,validator,config.bridge_generation),"actual Main primitive registry exports genuine object descriptors")
	check(_physical_facade.configure_main(_main_primitives),"actual physical facade retains only real resource retirement side facts")
	if exercise_main_resource_pump:
		var prefix := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd").new(_host,self)
		_resource_pump = load("res://scripts/gameplay/source/main_original_resource_pump.gd").new()
		check(_resource_pump.configure_main(_host,prefix,_main_primitives,config.bridge_generation),"actual resource pump binds the same Main executor and Native bridge")
		_streaming_primitives = preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd").new()
		check(_streaming_primitives.configure_main(validator,observer,config.bridge_generation),"actual streaming vault uses the same genuine Native cold ticket validator")
		_streaming_catalog = _streaming_primitives.capture_catalog(PackedInt32Array())
		check(_resource_pump.bind_actual_original_streaming(_streaming_primitives),"same Main pump binds the actual streaming vault without a second request queue")
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":0,"runtime_map_id":-1,"profile_id":"isolated.persistent_process.component"}
	var boot := {"exercise_main_live_feature":exercise_main_live_feature,"streaming_catalog":_streaming_catalog,"exercise_main_resource_pump":exercise_main_resource_pump,"origins":origins,"settings":Observe.settings(),"coordinator_idle":idle.publication,"root_membership":membership,"world_identity":world,"feature_resources":{"lease_owner":_main_primitives.export_boot_value(_physical_facade),"scene_tree":_main_primitives.export_boot_value(get_tree())}}
	boot.exercise_main_world_pump = exercise_main_world_pump
	boot.merge(_capture_actual_job_inputs(origins,config.bridge_generation))
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
			print("ACTUAL_FEATURE_MAIN_REJECTED_BODY ", {"held":_resource_pump.get("_live_held"),"last_request":_main_primitives.get("_last_request"),"last_reply":_main_primitives.get("_last_reply"),"failed":_main_primitives.get("_failed")})
			_record_actual_reference_diagnostics(_main_primitives.get("_last_reply"))
			check(false,"actual async Main Feature service:"+str(async_serviced)); _finish(); return
	if exercise_main_live_feature and _closing and not _live_closed and (not exercise_model_close_once or _host.status().get("source_model_close_completed") == true):
		var first_close: bool = not _close_diag_recorded
		if first_close:
			_close_diag_recorded = true
			print("PROFILE_MAIN_FEATURE_CLOSE_ENTER ",_host.status())
		var retired: Dictionary = _resource_pump.service_original_live_feature_retirement()
		if first_close: print("PROFILE_MAIN_FEATURE_CLOSE_RETURN ",retired)
		_live_closed = retired.get("status") == "READY"
	var packet: Dictionary = _host.acquire_presentation(_last_tick+1,32)
	if not packet.is_empty():
		_actual_kernel_state = packet.frame.get("actual_feature_kernel_state",{})
		if not packet.frame.get("prepared_code_value",{}).is_empty() and _target_loan.is_empty():
			var actual_prepared: Variant=_main_primitives.decode_original_source_value(packet.frame.prepared_code_value)
			check(actual_prepared is Dictionary and actual_prepared.get("lease") is RefCounted,"Main decodes the same actual input Lease before the original next code call")
			_target_loan=_main_primitives.capture_original_feature_command_loans(3,[actual_prepared,_code_consumer,1],get_tree().current_scene)
			check(_target_loan.get("success")==true and _host.submit_input({"kind":"actual_feature_kernel_target","loan":_target_loan,"actual_main_process_frame":Engine.get_process_frames()}),"actual Main next call captures fresh loan and enters the real Native input FIFO")
		if packet.frame.get("target_loan_imported") == true and not _target_import_observed:
			_target_import_observed=true
			check(_main_primitives.acknowledge_actual_feature_command_import(3,_target_loan.arguments,_target_loan.scene),"Main acknowledges target loan only after actual Source import")
		if packet.frame.get("feature_loans_imported") == true and not _job_import_observed:
			_job_import_observed=true
			for id: int in [1,2]:
				var loan: Dictionary=_job_main_loans[id-1]
				check(_main_primitives.acknowledge_actual_feature_command_import(id,loan.arguments,loan.scene),"Main observes genuine Source loan import before acknowledging its same association")
		_last_tick = int(packet.tick)
		_host.ack_events(int(packet.through_ordinal))
		if packet.frame.get("need_pause") == true and not _paused:
			_paused = true
			check(_host.submit_input({"kind":"persistent_process_fixture_pause"}),"Main admits pause input; only real S mutates simulation pause")
		if packet.frame.get("done") == true and not _closing:
			if not packet.frame.get("actual_source_fault_records",[]).is_empty():
				print("FEATURE_KERNEL_ACTUAL_SOURCE_FAULTS ",packet.frame.actual_source_fault_records)
				print("FEATURE_KERNEL_LAST_ACTUAL_MAIN_REPLY ",_main_primitives.get("_last_reply"))
			if exercise_main_live_feature: print("PROFILE_MAIN_DONE ",{"tick":packet.tick,"host":_host.status()})
			for row: Dictionary in packet.frame.checks: check(row.passed,row.label)
			if _resource_pump != null:
				check(_resource_pump.inspect_actual_original_pending_resources().get("completed") == (5 if exercise_main_world_pump else 4),"all interleaved actual Native requests execute once on the shared sequence")
			if exercise_main_live_feature:
				check(_resource_pump.inspect_actual_original_pending_resources().get("live_completed") == packet.frame.get("feature_retired_leaf_count"),"every actually accepted Coordinator leaf executes and retires once on the same Native pump")
			check(packet.frame.get("actual_component_result_consumers",[]) == [1,2,3],"Main observes the three actual component result consumers before retiring their imported argument custody")
			check(_main_primitives.retire_actual_feature_command_loan_association(1) and _main_primitives.retire_actual_feature_command_loan_association(2) and _main_primitives.retire_actual_feature_command_loan_association(3),"component removes only actually imported/completed command associations")
			_closing = true
			if reject_main_after_completed_writer:
				_fatal.reject_original_main_profile_writer({"method":"isolated.refused_Main_write_after_real_Source_writer","state":"S"})
				check(_host.status().get("close_requested") == true,"actual Main refusal requests genuine Source closure without waiting on Main")
			else: _host.request_close()
	if _closing and _host.status().get("join_complete") == true:
		var actual_closed: bool = _host.close_and_join()
		if reject_main_after_completed_writer:
			var status: Dictionary = _host.status()
			check(not actual_closed and status.get("fault") == "original_main_source_fault:isolated.refused_Main_write_after_real_Source_writer","actual joined Source retains expected formal Main-writer fault instead of relabeling it success")
			check(status.get("running") == false and status.get("close_quiescent") == true and status.get("join_complete") == true,"real Source closure and external physics release complete before Main drops the faulted Host")
			check(status.get("original_main_source_fault",{}).get("fact",{}).get("state") == "S","Native fault receipt preserves the real admitted Source ownership state")
		else: check(actual_closed,"actual Source closes before Main joins")
		_host = null
		check(_main_primitives.close_main(),"actual claim/retention/vault facts drain before physical owner close")
		check(JobGate.release_after_host_quiescence(_job_gate),"actual Source reader leaves before publication retirement")
		_finish()
	elif Time.get_ticks_usec()>_deadline:
		print("ACTUAL_FEATURE_KERNEL_STATE_AT_DEADLINE ",_actual_kernel_state)
		print("ACTUAL_FEATURE_MAIN_REPLY_AT_DEADLINE ",_main_primitives.get("_last_reply"))
		print("PERSISTENT_MAIN_DEADLINE ",{"host":_host.status(),"last_tick":_last_tick,"closing":_closing,"pump":_resource_pump.inspect_actual_original_pending_resources() if _resource_pump!=null else {}})
		check(false,"persistent Profile component completed before its explicit deadline")
		_finish()
func _record_actual_reference_diagnostics(value: Variant) -> void:
	if value is Array:
		for element: Variant in value: _record_actual_reference_diagnostics(element)
	elif value is Dictionary:
		if value.get("contract_id") == "feature.main.reference.v1":
			var vault: Dictionary = _main_primitives.get("_vault")
			var actual: Dictionary = vault.get(value.get("token_id"),{})
			print("ACTUAL_FEATURE_REFERENCE_FACT ", {"descriptor":value,"vault_present":not actual.is_empty(),"descriptor_equal":actual.get("descriptor")==value,"object_alive":instance_from_id(int(value.get("object_id",0)))!=null})
		for element: Variant in value.values(): _record_actual_reference_diagnostics(element)
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
	var scope_receipt: Dictionary={"schema_version":1,"scene_id":scene_id,"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"native_process_id":OS.get_process_id(),"scope":"actual Native Feature component kernel","standard_receipt_result":"PASS" if written and _failed==0 else "FAIL","formal_enter_live":"NOT_RUN","fullWorld":"NOT_RUN","positive_LIVE_publication":"NOT_RUN","same_path_issued_and_normal_GET_integration":"NOT_RUN"}
	var scope_file: FileAccess=FileAccess.open("res://outputs/test_logs/framework/"+scene_id+".scope.json",FileAccess.WRITE)
	if scope_file!=null:
		scope_file.store_string(JSON.stringify(scope_receipt,"  ")); scope_file.close()
	else: written=false
	print(scene_id.to_upper()+"_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)

# Component kernel only: actual Native/Session/scope/budget/Coordinator bodies.
# Formal Session.enter_live and full World/adoption are explicitly NOT_RUN.
const JobGate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const JobRegistry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const JobData := preload("res://scripts/features/generated/internal_code_preparation_catalog_data.gd")
class CodeConsumer extends Control:
	func is_code_preparation_generation_current(value: int) -> bool: return value==1
	func is_code_preparation_loading_phase_current(value: int) -> bool: return value==1
var _physical_facade: Node
var _code_consumer: Control
var _code_scope: RefCounted
var _job_gate: Dictionary
var _job_import_observed := false
var _job_main_loans: Array=[]
var _target_loan: Dictionary={}
var _target_import_observed := false
var _actual_kernel_state: Dictionary = {}
func _init() -> void:
	exercise_main_resource_pump=true; exercise_main_live_feature=true
func _prepare_actual_code_cover() -> void:
	_code_consumer=CodeConsumer.new(); add_child(_code_consumer)
	var overlay: Control=preload("res://scripts/loading_transition_overlay.gd").new(); _code_consumer.add_child(overlay)
	overlay.begin_loading("actual.Feature.CPS.kernel")
	await overlay.transition_covered
	_code_scope=preload("res://scripts/features/contracts/loading_preparation_scope.gd").issue(overlay,_code_consumer,1)
	check(_code_scope!=null and _code_scope.valid_for(_code_consumer,1),"actual original overlay issues the real code cover Scope")
	if _code_scope==null: return
	var published: bool=await ContentLayers.ensure_internal_code_catalogue_async(_code_scope,_code_consumer,1)
	check(published,"original Main code publisher verifies its actual current engine catalogue before Source starts")
	if not published: return
	var entry_id: String="framework.code.caster_animation.v1"
	var actual_payload: Dictionary=ContentLayers.get("_internal_code_entries").get(entry_id,{})
	var actual_publication: Dictionary=ContentLayers.code_preparation_published_entry(entry_id)
	var publication_current: bool=not actual_payload.is_empty() and not actual_publication.is_empty() and actual_publication.get("entry_id")==entry_id and actual_publication.get("target_path")==actual_payload.get("target_path") and actual_publication.get("plan_sha256")==JSON.stringify(actual_payload,"",true).sha256_text() and actual_payload==JobData.read_bundle().entries.get(entry_id) and ContentLayers.is_code_preparation_publication_current(entry_id,actual_publication.generation,actual_publication.source_revision,actual_publication.plan_sha256)
	check(publication_current,"actual nonempty producer payload and official publication metadata retain the same current entry/target/hash/generation")
	if not publication_current: return
	var declarations: Dictionary=JobRegistry.declarations()
	check(declarations.get("success")==true,"canonical resource registry is loaded and validated on Main")
	_job_gate=JobGate.publish("actual.Feature.CPS.kernel.20261016")
	check(not _job_gate.is_empty(),"actual catalog gate protects the same published registry for Source")
	_physical_facade=preload("res://scripts/features/runtime/feature_resource_main_facade.gd").new(); add_child(_physical_facade)
func _capture_actual_job_inputs(origins: Dictionary, _generation: int) -> Dictionary:
	var record: Dictionary=JobRegistry.record_by_id("hc.resource.item.healing.inventory")
	var catalog: Dictionary={"revision":"actual.Feature.CPS.kernel.20261016","modules":{"fixture.actual.resource":{"requires":[],"resource_dependencies":[record.path]}}}
	var module_args: Array=[catalog,["fixture.actual.resource"]]
	var payload: Dictionary=JobData.read_bundle().entries["framework.code.caster_animation.v1"]
	var code_args: Array=[payload,"framework.code.caster_animation.v1",ContentLayers,_code_scope,_code_consumer,1]
	var captured_frame: int=Engine.get_process_frames()
	var first: Dictionary=_main_primitives.capture_original_feature_command_loans(1,module_args,get_tree().current_scene)
	var second: Dictionary=_main_primitives.capture_original_feature_command_loans(2,code_args,get_tree().current_scene)
	first.actual_main_process_frame=captured_frame; second.actual_main_process_frame=captured_frame
	check(first.get("success")==true and second.get("success")==true,"two original call sites capture fresh actual Main values and their original scene")
	_job_main_loans=[first,second]
	var policy: Dictionary={}
	for key: String in preload("res://scripts/features/runtime/source_feature_live_provider.gd").LIVE_JOB_OPERATIONS: policy[key]=0
	return {"job_gate":_job_gate,"job_policy":policy,"job_loans":[first,second],"job_record_path":record.path,"job_manifest":{"captured":true,"scope_id":origins.feature.node_id,"process_priority":origins.feature.scope.process_priority,"tree_ordinal":origins.feature.tree_ordinal,"lazy_birth_entry":"res://scripts/layers/runtime/content_layer_registry.gd:_feature_resources"}}
