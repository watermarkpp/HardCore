extends RefCounted
## Main executes admitted original primitive bodies, never _process/queues/budget.
const PROTOCOL := "hardcore.streaming.primitives.v2"
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const Guard := preload("res://scripts/features/compilation/code_preparation_envelope_guard.gd")
const Android := preload("res://scripts/features/compilation/android_export_representation_verifier.gd")
const Acquire := preload("res://scripts/features/runtime/feature_resource_main_shader_acquisition.gd")
const METHODS := {"get_length": 0, "get_position": 0, "get_buffer": 1, "close": 0, "valid_for": 2, "is_verified": 0, "step": 0, "verify_next_source": 0, "paths": 0, "signature": 0, "target_path": 0, "revalidate_admission_sources": 0, "valid_asset": 2, "valid_target": 1, "valid_for_code": 1, "attach_loaded_code_resource": 4, "loaded_code_retention_current": 3, "transfer_loaded_code_retention": 4, "cancel": 0, "get_node_or_null": 1, "get_parent": 0, "get_node_count": 0, "get_node_property_count": 1, "get_node_property_name": 2, "get_node_property_value": 2, "change_scene_to_packed": 1, "is_inside_tree": 0, "is_queued_for_deletion": 0, "is_internal_code_publication_boundary_current": 1, "code_preparation_export_contract": 0, "code_preparation_export_seal_sha256": 0, "is_code_preparation_generation_current": 1, "is_code_preparation_loading_phase_current": 1, "code_preparation_cover_receipt": 0, "_feature_resources": 0, "get_object": 0, "get_method": 0, "complete_original_source_owner_header": 3, "source_application_call": 2}
const OPCODE_ARITY := {"object_get": 2, "object_call": 3, "object_script": 1, "object_valid": 1, "has_method": 2, "callback_valid": 1, "callback_invoke": 2, "get_cached_ref": 1, "exists": 2, "status": 1, "request": 3, "get": 1, "adopt_claims": 2, "valid_resource": 2, "open_image": 2, "issue_resource_lease": 4, "retain_publication": 1, "release_retention": 2, "retention_supports_path": 3, "issue_code_inputs": 4, "begin_code_verification": 4, "begin_export_verification": 3, "acquire_shader": 6, "release_reference": 1, "source_admission_unselected": 1, "source_admission_prepare": 3, "source_admission_commit": 2, "source_admission_abort": 1, "source_admission_loading": 1, "source_admission_pins": 1, "source_admission_release_pins": 1}
const PROPERTIES := ["root","current_scene","resource_path","scene_file_path","_launch_code_generation","launch_loading_overlay","_retained_code_resource"]
var _generation := 0
var _validate: Callable
var _publication_registrar: Callable
var _claim_transfer: Callable
var _observer: Object
var _facade: Node
var _next_token := 0
var _vault: Dictionary = {}
var _object_tokens: Dictionary = {}
var _callback_tokens: Array[int] = []
var _claims: Dictionary = {}
var _publications: Dictionary = {}
var _retentions: Dictionary = {}
var _next_retention := 0
var _observations: Dictionary = {}
var _native_observations: Array = []
var _last_request: Dictionary
var _last_reply: Dictionary
var _source_request: Dictionary
var _retirements: Array = []
var _owner_calls: Array = []
var _failed := false
var _original_source_admission: WeakRef
var _physical_owner_handoff: Dictionary = {}
var _original_source_owned := false

func configure_main(facade: Node, observer: Object, validate_ticket: Callable, publication_registrar: Callable, claim_transfer: Callable, generation: int) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or facade == null or not facade.is_inside_tree() or generation <= 0: return false
	if observer == null or not observer.has_method("threaded_status") or not validate_ticket.is_valid() or not publication_registrar.is_valid() or not claim_transfer.is_valid(): return false
	_facade=facade; _observer=observer; _validate=validate_ticket; _publication_registrar=publication_registrar; _claim_transfer=claim_transfer; _generation=generation
	return true

func configure_original_source_owned_main(facade: Node, observer: Object, validate_ticket: Callable, generation: int) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _generation != 0 or not is_instance_valid(facade) or not facade.is_inside_tree() or facade.get_script() != preload("res://scripts/features/runtime/feature_resource_main_facade.gd") or generation <= 0: return false
	if observer == null or not observer.is_class("HardCoreResourceObservation") or not validate_ticket.is_valid(): return false
	_facade = facade; _observer = observer; _validate = validate_ticket
	_publication_registrar = publish_actual_resource_lease
	_generation = generation; _original_source_owned = true
	# Issued Warm claims use their exact existing offer/accept range proof.
	# No unproven non-issued adoption callback is installed by this mode.
	return true

func _reject(reason: String) -> Dictionary:
	_failed=true
	push_error("Feature actual Main primitive rejected:"+reason)
	return {"executed":false,"error":reason}

func export_boot_value(value: Variant) -> Variant:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	return _encode(value)

func encode_original_source_value(value: Variant) -> Variant:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id() and not _failed)
	return _encode(value)

func decode_original_source_value(value: Variant) -> Variant:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id() and not _failed)
	return _decode(value)

func _encode(value: Variant) -> Variant:
	# Native cache misses are typed null Objects; transport carries only NIL.
	if value == null: return null
	# Each Resource result owns a new Main reference. An older Source proxy
	# may already owe release while this same physical cached Resource lives.
	if value is Resource:
		return _actual_owned_reference_value(value,[],0).value
	if value is Object or value is Callable:
		var object_id: int = value.get_instance_id() if value is Object else hash(value)
		var key:= ("object:" if value is Object else "callable:")+str(object_id)
		var token: int = int(_object_tokens.get(key,0)) if value is Object else 0
		if value is Callable:
			for candidate: int in _callback_tokens:
				if _vault.has(candidate) and _vault[candidate].value == value:
					token=candidate; break
		if token==0:
			_next_token+=1; token=_next_token
			if value is Object: _object_tokens[key]=token
			else: _callback_tokens.append(token)
			_vault[token]={"value":weakref(value) if value is Node or value is SceneTree else value,"weak":value is Node or value is SceneTree,"key":key}
		var types: Array[String]=[]
		for kind: String in ["Object","Node","SceneTree","Resource","Script","PackedScene","SceneState","Control","FileAccess"]:
			if value is Object and value.is_class(kind): types.append(kind)
		if value is Callable: types.append("Callable")
		var descriptor := {"contract_id":"feature.main.reference.v1","token_id":token,"object_id":object_id,"bridge_generation":_generation,"native_types":types}
		_vault[token].descriptor=descriptor.duplicate(true)
		return descriptor
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value: result[key]=_encode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(_encode(item))
		return result
	return value

func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.get("contract_id")=="feature.main.reference.v1":
			var id:=int(value.get("token_id",0))
			if value.get("bridge_generation")!=_generation or not _vault.has(id) or _vault[id].descriptor!=value:
				_failed=true; return null
			var entry: Dictionary=_vault[id]
			return entry.value.get_ref() if entry.weak else entry.value
		var result: Dictionary={}
		for key: Variant in value: result[key]=_decode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(_decode(item))
		return result
	return value

func capture_retirement(resources: Dictionary) -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	_retirements.append(_encode(resources))

func is_executing_original_primitive() -> bool:
	return not _source_request.is_empty()

func reject_external_retirement(resources: Dictionary) -> void:
	_retirements.append(_encode(resources))
	_reject("reliable original source retirement enqueue rejected")

func capture_owner_reentry(method: String, arguments: Array) -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id() and method in ["cancel_all","cancel_code_owner"])
	_owner_calls.append({"method":method,"arguments":_encode(arguments)})

func _actual_status(path: String) -> int:
	var observation: Dictionary=_observer.threaded_status(path,Engine.get_process_frames() if not _live_feature_call.is_empty() else int(_source_request.site.observation_process_epoch),_generation)
	if observation.get("ok")!=true or observation.get("observation_process_epoch")!=(Engine.get_process_frames() if not _live_feature_call.is_empty() else _source_request.site.observation_process_epoch) or observation.get("bridge_generation")!=_generation or observation.get("status") not in [0,1,2,3]:
		_failed=true; return -1
	_native_observations.append(observation)
	_observations[path]={"status":int(observation.status),"process_epoch":int(observation.observation_process_epoch)}
	if not _live_feature_call.is_empty(): _live_feature_status_ids[path]=_live_feature_call.identity.duplicate(true)
	return int(observation.status)

func execute(request: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _failed: return _reject("wrong Main owner/faulted executor")
	if request==_last_request and not _last_reply.is_empty(): return _last_reply.duplicate(true)
	if request.get("protocol")!=PROTOCOL or request.get("identity",{}).get("bridge_generation")!=_generation or not str(request.get("operation","")).begins_with("feature.") or not (bool(_validate.call(request,&"original_resource_primitive")) if _live_feature_call.is_empty() else bool(_live_feature_native_host.get_ref().validate_live_original_feature_execution(request))): return _reject("source/prefix/single-budget ticket")
	var opcode: String=str(request.operation).trim_prefix("feature.")
	if not request.get("arguments") is Array or request.arguments.size()!=int(OPCODE_ARITY.get(opcode,LIVE_JOB_ARITY.get(opcode,-1))): return _reject("original opcode arity")
	_source_request=request; _native_observations=[]
	var started:=Time.get_ticks_usec()
	var encoded_args: Array=request.arguments
	var args: Array=encoded_args if request.operation=="feature.release_reference" else _decode(encoded_args)
	if _failed: return _reject("expired/unregistered token")
	var value: Variant
	match str(request.operation).trim_prefix("feature."):
		"source_admission_unselected":
			var provider: RefCounted = _original_source_admission.get_ref() if _original_source_admission != null else null
			if provider == null: return _reject("actual_original_Main_admission_provider_missing")
			value = provider.verify_original_unselected_startup_source(args[0])
		"source_admission_prepare":
			var provider: RefCounted = _original_source_admission.get_ref() if _original_source_admission != null else null
			if provider == null: return _reject("actual_original_Main_admission_provider_missing")
			value = provider.prepare_original_profile_source_handoff(args[0],args[1],args[2])
		"source_admission_commit":
			var provider: RefCounted = _original_source_admission.get_ref() if _original_source_admission != null else null
			if provider == null: return _reject("actual_original_Main_admission_provider_missing")
			value = provider.commit_original_profile_source_handoff(args[0],args[1])
		"source_admission_abort":
			var provider: RefCounted = _original_source_admission.get_ref() if _original_source_admission != null else null
			if provider == null: return _reject("actual_original_Main_admission_provider_missing")
			value = provider.abort_original_profile_source_handoff(args[0])
		"source_admission_loading":
			var provider: RefCounted = _original_source_admission.get_ref() if _original_source_admission != null else null
			if provider == null: return _reject("actual_original_Main_admission_provider_missing")
			value = provider.verify_original_loading_boundary(args[0])
		"source_admission_pins":
			var provider: RefCounted = _original_source_admission.get_ref() if _original_source_admission != null else null
			if provider == null: return _reject("actual_original_Main_admission_provider_missing")
			value = provider.verify_actual_loading_pinned_closure(args[0])
		"source_admission_release_pins":
			var provider: RefCounted = _original_source_admission.get_ref() if _original_source_admission != null else null
			if provider == null: return _reject("actual_original_Main_admission_provider_missing")
			value = provider.release_original_loading_pins(args[0])
		"object_get":
			if args.size()!=2 or str(args[1]) not in PROPERTIES or not args[0] is Object: return _reject("object property ABI")
			value=args[0].get(args[1])
		"object_call":
			if args.size()!=3 or str(args[1]) not in METHODS or not args[2] is Array or args[2].size()!=METHODS[str(args[1])]: return _reject("object method ABI")
			if args[1]=="source_application_call":
				if not args[0] is RefCounted or args[0].get_script()!=preload("res://scripts/gameplay/world/world_main_views.gd") or not is_same(args[0].get("_feature"),self) or not args[2][0] is String or not args[2][1] is Array or not preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts(args[2][0],args[2][1]): return _reject("actual fixed World application method ABI")
			if args[1]=="complete_original_source_owner_header":
				if not args[0] is RefCounted or args[0].get_script()!=preload("res://scripts/gameplay/world/world_main_views.gd") or not args[2][0] is Dictionary or not args[2][1] is int or args[2][1]==0 or not args[2][2] is int or args[2][2]<=0: return _reject("actual Loading source owner header ABI")
			if args[0] is Callable:
				if args[1]=="get_object": value=args[0].get_object()
				elif args[1]=="get_method": value=args[0].get_method()
				else: return _reject("Callable token method ABI")
			else:
				if not args[0] is Object or not args[0].has_method(args[1]): return _reject("actual object method missing")
				value=args[0].callv(args[1],args[2])
		"object_script": value=args[0].get_script() if is_instance_valid(args[0]) else null
		"object_valid": value=is_instance_valid(args[0])
		"has_method": value=is_instance_valid(args[0]) and args[0].has_method(args[1])
		"callback_valid": value=args[0] is Callable and args[0].is_valid()
		"callback_invoke":
			if not args[0] is Callable: return _reject("callback reference ABI")
			_facade.set_original_applying_fact(args[1])
			value=args[0].call() if args[0].is_valid() else false
			_facade.clear_original_applying_fact()
		"get_cached_ref": value=ResourceLoader.get_cached_ref(args[0])
		"exists": value=ResourceLoader.exists(args[0],args[1])
		"status":
			value=_actual_status(args[0])
			if not _live_feature_call.is_empty() and not _observe_actual_normal_job_status(args[0],value): return _reject("normal job exact accepted request status dependency")
			var issued: Dictionary=_issued_original_leaf_context(request,args[0])
			if issued.get("invalid",false): return _reject("issued claim status provenance")
			if not issued.is_empty() and value==0:
				if int(_claims.get(args[0],0))<issued.remaining_count: return _reject("issued INVALID responsibility count")
				_claims[args[0]]-=issued.remaining_count
				if _claims[args[0]]==0: _claims.erase(args[0])
				if not _record_original_issued_claim_terminal(issued,"INVALID_RESOURCE",issued.remaining_count,_observations.get(args[0],{}),request): return _reject("issued INVALID range evidence")
		"request":
			if args[1] not in ["Texture2D","AudioStream","Script"] or args[2]!=false: return _reject("original request hint/subthread ABI")
			value=ResourceLoader.load_threaded_request(args[0],args[1],false)
			if value==OK:
				_claims[args[0]]=int(_claims.get(args[0],0))+1
				if not _live_feature_call.is_empty(): _register_actual_normal_job_request(args[0])
		"get":
			var path: String=args[0]
			var status: Dictionary=_observations.get(path,{})
			var issued: Dictionary=_issued_original_leaf_context(request,path)
			if issued.get("invalid",false): return _reject("issued claim get provenance")
			var issued_live: bool = not issued.is_empty() and not _live_feature_call.is_empty()
			var normal: Dictionary = _actual_normal_job_get_context(path) if not issued_live and not _live_feature_call.is_empty() else {}
			if issued_live:
				var observation: Variant = request.get("native_issued_claim_status_observation")
				if not observation is Dictionary or observation.get("ok") != true or observation.get("bridge_generation") != _generation or observation.get("status") not in [2,3] or not observation.get("observation_process_epoch") is int: return _reject("issued LIVE exact Native status dependency")
				status={"status":observation.status,"process_epoch":observation.observation_process_epoch}
			elif not _live_feature_call.is_empty():
				if normal.is_empty(): return _reject("normal job own request and exact terminal status required")
				status=normal.observation
			var closing:=str(request.site.entry_id)=="scripts/features/runtime/feature_resource_preparation.gd::_exit_tree" and bool(_validate.call(request,&"original_final_service_shutdown_join"))
			if int(_claims.get(path,0))<=0 or (not issued_live and (status.get("process_epoch")!=request.site.observation_process_epoch if _live_feature_call.is_empty() else not _actual_live_feature_get_dependency(path))) or (status.get("status") not in [2,3] and not (closing and status.get("status")==1)): return _reject("unproved accepted/terminal original get")
			value=ResourceLoader.load_threaded_get(path)
			_claims[path]-=1
			if _claims[path]==0: _claims.erase(path)
			if not normal.is_empty(): _normal_live_jobs.erase(normal.key)
			if not _record_original_issued_claim_terminal(issued,"GET",1,status,request): return _reject("issued actual get range evidence")
		"adopt_claims":
			if not _claim_transfer.is_valid(): return _reject("actual_nonissued_claim_origin_transfer_not_connected")
			if not bool(_claim_transfer.call(request,args[0],args[1])): return _reject("original transferred claim proof")
			_claims[args[0]]=int(_claims.get(args[0],0))+int(args[1]); value=true
		"valid_resource": value=Registry.valid_resource(args[0],args[1])
		"open_image": value=FileAccess.open(args[0],args[1])
		"issue_resource_lease":
			var lease: RefCounted=Lease.issue(args[0],args[1],args[2],args[3])
			var publication: Dictionary=_publication_registrar.call(lease,args[0]) if lease!=null else {}
			if lease!=null and publication.is_empty(): return _reject("actual feature lease publication registrar")
			if lease!=null and not register_actual_publication(publication,lease): return _reject("actual publication identity")
			value={"main_lease":lease,"resource_publication":publication}
		"retain_publication": value=_retain_publication(args[0])
		"release_retention": value=_release_retention(args[0],args[1])
		"retention_supports_path": value=_retention_supports_path(args[0],args[1],args[2])
		"issue_code_inputs": value=Lease.issue_code_inputs(args[0],args[1],args[2],args[3])
		"begin_code_verification": value=Guard.begin_verification(args[0],args[1],args[2],args[3])
		"begin_export_verification": value=Android.begin(args[0],args[1],args[2])
		"acquire_shader": value=Acquire.acquire_shader(args[0],args[1],args[2],args[3],args[4],args[5],_actual_status)
		"release_reference":
			value=_release_encoded_reference(encoded_args[0])
		"code_scope_check": value=_actual_code_scope(args[0],args[1],args[2])
		"code_inputs_admit":
			value=Guard.begin_verification(args[0],args[1],args[2],args[4]) if _actual_code_scope(args[3],args[4],args[5]) and is_instance_valid(args[2]) else {"success":false,"errors":["code_preparation_owner_or_capacity"],"plan":null}
		"code_publication_admit": value=_actual_code_publication_admit(args)
		"code_publication_owner": value=_actual_code_publication_owner(args[0],args[1],args[2],args[3],args[4])
		"code_publication_apply": value=_actual_code_publication_apply(args[0],args[1],args[2],args[3])
		"code_target_admission": value=_actual_code_target_admission(args)
		"code_target_deliver": value=_actual_code_target_deliver(args)
		"code_image_chunk": value=_actual_code_image_chunk(args[0],args[1],args[2])
		"code_image_close":
			if not args[0] is FileAccess: return _reject("actual code image FileAccess")
			args[0].close(); value=true
		"code_scope_cancel":
			if not args[0] is RefCounted or args[0].get_script()!=preload("res://scripts/features/contracts/loading_preparation_scope.gd"): return _reject("actual code scope cancel")
			args[0].cancel(); value=true
		_: return _reject("unregistered feature opcode")
	if _failed: return _reject("actual primitive failure cannot resume source")
	var reply: Dictionary={"request":request,"executed":true,"result":_encode(value),"started_usec":started,"finished_usec":Time.get_ticks_usec(),"completed_prefix_ordinal":1,"disposition":&"executed",
		"native_observations":_native_observations.duplicate(true),"retirements":_retirements.duplicate(true),"owner_calls":_owner_calls.duplicate(true)}
	if int(reply.finished_usec) > int(request.site.deadline_usec): reply.disposition = &"executed_late"
	if not _issued_claim_facts.is_empty(): reply["issued_claim_facts"]=_issued_claim_facts.duplicate(true)
	_issued_claim_facts.clear()
	_retirements.clear(); _owner_calls.clear(); _source_request={}
	_last_request=request; _last_reply=reply
	return reply

func _release_encoded_reference(descriptor: Dictionary) -> bool:
	var id:=int(descriptor.get("token_id",0))
	if descriptor.get("bridge_generation")!=_generation or not _vault.has(id) or _vault[id].descriptor!=descriptor:
		_failed=true; return false
	var key: String=_vault[id].key
	_object_tokens.erase(key)
	_callback_tokens.erase(id)
	_vault.erase(id)
	# No decoded strong Object local survives here. Actual Main PREDELETE
	# captures retirement before execute seals the original receipt.
	return true

var _next_publication_id := 0
func publish_actual_resource_lease(lease: RefCounted, plan: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _generation <= 0 or _failed or lease == null or lease.get_script() != Lease or lease.is_domain() or plan.get("success") != true or not plan.get("paths") is Array: return {}
	if lease.get("_signature") != plan.get("signature") or lease.get("_catalog_revision") != plan.get("catalog_revision") or lease.get("_enabled_modules") != plan.get("enabled_modules"): return {}
	var paths: Array = lease.get("_resources").keys()
	paths.sort()
	if paths != plan.paths: return {}
	var physical_owner: Node = lease.get("_owner").get_ref() if lease.get("_owner") is WeakRef else null
	if not is_instance_valid(physical_owner) or not Lease.capture_original_physical_owner_leases(physical_owner).has(lease): return {}
	for path: String in paths:
		if not Registry.valid_resource(path,lease.resource_at(path)): return {}
	for id: int in _publications:
		var row: Dictionary = _publications[id]
		if row.lease.get_ref() == lease:
			var prior: Dictionary = row.publication
			return prior.duplicate(true) if prior.get("signature") == plan.signature and prior.get("paths") == paths and prior.get("catalog_revision") == plan.catalog_revision and prior.get("enabled_modules") == plan.enabled_modules else {}
	var next_id: int = _next_publication_id
	for id: int in _publications: next_id = maxi(next_id,id)
	if next_id == 9223372036854775807: return {}
	next_id += 1
	var publication := {"contract_id":"hardcore.feature.resource_publication.v1","publication_id":next_id,"signature":plan.signature,"catalog_revision":plan.catalog_revision,"enabled_modules":plan.enabled_modules.duplicate(),"paths":paths}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if graph == null: return {}
	var captured: Dictionary = graph.capture(publication,true,false)
	if captured.get("success") != true or not register_actual_publication(captured.value,lease): return {}
	_next_publication_id = next_id
	return captured.value

func register_actual_publication(publication: Dictionary, lease: RefCounted) -> bool:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	var id:=int(publication.get("publication_id",0))
	if id<=0 or publication.get("contract_id")!="hardcore.feature.resource_publication.v1" or lease==null or lease.get_script()!=Lease or lease._signature!=publication.get("signature") or lease._catalog_revision!=publication.get("catalog_revision") or lease._enabled_modules!=publication.get("enabled_modules") or not publication.get("paths") is Array: return false
	if _publications.has(id):
		return _publications[id].publication==publication and is_same(_publications[id].lease.get_ref(),lease)
	for path: String in publication.paths:
		if not Registry.valid_resource(path,lease.resource_at(path)): return false
	_publications[id]={"publication":publication.duplicate(true),"lease":weakref(lease)}
	return true

func _retain_publication(publication: Dictionary) -> Dictionary:
	var id:=int(publication.get("publication_id",0))
	if not _publications.has(id): return {"success":false,"retention_id":0}
	var accepted: Dictionary=_publications[id].publication
	var lease: RefCounted=_publications[id].lease.get_ref()
	if publication.get("catalog_revision")!=accepted.catalog_revision or not publication.get("paths") is Array or not publication.get("enabled_modules") is Array: return {"success":false,"retention_id":0}
	if lease==null:
		# A withdrawn original may already have released its full lease. A live
		# genuine subset lease can narrow again using only refs it still holds.
		for held: Dictionary in _retentions.values():
			if held.publication_id!=id: continue
			var covers:=true
			for path: Variant in publication.paths:
				if path not in held.paths: covers=false
			for module_id: Variant in publication.enabled_modules:
				if module_id not in held.lease._enabled_modules: covers=false
			if covers:
				lease=held.lease
				break
	if lease==null: return {"success":false,"retention_id":0}
	# Exact original retained subset entitlement: closed selected paths/modules
	# may narrow an already-accepted publication, never grant another path.
	for selected: Variant in publication.enabled_modules:
		if selected not in accepted.enabled_modules: return {"success":false,"retention_id":0}
	for path: Variant in publication.paths:
		if path not in accepted.paths or not Registry.valid_resource(path,lease.resource_at(path)): return {"success":false,"retention_id":0}
	if publication.get("signature")!=JSON.stringify([publication.catalog_revision,publication.enabled_modules,publication.paths]).sha256_text(): return {"success":false,"retention_id":0}
	if publication.signature!=lease._signature:
		# Same original retain_subset -> issue algorithm and diagnostics. The
		# physical subset owns exactly selected refs, never a full parent lease.
		var owner: Node=lease._owner.get_ref() if lease._owner!=null else null
		if not is_instance_valid(owner) or owner.is_queued_for_deletion(): return {"success":false,"retention_id":0}
		var resources: Dictionary={}
		for path: String in publication.paths: resources[path]=lease.resource_at(path)
		var plan: Dictionary={"success":true,"paths":publication.paths,"enabled_modules":publication.enabled_modules,"catalog_revision":publication.catalog_revision,"signature":publication.signature}
		lease=Lease.issue(plan,resources,owner,{"requested":0,"cache_hits":resources.size(),"threaded_completed":0,"joined_requests":0})
		if lease==null: return {"success":false,"retention_id":0}
	_next_retention+=1
	_retentions[_next_retention]={"publication_id":id,"paths":publication.paths.duplicate(),"lease":lease}
	return {"success":true,"retention_id":_next_retention}

func _release_retention(publication_id: int, retention_id: int) -> bool:
	if not _retentions.has(retention_id) or _retentions[retention_id].publication_id!=publication_id: return false
	_retentions.erase(retention_id)
	return true

func _retention_supports_path(publication_id: int, retention_id: int, path: String) -> bool:
	return _retentions.has(retention_id) and _retentions[retention_id].publication_id==publication_id and path in _retentions[retention_id].paths and Registry.valid_resource(path,_retentions[retention_id].lease.resource_at(path))

const LIVE_JOB_ARITY := {"code_scope_check":3,"code_inputs_admit":6,"code_publication_admit":8,"code_publication_owner":5,"code_publication_apply":4,"code_target_admission":6,"code_target_deliver":6,"code_image_chunk":3,"code_image_close":1,"code_scope_cancel":1}
# Association metadata for the existing _claims. No additional task/queue or
# retrieval entitlement: one row is born only after an actual successful request
# and dies at that claim's actual terminal GET/INVALID.
var _normal_live_jobs: Dictionary = {}
func _live_identity_key(identity: Dictionary) -> String:
	if identity.size()!=2 or not identity.get("bridge_generation") is int or identity.bridge_generation<=0 or not identity.get("op_sequence") is int or identity.op_sequence<=0: return ""
	return "%d:%d"%[identity.bridge_generation,identity.op_sequence]
func _register_actual_normal_job_request(path: String) -> void:
	var identity: Dictionary = _live_feature_call.identity
	_normal_live_jobs[_live_identity_key(identity)] = {"identity":identity.duplicate(true),"path":path,"status_identity":{},"observation":{}}
func _normal_job_dependency(path: String, actual_caller: Dictionary = {}) -> Dictionary:
	var found: Dictionary = {}
	var caller: Dictionary = _live_feature_call if actual_caller.is_empty() else actual_caller
	for dependency: Dictionary in caller.get("dependencies",[]):
		if dependency.get("after") != "s_committed" or not dependency.get("identity") is Dictionary: continue
		var row: Dictionary = _normal_live_jobs.get(_live_identity_key(dependency.identity),{})
		if row.is_empty() or row.identity != dependency.identity or row.path != path: continue
		if not found.is_empty(): return {}
		found = row
	return found
func _observe_actual_normal_job_status(path: String, status_value: int) -> bool:
	var row: Dictionary = _normal_job_dependency(path)
	if row.is_empty(): return true # Original pre-request status creates no right.
	row.status_identity = _live_feature_call.identity.duplicate(true)
	row.observation = _observations[path].duplicate(true)
	if status_value == 0:
		if int(_claims.get(path,0)) <= 0: return false
		_claims[path] -= 1
		if _claims[path] == 0: _claims.erase(path)
		_normal_live_jobs.erase(_live_identity_key(row.identity))
	return true
func _actual_normal_job_get_context(path: String, actual_caller: Dictionary = {}) -> Dictionary:
	var caller: Dictionary = _live_feature_call if actual_caller.is_empty() else actual_caller
	var row: Dictionary = _normal_job_dependency(path,caller)
	if row.is_empty() or row.observation.get("status") not in [2,3]: return {}
	var matched: bool = false
	for dependency: Dictionary in caller.get("dependencies",[]):
		if dependency.get("after") == "s_committed" and dependency.get("identity") == row.status_identity: matched = true
	if not matched: return {}
	return {"key":_live_identity_key(row.identity),"observation":row.observation}
func verify_actual_original_normal_job_execution(caller: Dictionary) -> bool:
	# Native calls this before entering the actual leaf, using its own frozen
	# pending caller. It is read-only and neither borrows nor retires issued work.
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _failed or not caller.get("args") is Array or caller.args.size()!=1 or not caller.args[0] is String or not caller.get("dependencies") is Array: return false
	var path: String=caller.args[0]
	if caller.get("op")==&"feature.get": return not _actual_normal_job_get_context(path,caller).is_empty()
	if caller.get("op")!=&"feature.status": return false
	if not _normal_job_dependency(path,caller).is_empty(): return true
	# The original pre-request observation owns no user token and has no
	# dependencies. Only this sealed Coordinator PC issues this responsibility
	# key. Its Main status body never decrements an issued or normal claim.
	var key: String=str(caller.get("order_key",""))
	return caller.dependencies.is_empty() and key.begins_with("feature:") and (":job:"+path+":") in key and key.ends_with(":PRE_STATUS")
func _actual_code_scope(scope: Variant, consumer: Variant, generation: int) -> bool:
	return scope is RefCounted and scope.get_script()==preload("res://scripts/features/contracts/loading_preparation_scope.gd") and is_instance_valid(consumer) and consumer is Node and bool(scope.valid_for(consumer,generation))
func _actual_code_publication_owner(publisher: Variant, scope: Variant, consumer: Variant, generation: int, sequence: int) -> bool:
	return _actual_code_scope(scope,consumer,generation) and is_instance_valid(publisher) and publisher is Node and is_same(_facade.get_tree().root.get_node_or_null("ContentLayers"),publisher) and publisher.has_method("is_internal_code_publication_boundary_current") and bool(publisher.is_internal_code_publication_boundary_current(sequence))
func _actual_code_publication_admit(args: Array) -> Dictionary:
	var publisher: Node = _facade.get_tree().root.get_node_or_null("ContentLayers")
	if not _actual_code_publication_owner(publisher,args[3],args[4],args[5],args[6]) or not args[2] is Callable or args[2].get_object()!=publisher or args[2].get_method()!=&"_publish_internal_code_catalogue" or str(args[0]).length()!=64 or args[1]<=0 or args[1]>268435456: return {"success":false,"errors":["code_publication_owner_shape_or_loading_scope"]}
	var verifier: RefCounted
	if OS.get_name()=="Android":
		if publisher.code_preparation_export_contract()!=args[7] or publisher.code_preparation_export_seal_sha256()!=args[0]: return {"success":false,"errors":["android_unregistered_export_contract"]}
		verifier=Android.begin(args[7],args[0],true)
		if verifier==null: return {"success":false,"errors":["android_publication_contract_rejected"]}
	elif OS.get_name()!="Windows" or not args[7].is_empty(): return {"success":false,"errors":["code_publication_platform_unknown"]}
	return {"success":true,"errors":[],"publisher":publisher,"export_verifier":verifier}
func _actual_code_publication_apply(callback: Variant, fact: Dictionary, publisher: Variant, sequence: int) -> bool:
	if not callback is Callable or not callback.is_valid() or callback.get_object()!=publisher or callback.get_method()!=&"_publish_internal_code_catalogue" or not _actual_code_publication_owner(publisher,fact.get("scope"),fact.get("consumer"),fact.get("generation",-1),sequence): return false
	_facade.set_original_applying_fact(fact)
	var success: bool = bool(callback.call())
	_facade.clear_original_applying_fact()
	return success and _actual_code_publication_owner(publisher,fact.scope,fact.consumer,fact.generation,sequence)
func _actual_code_target_admission(args: Array) -> Dictionary:
	var result: Dictionary = {"success":false,"resource":null,"started":false,"mode":"","error":"code_target_source_or_owner_changed","admission_usec":0}
	var began: int=Time.get_ticks_usec()
	var plan: Variant=args[0]; var lease: Variant=args[4]; var path: String=args[5]
	if not plan is RefCounted or plan.get_script()!=Guard or not lease is RefCounted or lease.get_script()!=Lease or not _actual_code_scope(args[1],args[2],args[3]) or plan.target_path()!=path: return result
	var current: Dictionary=plan.revalidate_admission_sources()
	if not current.get("success",false) or not _actual_code_scope(args[1],args[2],args[3]) or not lease.valid_for_code(plan): return result
	result.admission_usec=Time.get_ticks_usec()-began
	# No callback/await/frame exists between revalidation and this request.
	result.resource=ResourceLoader.get_cached_ref(path)
	if result.resource!=null: result.success=true; result.mode="cache_hits"; result.error=""; return result
	if _actual_status(path)!=0: result.error="code_target_external_native_job_unproved"; return result
	var error: int=ResourceLoader.load_threaded_request(path,"Script",false)
	if error!=OK: result.error="code_target_request_failed:"+path; return result
	_claims[path]=int(_claims.get(path,0))+1; _register_actual_normal_job_request(path)
	result.success=true; result.started=true; result.error=""; return result
func _actual_code_target_deliver(args: Array) -> bool:
	var plan: Variant=args[0]; var lease: Variant=args[4]; var target: Variant=args[5]
	return plan is RefCounted and plan.get_script()==Guard and lease is RefCounted and lease.get_script()==Lease and _actual_code_scope(args[1],args[2],args[3]) and plan.valid_target(target) and lease.valid_for_code(plan) and lease.attach_loaded_code_resource(plan,target,args[2],_facade)
func _actual_code_image_chunk(file: Variant, expected: int, maximum: int) -> Dictionary:
	if not file is FileAccess or maximum!=262144 or file.get_length()!=expected: return {"success":false,"bytes":PackedByteArray(),"done":false}
	var remaining: int=file.get_length()-file.get_position()
	var bytes: PackedByteArray=file.get_buffer(mini(maximum,remaining)) if remaining>0 else PackedByteArray()
	return {"success":bytes.size()==mini(maximum,remaining),"bytes":bytes,"done":remaining==0}

func close_main() -> bool:
	if not _normal_live_jobs.is_empty(): return false
	# Caller supplies global Host/consumer/prefix quiescence; retained roots,
	# accepted claims or callback retirement records never disappear on close.
	if not _command_reference_loans.is_empty() or not _issued_claim_records.is_empty() or not _issued_live_pending_paths.is_empty() or not _issued_claim_facts.is_empty() or not _claims.is_empty() or not _retirements.is_empty() or not _owner_calls.is_empty() or not _retentions.is_empty(): return false
	for entry: Dictionary in _vault.values():
		if not entry.weak: return false
	return true

func retire_after_owner_fault(ticket: Dictionary) -> Dictionary:
	# This is the original FINAL shutdown join boundary, never scene retirement.
	# Native must prove S stopped, the executed prefix/outbox obligations drained,
	# and all physical consumers retired. It is not recovery/admission/readiness.
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not _failed or not bool(_validate.call(ticket,&"feature_owner_final_fault_retirement")):
		return {"success":false,"errors":["unproved_final_owner_fault_quiescence"]}
	for flag: String in ["source_stopped","prefix_drained","outbox_drained","consumers_retired","global_shutdown_join"]:
		if ticket.get(flag)!=true: return {"success":false,"errors":["missing_final_fault_proof:"+flag]}
	if ticket.get("bridge_generation")!=_generation or not ticket.get("observation_process_epoch") is int:
		return {"success":false,"errors":["wrong_final_fault_generation_or_observation"]}
	var joined:=0
	var missing:=0
	var observations: Array=[]
	for path: String in _claims.keys():
		var observation: Dictionary=_observer.threaded_status(path,ticket.observation_process_epoch,_generation)
		if observation.get("ok")!=true or observation.get("observation_process_epoch")!=ticket.observation_process_epoch or observation.get("bridge_generation")!=_generation or observation.get("status") not in [0,1,2,3]:
			return {"success":false,"errors":["actual_final_claim_observation_failed"],"joined":joined,"missing":missing}
		observations.append(observation)
		var remaining: int=int(_claims[path])
		if observation.status in [1,2,3]:
			for index in range(remaining):
				ResourceLoader.load_threaded_get(path)
				joined+=1
		else:
			missing+=remaining # Same original INVALID_RESOURCE missing classification.
		_claims.erase(path)
	# These are associations for the physical claims just fully joined above.
	# Only the proven original FINAL fault boundary can retire them together;
	# ordinary close still requires each real GET/INVALID completion.
	_normal_live_jobs.clear()
	_facade.clear_original_applying_fact()
	_retentions.clear()
	# Actual original Lease PREDELETE may hand actual refs to the facade. Drop
	# those final roots only after the native proof has retired all consumers.
	# Never pretend a running S coordinator accepted these final retirements.
	var released:=0
	while not _vault.is_empty():
		var id: int=_vault.keys()[0]
		var key: String=_vault[id].key
		_object_tokens.erase(key)
		_callback_tokens.erase(id)
		_vault.erase(id)
		released+=1
		_retirements.clear()
	_publications.clear()
	_owner_calls.clear()
	_last_request={}; _last_reply={}; _source_request={}
	return {"success":true,"errors":[],"joined":joined,"missing":missing,"released_actual_roots":released,"native_observations":observations}

## Appended to actual FeatureResourceMainPrimitives; same _claims owns all
## physical ResourceLoader obligations. This never issues a loader request.
var _issued_claim_host: Object
var _issued_claim_records: Dictionary={}
var _issued_live_pending_paths: Dictionary={} # Main-only index of exact record remaining ranges; never an admission identity.
func original_live_feature_path_has_issued_responsibility(path: String) -> bool:
	return OS.get_thread_caller_id()==OS.get_main_thread_id() and int(_issued_live_pending_paths.get(path,0))>0
var _issued_claim_facts: Array[Dictionary]=[]
func configure_original_issued_claim_bridge(host: Object) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _issued_claim_host!=null: return false
	for method: String in ["offer_claim_transfer","confirm_origin_released","bind_original_main_feature_claim_producer"]:
		if host==null or not host.has_method(method): return false
	if not host.bind_original_main_feature_claim_producer(self,get_script().get_source_code().sha256_text()): return false
	_issued_claim_host=host;return true
func offer_original_warm_issued_claim(identity: Dictionary, evidence: Dictionary, helper: RefCounted) -> Dictionary:
	if _issued_claim_host==null or OS.get_thread_caller_id()!=OS.get_main_thread_id(): return {"status":"INVALID"}
	if helper==null or evidence.size()!=11 or identity.size()!=4 or evidence.get("identity")!=identity or evidence.get("actual_feature_main_id")!=get_instance_id() or evidence.get("actual_helper_id")!=helper.get_instance_id() or helper.get("_loading_claims").get(evidence.get("path"))!=true or int(evidence.get("claim_count",0))<=0: return {"status":"INVALID"}
	var key: String=IssuedClaimIdentity.key(identity)
	if not _issued_claim_records.has(key):
		var path: String=evidence.path
		var count: int=evidence.claim_count
		# Exact original physical accounting formerly performed by adopt_claims.
		# It happens before Native can publish OFFERED to S. No get/request is
		# executed; Main origin freezes consumption while transfer is pending.
		_claims[path]=int(_claims.get(path,0))+count
		_issued_claim_records[key]={"identity":identity.duplicate(true),"evidence":evidence.duplicate(true),"consumed":0,"offered":false,"terminal_facts":[]}
		_issued_live_pending_paths[path]=int(_issued_live_pending_paths.get(path,0))+count
	var record: Dictionary=_issued_claim_records[key]
	if var_to_bytes(record.evidence)!=var_to_bytes(evidence): return {"status":"INVALID"}
	var actual: Dictionary=_issued_claim_host.offer_claim_transfer(identity,evidence)
	if actual.get("status")=="INVALID" and not record.offered:
		# Native guarantees INVALID admitted no responsibility. Restore only
		# this new bookkeeping portion; original Main claim remains owned.
		_claims[evidence.path]-=evidence.claim_count
		_issued_live_pending_paths[evidence.path]-=evidence.claim_count
		if _issued_live_pending_paths[evidence.path]==0: _issued_live_pending_paths.erase(evidence.path)
		if _claims[evidence.path]==0: _claims.erase(evidence.path)
		_issued_claim_records.erase(key)
	elif actual.get("state") in ["OFFERED","ACCEPTED","ORIGIN_RELEASED","TERMINAL"]: record.offered=true
	return actual
func verify_original_main_issued_claim_offer(identity: Dictionary, evidence: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id(): return {"success":false}
	var key: String=IssuedClaimIdentity.key(identity)
	if not _issued_claim_records.has(key) or var_to_bytes(_issued_claim_records[key].evidence)!=var_to_bytes(evidence) or int(_claims.get(evidence.path,0))<evidence.claim_count-_issued_claim_records[key].consumed: return {"success":false}
	return {"success":true,"identity":identity,"evidence":evidence,"actual_feature_main_id":get_instance_id(),"physical_remaining":evidence.claim_count-_issued_claim_records[key].consumed}
func original_issued_claim_transfer_state(identity: Dictionary) -> Dictionary:
	var key: String=IssuedClaimIdentity.key(identity)
	if _issued_claim_host==null or not _issued_claim_records.has(key): return {"status":"INVALID"}
	# Idempotent offer observes the same existing caster attached record; it
	# never re-registers the physical counter or creates another offer.
	return _issued_claim_host.offer_claim_transfer(identity,_issued_claim_records[key].evidence)
func confirm_original_warm_claim_origin_released(identity: Dictionary) -> Dictionary:
	return _issued_claim_host.confirm_origin_released(identity)
func _issued_original_leaf_context(request: Dictionary, path: String) -> Dictionary:
	var context: Variant=request.get("native_issued_claim_responsibility")
	if context==null: return {} # Existing unrelated original resource path.
	if not context is Dictionary or context.size()!=7 or context.get("path")!=path or not context.get("identity") is Dictionary: return {"invalid":true}
	var key: String=IssuedClaimIdentity.key(context.identity)
	if not _issued_claim_records.has(key): return {"invalid":true}
	var record: Dictionary=_issued_claim_records[key]
	if context.get("original_first_claim_ordinal")!=record.consumed or context.get("remaining_count")!=record.evidence.claim_count-record.consumed or context.get("owner_session_id")!=record.evidence.owner_descriptor.owner_session_id: return {"invalid":true}
	return context
func _record_original_issued_claim_terminal(context: Dictionary, kind: String, count: int, observation: Dictionary, request: Dictionary) -> bool:
	if context.is_empty(): return true
	if context.get("invalid",false) or count<=0: return false
	var key: String=IssuedClaimIdentity.key(context.identity)
	var record: Dictionary=_issued_claim_records[key]
	if count>record.evidence.claim_count-record.consumed: return false
	var actual: Dictionary={"contract_id":"hardcore.feature.issued_claim.physical_terminal.v1","identity":context.identity,"original_first_claim_ordinal":record.consumed,"claim_count":count,"kind":kind,"path":context.path,"operation_identity":request.identity,"source_site":request.site,"observation":observation.duplicate(true),"actual_feature_main_id":get_instance_id()}
	# GET is recorded after the one original ResourceLoader.get regardless of
	# null/FAILED result. INVALID accounts the original remaining range, without
	# another get. Native verifies the actual bound original leaf execution.
	record.consumed+=count;record.terminal_facts.append(actual);_issued_claim_facts.append(actual)
	_issued_live_pending_paths[context.path]-=count
	if _issued_live_pending_paths[context.path]==0: _issued_live_pending_paths.erase(context.path)
	return true
func acknowledge_original_issued_claim_terminal_delivery(identity: Dictionary) -> bool:
	# Called only by the existing Main reply/journal ACK boundary after Native
	# has folded all terminal facts and Source exact queue absence into TERMINAL.
	var key: String=IssuedClaimIdentity.key(identity)
	if not _issued_claim_records.has(key): return false
	var actual: Dictionary=original_issued_claim_transfer_state(identity)
	if actual.get("state")!="TERMINAL" or actual.get("evidence")!=_issued_claim_records[key].evidence: return false
	_issued_claim_records.erase(key);return true

const IssuedClaimIdentity := preload("res://scripts/features/runtime/issued_claim_identity.gd")

var _live_feature_native_host: WeakRef
var _live_feature_call: Dictionary={}
var _live_feature_status_ids: Dictionary={}
func bind_original_live_feature_native(host: Object) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _live_feature_native_host!=null or host==null or not host.is_class("HardCoreSimulationHost"): return false
	_live_feature_native_host=weakref(host);return true
func execute_original_live_feature(execution: Dictionary, caller: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _live_feature_native_host==null or _live_feature_native_host.get_ref()==null or not _live_feature_call.is_empty(): return {"executed":false,"error":"actual_live_Feature_native_owner_required"}
	if execution.get("identity")!=caller.get("identity") or execution.get("operation")!=caller.get("op") or execution.get("arguments")!=caller.get("args") or execution.get("main_prefix")!=caller.get("main_prefix"): return {"executed":false,"error":"actual_live_Feature_two_wire_identity"}
	_live_feature_call=caller.duplicate(true)
	var actual: Dictionary=execute(execution)
	_live_feature_call={}
	return actual
func _actual_live_feature_get_dependency(path: String) -> bool:
	return not _actual_normal_job_get_context(path).is_empty()


func bind_original_main_source_admission(provider: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or provider==null or _original_source_admission!=null: return false
	if provider.get_script()!=load("res://scripts/gameplay/source/main_source_admission.gd") or provider.get("_main_primitives")!=self or provider.get("_primitive_facade")!=_facade: return false
	var gate: Variant=provider.get("_gate")
	if not gate is RefCounted or gate.state()!="MAIN" or provider.get("_committed")!=false: return false
	_original_source_admission=weakref(provider)
	return true

func handoff_original_physical_leases(previous: Node, leases: Array, prepared: Dictionary) -> Dictionary:
	# Only the already Native-admitted bootstrap commit may transfer physical
	# reference ownership. Empty input is not a proof of an empty old world.
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _failed or _original_source_admission==null or not _physical_owner_handoff.is_empty(): return {"success":false,"error":"actual_once_physical_commit_required"}
	var admission: RefCounted=_original_source_admission.get_ref()
	if admission==null or not is_instance_valid(previous) or not is_instance_valid(_facade): return {"success":false,"error":"physical_commit_owner_absent"}
	if _source_request.get("operation")!="feature.source_admission_commit" or _source_request.get("site",{}).get("clock_epoch")!=0 or _source_request.site.get("bootstrap")!=true: return {"success":false,"error":"physical_commit_outside_original_Native_operation"}
	if admission.get("_prepared")!=prepared or admission.get("_committed")!=false or admission.get("_gate").state()!="PREPARED" or admission.get("_legacy_resources")!=previous or admission.get("_primitive_facade")!=_facade or _facade.get("_primitives")!=self: return {"success":false,"error":"physical_commit_prepared_identity"}
	var arguments: Array=_source_request.get("arguments",[])
	if arguments.size()!=2 or not arguments[0] is Dictionary or arguments[0].get("receipt")!=prepared: return {"success":false,"error":"physical_commit_native_request_receipt"}
	var content: Node=admission.get("_content")
	if not is_instance_valid(content) or content.get("_feature_resource_service")!=previous or previous.get_script()!=load("res://scripts/features/runtime/feature_resource_preparation.gd"): return {"success":false,"error":"physical_commit_registered_legacy_owner"}
	var idle: Dictionary=admission.capture_original_resource_idle_state()
	if idle.get("success")!=true or previous.is_processing() or previous.is_physics_processing(): return {"success":false,"error":"physical_commit_old_owner_not_quiescent"}
	var ids: Array[int]=[]
	for value: Variant in leases:
		if not value is RefCounted or value.get_script()!=Lease: return {"success":false,"error":"physical_commit_foreign_lease"}
		ids.append(value.get_instance_id())
	var receipt: Dictionary={"success":true,"bridge_generation":_generation,"operation_identity":_source_request.identity.duplicate(true),"prepared_serial":prepared.get("serial"),"previous_owner_id":previous.get_instance_id(),"new_owner_id":_facade.get_instance_id(),"content_id":content.get_instance_id(),"physical_lease_ids":ids}
	# Complete-set validation and owner changes happen synchronously on Main.
	# No resource is acquired/freed, no queued=true acceptance is invented.
	if not Lease.rebind_original_physical_owner(previous,_facade,leases): return {"success":false,"error":"physical_commit_incomplete_actual_lease_set"}
	_physical_owner_handoff=receipt
	return receipt.duplicate(true)

func verify_original_physical_facade_switch(content: Node, previous: Node, successor: Node) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _physical_owner_handoff.is_empty() or _source_request.get("operation")!="feature.source_admission_commit": return false
	return is_instance_valid(content) and is_instance_valid(previous) and successor==_facade and _physical_owner_handoff.operation_identity==_source_request.get("identity") and content.get_instance_id()==_physical_owner_handoff.content_id and previous.get_instance_id()==_physical_owner_handoff.previous_owner_id and successor.get_instance_id()==_physical_owner_handoff.new_owner_id and Lease.capture_original_physical_owner_leases(previous).is_empty()

# Main command custody only. Actual resources stay in the original vault and
# their Source proxies release them through the existing reference FIFO.
var _command_reference_loans: Dictionary = {}
var _last_command_loan_id := 0

func _actual_owned_reference_value(value: Variant, refs: Array, depth: int) -> Dictionary:
	if value == null: return {"success":true,"value":null}
	if depth > 64 or value is Signal: return {"success":false}
	if value is Object or value is Callable:
		if value is Object and not is_instance_valid(value): return {"success":false}
		for prior: Dictionary in refs:
			if (value is Object and prior.value is Object and is_same(value,prior.value)) or (value is Callable and prior.value is Callable and value == prior.value): return {"success":true,"value":prior.descriptor}
		_next_token += 1
		var token: int = _next_token
		var types: Array[String] = []
		for kind: String in ["Object","Node","SceneTree","Resource","Script","PackedScene","SceneState","Control","FileAccess"]:
			if value is Object and value.is_class(kind): types.append(kind)
		if value is Callable: types.append("Callable")
		var descriptor: Dictionary = {"contract_id":"feature.main.reference.v1","token_id":token,"object_id":value.get_instance_id() if value is Object else hash(value),"bridge_generation":_generation,"native_types":types}
		# A unique key cannot erase another token's stable object index when this
		# loan later receives its genuine Source release_reference.
		_vault[token] = {"value":weakref(value) if value is Node or value is SceneTree else value,"weak":value is Node or value is SceneTree,"key":"owned_reference:%d"%token,"descriptor":descriptor.duplicate(true)}
		refs.append({"value":value,"descriptor":descriptor})
		return {"success":true,"value":descriptor}
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			var encoded: Dictionary = _actual_owned_reference_value(item,refs,depth+1)
			if encoded.get("success") != true: return {"success":false}
			result.append(encoded.value)
		return {"success":true,"value":result}
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			if key is Object or key is Callable or key is Signal: return {"success":false}
			var encoded: Dictionary = _actual_owned_reference_value(value[key],refs,depth+1)
			if encoded.get("success") != true: return {"success":false}
			result[key] = encoded.value
		return {"success":true,"value":result}
	return {"success":true,"value":value}

func capture_original_feature_command_loans(command_id: int, arguments: Array, scene: Node) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _failed or _generation <= 0 or command_id != _last_command_loan_id+1 or _command_reference_loans.has(command_id): return {"success":false,"status":"INVALID"}
	if scene != null and (not is_instance_valid(scene) or not scene.is_inside_tree() or scene != _facade.get_tree().current_scene): return {"success":false,"status":"INVALID","error":"actual_original_caller_scene_required"}
	var refs: Array = []
	var encoded: Dictionary = _actual_owned_reference_value([arguments,scene],refs,0)
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if encoded.get("success") != true or graph.validate(encoded.get("value"),false).get("success") != true:
		# These fresh tokens have never left Main. Roll back only this rejected
		# capture, with the actual Objects still held by the caller's arguments.
		for row: Dictionary in refs: _vault.erase(row.descriptor.token_id)
		return {"success":false,"status":"INVALID","error":"actual_command_loan_graph"}
	var row: Dictionary = {"arguments":encoded.value[0],"scene":encoded.value[1],"source_imported":false}
	_command_reference_loans[command_id] = row
	_last_command_loan_id = command_id
	return {"success":true,"arguments":row.arguments.duplicate(true),"scene":row.scene,"loan_id":command_id}

func acknowledge_actual_feature_command_import(command_id: int, arguments: Array, scene: Variant) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _command_reference_loans.has(command_id): return false
	var row: Dictionary = _command_reference_loans[command_id]
	if row.arguments != arguments or row.scene != scene: return false
	row.source_imported = true
	return true

func retire_actual_feature_command_loan_association(command_id: int) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _command_reference_loans.has(command_id) or _command_reference_loans[command_id].source_imported != true: return false
	# This retires a command association, never its still owned physical tokens.
	# It is called only after the same Source's result-consumption ACK fact.
	_command_reference_loans.erase(command_id)
	return true
