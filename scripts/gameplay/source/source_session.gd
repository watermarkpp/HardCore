extends RefCounted
const PersistentPathSlot := preload("res://scripts/gameplay/world/source_session_path_slot.gd")
var _path_slot: RefCounted

const SessionBudget := preload("res://scripts/gameplay/source/source_session_budget.gd")
const SessionClock := preload("res://scripts/gameplay/source/source_session_clock.gd")
const Router := preload("res://scripts/gameplay/source/source_session_actor_router.gd")
const Transport := preload("res://scripts/gameplay/source/source_session_transport.gd")
const ServiceActors := preload("res://scripts/gameplay/enemy/enemy_owner_service_actor_access.gd")
const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
const Journal := preload("res://scripts/gameplay/world/world_original_event_journal.gd")
const PrefixTransport := preload("res://scripts/gameplay/world/world_resource_prefix_transport.gd")
const PersistenceBudget := preload("res://scripts/gameplay/world/world_profile_budget_port.gd")
const FeatureFactory := preload("res://scripts/features/runtime/feature_resource_owner_factory.gd")
const ProfileFactory := preload("res://scripts/gameplay/profile/profile_owner_factory.gd")
const Engagement := preload("res://scripts/gameplay/world/world_owner_engagement_window.gd")
const EnemyShared := preload("res://scripts/gameplay/world/world_owner_enemy_shared.gd")
const EnemyAudio := preload("res://scripts/gameplay/world/world_owner_enemy_audio_shared.gd")

var _owner := OS.get_thread_caller_id()
var _host: Object
var _id := 0
var _boot: Dictionary
var _services: Dictionary
var _faults: Array[Dictionary] = []
var _phase := "ADMITTING"
var _profile_commit_attempted := false
var _profile_commit_acknowledged := false
var _actual_admission_scope: Dictionary = {}
var _core: WeakRef
var _actor_router: RefCounted
var _clock: RefCounted
var _budget: RefCounted
var _service_actors: RefCounted
var _journal: RefCounted
var _engagement: RefCounted
var _enemy_shared: RefCounted
var _enemy_audio: RefCounted
var _global_random: RefCounted
var _feature_scope: RefCounted
var _profile_scope: RefCounted
var _profile_receipt_scope: RefCounted
var _persistent_process_origins: Dictionary = {}
var _last_profile_node_frame := -1
var _last_profile_receipt_frame := -1
var _persistent_world_context: Dictionary = {}
var _persistent_entry_ordinal := 0
var _feature: Dictionary
var _profile: Dictionary
var _transport: RefCounted
var _loading_transport: RefCounted
var _loading_site: Dictionary
var _live_consumers: Dictionary = {}
var _live_tickets: Dictionary = {}
var _resource_commit_epoch := -1
var _pins: Dictionary = {}
var _adopt_count := 0
var _release_count := 0

func owner_thread_id() -> int: return _owner
func fault(code: String, details: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_faults.append({"code":code,"details":details,"source_phase":_phase,"wall_usec":Time.get_ticks_usec()})
	_services.failure.record_fatal_source_fault(code, details)
func is_faulted() -> bool: return not _faults.is_empty()
func cold_resource_calls_allowed() -> bool: return _phase == "LOADING" and not is_faulted()

func initialize(host: Object, boot: Dictionary, services: Dictionary) -> bool:
	if _host != null or OS.get_thread_caller_id() == OS.get_main_thread_id(): return false
	_host = host
	_boot = boot
	_services = services
	_id = int(boot.session_id)
	_phase = "LOADING"
	_global_random = ClassDB.instantiate("HardCoreGameplayGlobalRandom")
	if _global_random == null or not _global_random.initialize_handoff(boot.global_random_handoff): return _reject("original_global_random_handoff_rejected", {})
	_journal = Journal.new(self, int(host.capabilities().bridge_generation), int(boot.journal_generation))
	_engagement = Engagement.new()
	if not _engagement.configure_original_handoff(boot.engagement_handoff): return _reject("engagement_handoff_rejected", {})
	_enemy_shared = EnemyShared.new()
	if not _enemy_shared.configure_original_handoff(boot.enemy_shared_handoff): return _reject("enemy_shared_handoff_rejected", {})
	_clock = SessionClock.new(self, host, boot.project_settings)
	_actor_router = Router.new(self)
	_service_actors = ServiceActors.new()
	if not _service_actors.configure_owner(_actor_router, _actor_router): return _reject("session_service_access_rejected", {})
	_budget = SessionBudget.new()
	if not _budget.configure_owner({"Engine":_clock,"Time":_clock,"ProjectSettings":_clock,"phase":_clock}, _service_actors) or not _budget.configure_resource_continuations(_resource_failure) or not _budget.configure_session(_id, cold_resource_calls_allowed): return _reject("session_budget_rejected", {})
	if not configure_original_persistent_process_scopes(boot.original_persistent_process_scopes): return _reject("persistent_source_scope_rejected", {})
	if boot.feature_process_scope != _persistent_process_origins.feature.scope or boot.profile_process_scope != _persistent_process_origins.profile.scope: return _reject("persistent_source_scope_publication_mismatch", {})
	for scope: RefCounted in [_feature_scope,_profile_scope,_profile_receipt_scope]:
		if not _service_actors.register_process_owner(scope): return _reject("persistent_source_scope_registration_rejected", {})
	var application_bindings: Script = load("res://scripts/gameplay/source/source_application_providers.gd")
	if not application_bindings.bind_original_session_services(self,host,_services): return _reject("actual_application_owners_not_bound_to_unique_Session",{})
	_loading_transport = PrefixTransport.new(self, host)
	_transport = Transport.new(self, host, _loading_transport)
	_feature = FeatureFactory.create(self, _transport, _budget, _clock, boot.feature_resources, _feature_scope)
	if not _feature.get("success", false): return _reject("source_feature_factory_rejected", _feature)
	if not _services.admission.bind_original_source_endpoint(_feature.primitives): return _reject("actual_source_admission_endpoint_bind_rejected",{})
	if not _feature.coordinator.has_method("configure_original_issued_claim_bridge") or not _feature.coordinator.configure_original_issued_claim_bridge(host,self): return _reject("actual_original_issued_claim_bridge_missing",{})
	_loading_site = boot.loading_source_site
	_persistent_world_context = _loading_site.world_context
	if not host.bind_original_world_context(_loading_site.world_context): return _reject("actual_loading_source_world_rejected",{})
	var scope: Dictionary = boot.get("source_admission_scope",{})
	if scope.get("state") != "PREPARED" or scope.get("receipt") != boot.get("source_commit_receipt") or scope.get("publication") != boot.get("profile_state_handoff") or scope.get("world_context") != _loading_site.world_context: return _reject("actual_same_Main_prepared_admission_scope_required",{})
	var claimed: Dictionary = host.claim_original_source_admission_scope(int(scope.get("scope_id",0)))
	if claimed.get("status") != "READY" or claimed.get("scope") != scope: return _reject("actual_Native_prepared_scope_claim_rejected",claimed)
	_actual_admission_scope = scope
	if not _feature.primitives.begin_original_phase(_loading_site): return _reject("actual_loading_source_site_rejected", {})
	if boot.profile_state_handoff != null:
		if not adopt_original_loaded_profile(boot): return false
	else:
		var pending: Dictionary = services.admission.verify_original_unselected_startup_source(boot)
		if pending.get("success") != true: return _reject("actual_unselected_startup_source_unproved", pending)
	if not _feature.primitives.finish_original_phase() or not host.finish_original_call_site(_loading_site): return _reject("loading_adoption_source_finish_rejected", {})
	_loading_site = {}
	return true
func adopt_original_loaded_profile(publications: Dictionary) -> bool:
	if not cold_resource_calls_allowed() or _loading_site.is_empty() or not _profile.is_empty(): return false
	for field: String in ["profile_publication","profile_state_handoff","content_snapshot","source_commit_receipt"]:
		if not publications.get(field) is Dictionary: return _reject("loaded_profile_publication_missing", {"field":field})
	# Main still owns the prepared source until the single real S adoption has
	# succeeded. The real original provider commits all closed writers together.
	var admitted: Dictionary = _services.admission.prepare_original_profile_source_handoff(publications.profile_state_handoff, publications.source_commit_receipt, _boot.feature_resources.lease_owner)
	if admitted.get("success") != true: return _reject("main_source_commit_not_proved", admitted)
	var persistence_port := PersistenceBudget.new(_budget, _profile_scope)
	_profile = ProfileFactory.create_loaded(self, publications.profile_publication, publications.content_snapshot, persistence_port, publications.profile_state_handoff)
	if not _profile.get("success", false) or _profile.get("loaded_state_adoption", {}).get("ok") != true: return _abort_loaded_handoff(publications, "original_loaded_profile_adoption_rejected", _profile)
	_profile_commit_attempted = true
	var committed: Dictionary = _services.admission.commit_original_profile_source_handoff(admitted, _profile.loaded_state_adoption)
	if committed.get("success") == true: _profile_commit_acknowledged = true
	if committed.get("success") != true: return _abort_loaded_handoff(publications, "original_profile_source_commit_rejected", committed)
	_profile["original_loaded_handoff_applied"] = true
	return true
func _abort_loaded_handoff(publications: Dictionary, code: String, details: Dictionary) -> bool:
	if _profile_commit_attempted:
		# An unsuccessful returned suffix is not proof that Main did not commit.
		# Keep the exact Source owner and all accepted debt for factual close.
		return _reject(code,{"original_failure":details,"Main_commit_attempted":true,"Main_commit_acknowledged":_profile_commit_acknowledged,"source_commit_receipt":publications.source_commit_receipt})
	var restored: Dictionary = _services.admission.abort_original_profile_source_handoff(publications.source_commit_receipt)
	if restored.get("success") != true: fault("original_main_profile_abort_unproved", restored)
	elif not _finish_actual_original_admission_scope("ABORTED"): fault("original_aborted_admission_scope_retirement_unproved",{})
	return _reject(code, details)

func _finish_actual_original_admission_scope(expected: String) -> bool:
	if _actual_admission_scope.is_empty(): return false
	var id: int = _actual_admission_scope.scope_id
	var actual: Dictionary = _host.poll_original_source_admission_scope(id)
	var wanted: Dictionary = _actual_admission_scope.duplicate(true)
	wanted.state = expected
	if actual.get("status") != "READY" or actual.get("scope") != wanted or not _host.finish_original_source_admission_scope(id): return false
	_actual_admission_scope = {}
	return true
func _reject(code: String, details: Dictionary) -> bool:
	fault(code, details)
	return false
func _resource_failure(reason: String) -> void: fault("source_resource_budget_failure", {"reason":reason})

func adopt_world_core(core: RefCounted, actor_access: RefCounted, clock_ports: RefCounted) -> bool:
	if is_faulted() or _phase == "CLOSED" or (_core != null and _core.get_ref() != null): return false
	if core.owner_thread_id() != _owner or actor_access.owner_thread_id() != _owner or clock_ports.owner_thread_id() != _owner: return false
	if not _actor_router.bind_world(core, actor_access): return false
	_core = weakref(core)
	_adopt_count += 1
	return true
func release_world_core(core: RefCounted) -> bool:
	if _core == null or not is_same(_core.get_ref(), core) or _budget.resource_external_segment_active(): return false
	var close_scope: Dictionary = {}
	if _host.current_clock_frame().get("closing_session") == true:
		close_scope = core.capture_original_persistent_close_scope()
		if close_scope.get("contract_id") != "hardcore.source.persistent_close_scope.v1" or close_scope.get("source_core_id") != core.get_instance_id() or close_scope.get("world_context") != core.current_world_identity() or close_scope.get("owner_session_id") != _id: return false
	if _path_slot != null and not _path_slot.release_world(core): return false
	if not _actor_router.release_world(core): return false
	_persistent_world_context = core.current_world_identity().duplicate(true)
	if not close_scope.is_empty():
		_persistent_close_scope = close_scope
		_persistent_entry_ordinal = int(close_scope.entry_ordinal)
	_core = null
	_release_count += 1
	# Preserve budget, accepted tickets, Profile, scopes, journal and leases.
	return _transport.bind_current(_loading_transport)
func bind_original_application_world(core: RefCounted, publication: Dictionary) -> bool:
	if _core == null or not is_same(_core.get_ref(),core) or OS.get_thread_caller_id() != _owner: return false
	var application_bindings: Script = load("res://scripts/gameplay/source/source_application_providers.gd")
	return application_bindings.bind_original_world_services(self,core,publication,_services)
func original_service_actors() -> RefCounted: return _service_actors
func release_original_application_world_references(core: RefCounted, root: RefCounted) -> bool:
	return preload("res://scripts/gameplay/source/source_application_providers.gd").release_original_world_service_references(self,core,root,_services)
func original_frame_budget() -> RefCounted: return _budget
func original_event_journal() -> RefCounted: return _journal
func original_engagement_owner() -> RefCounted: return _engagement
func original_global_random() -> RefCounted: return _global_random
func original_enemy_shared_owner(bindings: Dictionary, actor_access: Object) -> RefCounted:
	if not _enemy_shared.bind_current_world(bindings, actor_access):
		fault("enemy_shared_actual_world_binding_rejected", {})
		return null
	return _enemy_shared
func original_enemy_audio_shared_owner(primitives: RefCounted) -> RefCounted:
	if _enemy_audio == null:
		_enemy_audio = EnemyAudio.new()
		if not _enemy_audio.configure_handoff(_boot.enemy_audio_handoff, primitives):
			fault("enemy_audio_original_handoff_rejected", {})
			return null
	return _enemy_audio
func original_profile_owner() -> Dictionary:
	if _profile.is_empty(): return {"success":false,"errors":["original_loaded_profile_not_yet_adopted"]}
	return _profile
func feature_resource_process_scope() -> RefCounted: return _feature_scope
func original_profile_process_scope() -> RefCounted: return _profile_scope
func feature_resource_session() -> Dictionary: return _feature
func bind_current_original_resource_transport(value: RefCounted) -> bool: return _transport.bind_current(value)
func freeze_original_main_prefix() -> Dictionary:
	# LIVE results and ordinary/caster prefixes share this single true-ACK
	# boundary. Both Native and the Source journal must see the same receipt
	# before any caller freezes the next consecutive immutable prefix.
	var receipt: Dictionary = _host.completed_original_main_prefix_receipt()
	if not _journal.consume_normal_receipt(receipt):
		fault("actual_normal_main_prefix_ack_rejected", receipt)
		return {}
	return _journal.freeze_prefix()
func try_publish_original_event_prefix(event: Dictionary) -> Dictionary:
	# The event/ticket is already reserved and appended, but a full Native FIFO
	# has not accepted a publication yet. Keep intent only until actual READY.
	var current: Dictionary = freeze_original_main_prefix()
	if current.is_empty() or not current.events.has(event): return {"status":"INVALID","error":"actual_pending_event_not_in_current_journal"}
	var prefix: Dictionary = _journal.original_registered_prefix_containing(event)
	var existing: bool = not prefix.is_empty()
	if not existing: prefix=current
	var accepted: Dictionary = _host.try_register_published_original_main_prefix(prefix)
	if accepted.get("status")!="READY": return accepted
	if not existing and not _journal.register_normal_publication(prefix):
		fault("actual_accepted_event_prefix_journal_registration_failed",{})
		return {"status":"INVALID","error":"actual_accepted_event_prefix_journal_registration_failed"}
	return {"status":"READY","prefix":prefix}
func ack_original_main_prefix(receipt: Dictionary, prefix: Dictionary) -> bool: return _journal.acknowledge(receipt, prefix)
func profile_world_paused() -> bool: return bool(_host.current_host_paused())
func original_scope_can_process(scope: RefCounted) -> bool:
	if not scope.runtime_object_is_present() or not scope.is_inside_world(): return false
	match int(scope.effective_process_mode):
		1: return not profile_world_paused()
		2: return profile_world_paused()
		3: return true
		4: return false
	fault("source_scope_effective_mode_invalid", {})
	return false
func service_original_process_frame_without_world(sequence: int) -> bool:
	if _core != null and _core.get_ref() != null: return _reject("duplicate_session_world_process_frame", {"sequence":sequence})
	if sequence != _clock.get_process_frames(): return _reject("source_process_frame_provenance", {})
	if _profile.is_empty(): return true # Actual Main Startup load has not handed a model to S yet.
	_persistent_entry_ordinal = 0
	if not _invoke_original_persistent_entry("SceneTree.process_frame",Callable(_profile.runtime,"service_process_frame"),[sequence]): return false
	return _invoke_original_persistent_entry("SceneTree.P_GROUP:after_process_frame",Callable(_host,"flush_source_deferred"),[&"P",&"P_GROUP:after_process_frame"])

func configure_original_persistent_process_scopes(origins: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _owner == OS.get_main_thread_id() or not _persistent_process_origins.is_empty(): return false
	var expected := {"profile":"res://scripts/player_state.gd","feature":"res://scripts/features/runtime/feature_resource_preparation.gd","profile_receipts":"res://scripts/layers/runtime/execution/paused_receipt_pump.gd"}
	if origins.size() != expected.size(): return false
	var ids: Dictionary = {}
	var scopes: Dictionary = {}
	for key: String in expected:
		var record: Variant = origins.get(key)
		if not record is Dictionary or record.get("success") != true or not record.get("scope") is Dictionary: return false
		if not record.get("node_id") is int or record.node_id <= 0 or ids.has(record.node_id): return false
		if not record.get("root_child_id") is int or record.root_child_id <= 0: return false
		if record.get("source_script") != expected[key] or not record.get("source_sha256") is String or record.source_sha256.length() != 64: return false
		var original_script: Script = load(expected[key])
		if original_script == null or original_script.get_source_code().sha256_text() != record.source_sha256: return false
		if not record.get("source_path") is Array or record.source_path.is_empty() or record.scope.get("source_path") != record.source_path: return false
		for index: Variant in record.source_path:
			if not index is int or index < 0: return false
		if record.scope.get("source_entry") != expected[key]+":_process" or record.scope.get("runtime_present") != true or record.scope.get("inside_world") != true or record.scope.get("queued_for_retirement") != false: return false
		var scope := Scope.new()
		if record.scope.get("life_generation") != scope.life_generation or not scope.configure_source(record.scope,self): return false
		scopes[key] = scope
		ids[record.node_id] = true
	var parent_path: Array = origins.profile.source_path
	var child_path: Array = origins.profile_receipts.source_path
	if origins.profile_receipts.scope.parent_scope_id != origins.profile.node_id or child_path.size() != parent_path.size()+1 or child_path.slice(0,parent_path.size()) != parent_path: return false
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture(origins,true,false)
	if captured.get("success") != true: return false
	_persistent_process_origins = captured.value
	_profile_scope = scopes.profile
	_feature_scope = scopes.feature
	_profile_receipt_scope = scopes.profile_receipts
	return true

func original_persistent_callback_order(id: int, method: StringName) -> Dictionary:
	if OS.get_thread_caller_id() != _owner or _persistent_process_origins.is_empty(): return {"matched":false,"ok":false}
	var key := ""
	if id == get_instance_id():
		if method == &"original_profile_node_process": key = "profile"
		elif method == &"original_paused_profile_receipts": key = "profile_receipts"
	elif not _feature.is_empty() and id == _feature.coordinator.get_instance_id() and method == &"original_process": key = "feature"
	if key.is_empty(): return {"matched":false,"ok":false}
	var record: Dictionary = _persistent_process_origins[key]
	var path: Array = record.source_path.duplicate()
	var tree: RefCounted = original_source_tree_service()
	if tree != null:
		var current: Dictionary = tree.original_persistent_scope_path(record)
		if current.get("ok") != true: return {"matched":true,"ok":false,"reason":"actual_persistent_global_path_missing"}
		path = current.source_path
	return {"matched":true,"ok":true,"domain":"P","source_path":path,"order":record.tree_ordinal*2+1,"entry":record.scope.source_entry}

func original_persistent_callback_rows(domain: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if OS.get_thread_caller_id() != _owner or _phase == "CLOSED": return rows
	if domain == &"P" and not _profile.is_empty():
		for spec: Array in [[_profile_scope,&"original_profile_node_process"],[_profile_receipt_scope,&"original_paused_profile_receipts"]]:
			var order: Dictionary = original_persistent_callback_order(get_instance_id(),spec[1])
			if order.get("ok") != true: fault("actual_persistent_Profile_order_missing",order); return []
			rows.append({"target":weakref(self),"scope":spec[0],"domain":domain,"method":spec[1],"priority":spec[0].process_priority,"source_order":order.order,"source_path":order.source_path,"registration_order":rows.size(),"entry":order.entry})
	if domain == &"P" and not _feature.is_empty():
		var order: Dictionary = original_persistent_callback_order(_feature.coordinator.get_instance_id(),&"original_process")
		if order.get("ok") != true: fault("actual_persistent_Feature_order_missing",order); return []
		rows.append({"target":weakref(_feature.coordinator),"scope":_feature_scope,"domain":domain,"method":&"original_process","priority":_feature_scope.process_priority,"source_order":order.order,"source_path":order.source_path,"registration_order":rows.size(),"entry":order.entry})
	var tree: RefCounted = original_source_tree_service()
	if tree != null: rows.append_array(tree.original_persistent_callback_rows(domain))
	return rows

func original_profile_node_process(delta: float) -> bool:
	if OS.get_thread_caller_id() != _owner or _profile.is_empty() or _host.current_clock_frame().get("phase") != "P_GROUP": return false
	if not _profile_scope.can_process() or not _profile_scope.process_enabled(): return true
	var sequence: int = _host.current_clock_frame().source_process_frame
	if sequence <= _last_profile_node_frame: return false
	_last_profile_node_frame = sequence
	# Original PlayerState._process body, in this order, at its original node P.
	_profile.profile.service_receipts()
	_profile.profile.step_process(delta)
	return true

func original_paused_profile_receipts(_delta: float) -> bool:
	if OS.get_thread_caller_id() != _owner or _profile.is_empty() or _host.current_clock_frame().get("phase") != "P_GROUP": return false
	var sequence: int = _host.current_clock_frame().source_process_frame
	if sequence <= _last_profile_receipt_frame: return false
	_last_profile_receipt_frame = sequence
	# This is the real ALWAYS child body, distinct from the parent callback and
	# process_frame signal. It pumps only on pause and never advances timers.
	if profile_world_paused() and _profile_scope.runtime_object_is_present() and not _profile_scope.is_queued_for_retirement(): _profile.profile.service_receipts()
	return true

func dispatch_original_persistent_without_world(name: String, frame: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _core != null and _core.get_ref() != null or frame != _host.current_clock_frame() or frame.get("phase") != name: return false
	if name not in ["P_GROUP","H_GROUP"]: return true
	if name == "H_GROUP": _persistent_entry_ordinal = 0
	var domain: StringName = &"P" if name == "P_GROUP" else &"H"
	var rows: Array[Dictionary] = original_persistent_callback_rows(domain)
	rows.sort_custom(original_callback_before)
	for row: Dictionary in rows:
		var scope: RefCounted = row.scope
		if not scope.runtime_object_is_present() or not scope.is_inside_world() or not scope.can_process(): continue
		if not (scope.process_enabled() if domain == &"P" else scope.physics_enabled()): continue
		var target: RefCounted = row.target.get_ref()
		if target == null: continue
		if not _invoke_original_persistent_entry(row.entry,Callable(target,row.method),[float(frame.scaled_delta)]): return false
	return _invoke_original_persistent_entry("SceneTree."+name+":end_group",Callable(_host,"flush_source_deferred"),[domain,StringName(name+":end_group")]) and not is_faulted()

func _invoke_original_persistent_entry(entry: String, callback: Callable, arguments: Array) -> bool:
	var frame: Dictionary = _host.current_clock_frame()
	if _feature.is_empty() or _persistent_world_context.is_empty() or frame.get("phase") not in ["P_GROUP","H_GROUP"]: return false
	_persistent_entry_ordinal += 1
	var site := {"clock_epoch":int(frame.epoch),"domain":&"P" if frame.phase == "P_GROUP" else &"H","entry_id":entry,"entry_ordinal":_persistent_entry_ordinal,"bootstrap":int(frame.epoch)==0,"observation_process_epoch":int(frame.source_process_frame),"world_context":_persistent_world_context,"deadline_usec":int(frame.next_release_usec)}
	if not _feature.primitives.begin_original_phase(site): return false
	var result: Variant = callback.callv(arguments)
	var finished: bool = _feature.primitives.finish_original_phase() and _host.finish_original_call_site(site)
	return finished and (not result is bool or result)

static func original_callback_before(a: Dictionary, b: Dictionary) -> bool:
	if a.priority != b.priority: return a.priority < b.priority
	var left: Array = a.source_path
	var right: Array = b.source_path
	for index: int in range(mini(left.size(),right.size())):
		if left[index] != right[index]: return left[index] < right[index]
	if left.size() != right.size(): return left.size() < right.size()
	return a.registration_order < b.registration_order

func begin_loading_source(site: Dictionary) -> bool:
	if is_faulted() or _budget.resource_external_segment_active() or not _loading_site.is_empty(): return false
	var checked: Dictionary = _services.admission.verify_original_loading_boundary(site)
	if checked.get("success") != true: return _reject("original_loading_boundary_missing", checked)
	_phase = "LOADING"
	if not _feature.primitives.begin_original_phase(site): return false
	_loading_site = site
	return true
func finish_loading_source() -> bool:
	if _loading_site.is_empty() or not _feature.primitives.finish_original_phase() or not _host.finish_original_call_site(_loading_site): return false
	_loading_site = {}
	return true
func enter_live(closure: Dictionary) -> bool:
	if is_faulted() or _phase != "LOADING" or not _loading_site.is_empty() or _budget.resource_external_segment_active(): return false
	var inspected: Dictionary = _services.admission.verify_actual_loading_pinned_closure(closure)
	if inspected.get("success") != true: return _reject("live_required_resource_closure_unproved", inspected)
	var installed: Dictionary = _services.live_feature.admit_original_live_feature_continuations(self, _feature, closure)
	if installed.get("success") != true: return _reject("live_feature_caller_continuations_missing", installed)
	if not _finish_actual_original_admission_scope("COMMITTED"): return _reject("actual_committed_admission_scope_retirement_unproved",{})
	_pins = inspected
	_phase = "LIVE"
	return true
func release_loading_pins(closure_id: int) -> bool:
	# Actual legal scene/actor/skill/ticket lifetime validation is mandatory.
	return bool(_services.admission.release_original_loading_pins(closure_id))

func submit_live_resource(request: Dictionary, category: String, lane: int, reserved_usec: int, consumer_key := "feature") -> Dictionary:
	if consumer_key != "feature" and not _live_consumers.has(consumer_key): return {"status":"INVALID","error":"unregistered_actual_consumer"}
	if _phase != "LIVE" or (is_faulted() and not (request.get("cleanup") == true and actual_original_closing_resource_service())): return {"status":"INVALID","error":"actual_live_phase_required"}
	if request.get("main_prefix") != _journal.freeze_prefix(): return {"status":"INVALID","error":"actual_session_journal_prefix_required"}
	var reservation: Dictionary = _budget.reserve_live(category, lane, reserved_usec)
	if reservation.is_empty(): return {"status":"BACKPRESSURE","error":"same_s_budget_reservation_denied"}
	var submitted: Dictionary = request.duplicate(true)
	submitted.reservation = reservation
	submitted.submitted_usec = Time.get_ticks_usec()
	# Native owns admission identity/call ordinal; no local sequence guess.
	var accepted: Dictionary = _host.submit_live_original_resource(submitted)
	if accepted.get("status") != "PENDING":
		if not _budget.release_unaccepted(reservation):
			fault("live_unaccepted_reservation_release_rejected",reservation)
			return {"status":"INVALID","error":"actual_unaccepted_budget_release_failed"}
		return accepted
	var accepted_request: Dictionary = accepted.request
	var identity: Dictionary = accepted_request.identity
	if not _journal.register_normal_publication(accepted_request.main_prefix):
		fault("accepted_live_journal_prefix_rejected", identity)
		return {"status":"INVALID","identity":identity}
	var key := JSON.stringify([identity.bridge_generation, identity.op_sequence])
	if _live_tickets.has(key):
		fault("duplicate_native_live_ticket", identity)
		return {"status":"INVALID","identity":identity}
	_live_tickets[key] = {"identity":identity,"reservation":reservation,"settled":false,"applied":false,"request":accepted_request,"consumer_key":consumer_key}
	return accepted
func begin_resource_commit_phase(source_process_frame: int) -> bool:
	if _resource_commit_epoch != -1 or source_process_frame != _clock.get_process_frames() or (is_faulted() and not actual_original_closing_resource_service()): return false
	_resource_commit_epoch = source_process_frame
	return true

func actual_original_closing_resource_service() -> bool:
	if OS.get_thread_caller_id() != _owner or _host == null: return false
	var frame: Dictionary = _host.current_clock_frame()
	return frame.get("closing_session") == true and frame.get("phase") == "P_CLOSE_SERVICE" and frame.get("source_boundary") == "NODE_PROCESS_SERVICE" and frame.get("closing_process_publication",{}).get("phase") == "NODE_PROCESS_SERVICE"
func commit_live_resource(identity: Dictionary) -> Dictionary:
	var settled: Dictionary=settle_live_resource(identity)
	if settled.get("status")!="SETTLED": return settled
	return apply_settled_live_resource(identity)

func settle_live_resource(identity: Dictionary) -> Dictionary:
	if _resource_commit_epoch != _clock.get_process_frames(): return {"status":"BUSY"}
	var key := JSON.stringify([identity.bridge_generation, identity.op_sequence])
	if not _live_tickets.has(key): return {"status":"INVALID"}
	var held: Dictionary = _live_tickets[key]
	if held.applied: return {"status":"SETTLED","identity":identity,"budget_receipt":held.receipt}
	if not held.settled:
		var polled: Dictionary = _host.poll_live_original_resource(identity)
		if polled.get("status") != "READY": return polled
		var reply: Dictionary = polled.reply
		var main_receipt: Variant = reply.get("native_main_prefix_receipt")
		if not main_receipt is Dictionary or main_receipt.size() != 4 or not _journal.consume_normal_receipt(main_receipt):
			fault("live_actual_main_prefix_receipt_rejected", identity)
			return {"status":"INVALID"}
		# Native first-poll time is a factual immutable receipt timestamp. A later
		# script wall-clock read cannot replace it in the settlement comparison.
		if not reply.get("native_received_usec") is int:
			fault("live_native_received_time_missing", identity)
			return {"status":"INVALID"}
		var current_frame: Dictionary = _host.current_clock_frame()
		if not current_frame.get("epoch") is int:
			fault("live_actual_commit_clock_epoch_missing", identity)
			return {"status":"INVALID"}
		var receipt: Dictionary = _budget.settle_live(held.reservation, identity, reply, int(reply.native_received_usec), int(current_frame.epoch))
		if receipt.is_empty():
			fault("live_resource_cost_receipt_rejected", identity)
			return {"status":"INVALID"}
		held.settled = true
		held.receipt = receipt
		held.reply = reply
		held.native_settlement_acknowledged = false
	# A try-lock miss is no acknowledgement. Retain the SAME once-debited
	# receipt and original epoch/time for a later P; never debit a second time.
	if not bool(held.get("native_settlement_acknowledged", false)):
		var confirmation: Dictionary = _host.settle_live_original_resource_status(held.receipt)
		if confirmation.get("status") == "PENDING":
			return {"status":"PENDING","identity":identity,"budget_settled":true}
		if confirmation.get("status") != "SETTLED":
			fault("native_live_settlement_invalid", confirmation)
			return {"status":"INVALID"}
		held.native_settlement_acknowledged = true
	return {"status":"SETTLED","identity":identity,"budget_receipt":held.receipt}

func apply_settled_live_resource(identity: Dictionary) -> Dictionary:
	if _resource_commit_epoch!=_clock.get_process_frames(): return {"status":"BUSY"}
	var key:=JSON.stringify([identity.bridge_generation,identity.op_sequence])
	if not _live_tickets.has(key): return {"status":"INVALID"}
	var held: Dictionary=_live_tickets[key]
	if held.applied: return {"status":"SETTLED","identity":identity,"budget_receipt":held.receipt}
	if not held.settled or not bool(held.get("native_settlement_acknowledged",false)): return {"status":"PENDING"}
	# Actual original cursor/result/lease/reentry applies exactly once after
	# Native confirms the accepted receipt. A failed commit retains obligations.
	var consumer: Object = _live_consumer(str(held.consumer_key))
	if consumer == null: return {"status":"INVALID","error":"actual_consumer_missing"}
	var applied: Dictionary = consumer.commit_original_live_feature_reply(identity, held.reply)
	if applied.get("status") in ["PENDING","BUSY"]: return {"status":"PENDING","identity":identity,"budget_settled":true}
	if applied.get("success") != true:
		fault("live_feature_original_commit_rejected", applied)
		return {"status":"INVALID"}
	held.applied = true
	return {"status":"SETTLED","identity":identity,"budget_receipt":held.receipt}
func finish_resource_commit_phase() -> bool:
	if _resource_commit_epoch == -1: return false
	_resource_commit_epoch = -1
	return true
func retire_live_resource(identity: Dictionary) -> bool:
	var key := JSON.stringify([identity.bridge_generation, identity.op_sequence])
	if not _live_tickets.has(key): return false
	var held: Dictionary = _live_tickets[key]
	if not held.settled or not held.applied or not _live_consumer(str(held.consumer_key)).original_ticket_lease_obligations_retired(identity): return false
	if not _host.retire_live_original_resource(identity): return false
	if not _budget.retire_settlement(int(held.reservation.reservation_id)): return false
	_live_tickets.erase(key)
	return true

func retain_feature_resource_publication(value: Dictionary) -> Dictionary:
	if _phase == "LIVE": return _services.live_feature.retain_original_feature_publication(value)
	return _feature.primitives.retain_feature_resource_publication(value)
func release_feature_resource_retention(publication_id: int, retention_id: int) -> bool:
	if _phase == "LIVE": return _services.live_feature.release_original_feature_retention(publication_id, retention_id)
	return _feature.primitives.release_feature_resource_retention(publication_id, retention_id)
func feature_resource_retention_supports_path(publication_id: int, retention_id: int, path: String) -> bool:
	if _phase == "LIVE": return _services.live_feature.original_feature_retention_supports_path(publication_id, retention_id, path)
	return _feature.primitives.feature_resource_retention_supports_path(publication_id, retention_id, path)
func prepare_profile_feature_resources(catalog: Dictionary, enabled: Array, _sequence: int, _scope: Dictionary) -> Dictionary:
	if _phase == "LIVE": return await _services.live_feature.prepare_original_profile_feature_resources(catalog, enabled)
	var ready: Dictionary = await _feature.coordinator.prepare(catalog, enabled)
	if ready.get("success") != true: return ready
	var lease: RefCounted = ready.lease
	ready.resource_publication = lease.domain_publication() if lease != null else {}
	ready.diagnostics = lease.diagnostics() if lease != null else {}
	return ready
func apply_profile_feature_ready(callback: Callable) -> bool:
	if _phase == "LIVE": return await _services.live_feature.apply_original_profile_feature_ready(callback)
	return await _feature.coordinator.apply_ready(callback)
func profile_feature_is_applying() -> bool:
	if _phase == "LIVE": return _services.live_feature.original_feature_is_applying()
	return _feature.coordinator.is_applying()
func cancel_profile_feature_resources() -> void:
	if _phase == "LIVE": _services.live_feature.cancel_original_feature_requests()
	else: _feature.coordinator.cancel_all()
func prepare_profile_feature_directory(path: String) -> Dictionary: return await _services.directory.prepare_directory(path)
func profile_global_randi() -> int: return _global_random.randi()
func profile_global_randi_range(low: int, high: int) -> int: return _global_random.randi_range(low, high)
func _actual_world() -> RefCounted:
	if _core == null or _core.get_ref() == null:
		fault("profile_world_service_without_world", {})
		assert(false, "ProfileRuntime enumerates actual registered worlds only")
	return _core.get_ref()
func profile_runtime_owner_view() -> Dictionary: return _actual_world().profile_runtime_owner_view()
func profile_runtime_registry() -> RefCounted: return _actual_world().profile_runtime_registry()
func feature_publication_scope() -> Dictionary: return _actual_world().feature_publication_scope()
func gameplay_input_is_enabled() -> bool: return _actual_world().gameplay_input_is_enabled()

func lifetime_evidence() -> Dictionary:
	return {"session_id":_id,"adopt_count":_adopt_count,"release_count":_release_count,
		"profile_id":_profile.profile.get_instance_id() if not _profile.is_empty() else 0,"budget_id":_budget.get_instance_id(),
		"journal_id":_journal.get_instance_id(),"feature_id":_feature.coordinator.get_instance_id(),
		"engagement_id":_engagement.get_instance_id(),"live_tickets":_live_tickets.size(),"faults":_faults.duplicate(true)}

func live_resource_phase() -> bool: return _phase == "LIVE" and not is_faulted()

func original_streaming_live_reservation_policy() -> Dictionary:
	assert(OS.get_thread_caller_id()==_owner)
	# This exact policy was supplied and sealed by the real Main startup owner.
	# Absence stays an empty rejected policy, never an inferred runtime default.
	return _boot.get("streaming_live_reservation_usec",{}).duplicate(true)

func register_live_resource_consumer(key: String, consumer: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _owner or key.is_empty() or key == "feature" or _live_consumers.has(key) or consumer == null or consumer.owner_thread_id() != _owner: return false
	for method in ["commit_original_live_feature_reply", "original_ticket_lease_obligations_retired", "live_operations_drained"]:
		if not consumer.has_method(method): return false
	# Session pins accepted consumers until actual transport retirement. Consumer
	# retains only WeakRef(Session), so this introduces no retention cycle.
	_live_consumers[key] = consumer
	return true

func _live_consumer(key: String) -> Object:
	return _services.live_feature if key == "feature" else _live_consumers.get(key)

func unregister_live_resource_consumer(key: String, consumer: RefCounted) -> bool:
	if _live_consumers.get(key) != consumer or not consumer.live_operations_drained(): return false
	for held: Dictionary in _live_tickets.values():
		if str(held.consumer_key) == key: return false
	_live_consumers.erase(key)
	return true

func original_transport_obligations_released(identity: Dictionary) -> bool:
	# Native knows whether Main acknowledged physical retirement OR actually
	# transferred the exact witness to its strongly pinned, validated vault.
	if not _host.has_method("live_original_resource_transport_releasable"): return false
	return bool(_host.live_original_resource_transport_releasable(identity))


func original_close_process_signal_highwater() -> int:
	assert(OS.get_thread_caller_id()==_owner)
	if not _host.has_method("original_close_process_signal_highwater"):
		fault("MISSING_Native_original_close_SIGNAL_highwater",{})
		return -1
	return int(_host.original_close_process_signal_highwater())
func original_resource_service_waiter_count() -> int:
	assert(OS.get_thread_caller_id()==_owner)
	return 0 if _profile.is_empty() else _profile.runtime.original_resource_service_waiter_count()
func service_original_close_process_signal_without_world(frame: Dictionary) -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if (_core!=null and _core.get_ref()!=null) or frame!=_host.current_clock_frame() or frame.get("closing_session")!=true or str(frame.get("source_boundary",""))!="PROCESS_SIGNAL": return false
	# Empty Profile is the already-admitted genuine unselected Startup state.
	if _profile.is_empty(): return true
	return _profile.runtime.service_original_close_process_signal(int(frame.source_process_frame),int(frame.actual_main_process_frame),int(frame.published_signal_highwater))

var _persistent_close_scope: Dictionary = {}
func service_original_close_session_obligations(frame: Dictionary, actual_receipts: Callable) -> bool:
	if OS.get_thread_caller_id() != _owner or _core != null and _core.get_ref() != null or frame != _host.current_clock_frame() or frame.get("closing_session") != true or not actual_receipts.is_valid(): return false
	var publication: Variant = frame.get("closing_process_publication")
	if not publication is Dictionary or publication.get("contract_id") != "hardcore.source.closing_process_frame.v1" or publication.get("main_process_frame") != frame.get("actual_main_process_frame"): return false
	var boundary: String = str(frame.get("source_boundary",""))
	if boundary not in ["PROCESS_SIGNAL","NODE_PROCESS_SERVICE"] or publication.get("phase") != boundary or frame.get("phase") != ("P_CLOSE_SIGNAL" if boundary == "PROCESS_SIGNAL" else "P_CLOSE_SERVICE"): return false
	var sequence: int = int(frame.source_process_frame)
	var main_frame: int = int(frame.actual_main_process_frame)
	if _persistent_close_scope.is_empty():
		# A genuinely unselected/no-World Session may start here. A released
		# World must instead hand over its exact half-pair and entry frontier.
		if _adopt_count != 0 or _release_count != 0 or boundary != "PROCESS_SIGNAL": return false
		_persistent_close_scope = {"baseline":frame,"last_source_frame":sequence-1,"last_Main_frame":-1,"pending_service":false}
	for key: String in ["epoch","source_physics_frame","h_ordinal","simulation_elapsed"]:
		if frame.get(key) != _persistent_close_scope.baseline.get(key): return false
	if boundary == "PROCESS_SIGNAL":
		if _persistent_close_scope.pending_service or sequence != _persistent_close_scope.last_source_frame+1 or main_frame <= _persistent_close_scope.last_Main_frame: return false
		_persistent_close_scope.last_source_frame=sequence;_persistent_close_scope.last_Main_frame=main_frame;_persistent_close_scope.pending_service=true
		_persistent_entry_ordinal=0
		if not _invoke_original_persistent_close_entry("SceneTree.process_frame",Callable(self,"service_original_close_process_signal_without_world"),[frame]): return false
		return _invoke_original_persistent_close_entry("SceneTree.P_GROUP:after_process_frame",Callable(_host,"flush_source_deferred"),[&"P",&"P_GROUP:after_process_frame"])
	if not _persistent_close_scope.pending_service or sequence != _persistent_close_scope.last_source_frame or main_frame != _persistent_close_scope.last_Main_frame: return false
	if not _invoke_original_persistent_close_entry("Session.accepted_close_cleanup",actual_receipts,[]): return false
	if not _invoke_original_persistent_close_entry("SceneTree.P_GROUP:end_group",Callable(_host,"flush_source_deferred"),[&"P",&"P_GROUP:end_group"]): return false
	_persistent_close_scope.pending_service=false
	return not is_faulted()

func _invoke_original_persistent_close_entry(entry: String, callback: Callable, arguments: Array) -> bool:
	var frame: Dictionary = _host.current_clock_frame()
	if _feature.is_empty() or _persistent_world_context.is_empty() or frame.get("closing_session") != true or frame.get("phase") not in ["P_CLOSE_SIGNAL","P_CLOSE_SERVICE"] or _budget.resource_external_segment_active() or int(_budget.snapshot().open_scopes) != 0: return false
	_persistent_entry_ordinal += 1
	var site := {"clock_epoch":int(frame.epoch),"domain":&"P","entry_id":entry,"entry_ordinal":_persistent_entry_ordinal,"bootstrap":int(frame.epoch)==0,"observation_process_epoch":int(frame.source_process_frame),"world_context":_persistent_world_context,"deadline_usec":int(frame.next_release_usec)}
	if not _feature.primitives.begin_original_phase(site): return false
	var result: Variant = callback.callv(arguments)
	var finished: bool = _feature.primitives.finish_original_phase() and _host.finish_original_call_site(site)
	return finished and (not result is bool or result)
func service_original_session_resource_close_at_actual_P(core: RefCounted, frame: Dictionary) -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if core==null or core.owner_thread_id()!=_owner or frame!=_host.current_clock_frame() or str(frame.get("source_boundary",""))!="NODE_PROCESS_SERVICE" or frame.get("closing_session")!=true: return false
	var source_frames: Variant = _services.get("source_frames")
	if not source_frames is RefCounted or not source_frames.has_method("service_original_close_session_resource_obligations"):
		return _reject("MISSING_actual_persistent_source_resource_close",{})
	var feature: Variant=_services.get("live_feature")
	if _phase=="LIVE":
		if not feature is RefCounted or not feature.has_method("service_original_feature_cleanup_at_actual_P") or not feature.service_original_feature_cleanup_at_actual_P(frame): return _reject("MISSING_actual_original_Feature_closing_P_cleanup",{})
	return source_frames.service_original_close_session_resource_obligations(self,core,frame)


func original_path_session() -> RefCounted:
	if _path_slot != null: return _path_slot
	if not _services.get("source_tree") is RefCounted or not _services.get("path_bindings") is RefCounted or not _services.path_bindings.has_method("actual_persistent_path_bindings"):
		fault("actual_persistent_source_path_services_missing", {})
		return null
	var bindings: Dictionary = _services.path_bindings.actual_persistent_path_bindings(self)
	_path_slot = PersistentPathSlot.new()
	if not _path_slot.configure_session(self, bindings, _services.source_tree):
		fault("actual_persistent_source_path_configuration_rejected", {})
		_path_slot = null
	return _path_slot
func original_path_source_tree_exit() -> bool:
	return _path_slot == null or _path_slot.retire_at_original_source_tree_exit()
func original_path_source_tree_final_free() -> bool:
	return _path_slot == null or _path_slot.free_at_original_source_tree_checkpoint()
func original_path_source_tree_retirement_complete() -> bool:
	return _path_slot == null or not _path_slot.scheduler_present()

var _original_source_frames_owner: RefCounted
func original_source_frames_owner(publication: Dictionary) -> RefCounted:
	assert(OS.get_thread_caller_id()==_owner)
	if _original_source_frames_owner==null:
		var frames:=preload("res://scripts/gameplay/world/world_source_frames_owner.gd").new()
		if not frames.configure_session(self,publication): return null
		_original_source_frames_owner=frames
	return _original_source_frames_owner
func is_original_source_frames_owner(value: RefCounted) -> bool: return is_same(_original_source_frames_owner,value)

var _original_camera_owner: RefCounted
var _original_camera_publication: Dictionary
func original_camera_constraint(publication: Dictionary) -> RefCounted:
	if OS.get_thread_caller_id() != _owner: return null
	if _original_camera_owner != null:
		# The existing S cache survives World replacement. A new Main snapshot
		# cannot overwrite camera state that Source has already advanced.
		return _original_camera_owner if publication == _original_camera_publication else null
	var camera := preload("res://scripts/gameplay/world/world_camera_constraint_owner.gd").new()
	if not camera.configure_original_handoff(publication): return null
	_original_camera_publication = publication
	_original_camera_owner = camera
	return camera

func verify_original_interactable_loading_publication(publication: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != _owner or not cold_resource_calls_allowed() or _core == null or _core.get_ref() == null: return {"status":"INVALID","error":"actual_Source_Loading_Core_required"}
	var closure: Dictionary = _boot.get("actual_loading_pin_closure",{})
	if publication.get("contract_id") != "world.interactable.loading.v1" or closure.get("interactable_loading") != publication or publication.get("world_context") != _core.get_ref().current_world_identity() or closure.get("closure_id") != _id or publication.get("closure_id") != _id: return {"status":"INVALID","error":"actual_same_interactable_Loading_publication_required"}
	# The original Native cold continuation inspects the same physical Main
	# Caster/NPC textures. A matching value alone is never a physical pin proof.
	var actual: Dictionary = _services.admission.verify_actual_loading_pinned_closure(closure)
	if actual.get("success") != true or actual.get("closure") != closure: return {"status":"MISSING","error":"actual_Main_interactable_pins_unproved"}
	return {"status":"READY","publication":publication,"actual_Main_pin_receipt":actual}

func original_world_main_dependency(name: StringName) -> RefCounted:
	assert(OS.get_thread_caller_id()==_owner)
	if name not in [&"WorldSourceCheckpoint",&"WorldMapLoadingAdmission",&"WorldViewTransport",&"WorldAudioProjection",&"WorldUiLoading"]: return null
	var value: Variant=_services.get(name)
	return value if value is RefCounted and not value is Resource and value.has_method("owner_thread_id") and value.owner_thread_id()==_owner else null
func actual_original_loading_scope_is_current(scope: Dictionary) -> bool:
	if not cold_resource_calls_allowed(): return false
	var site: Dictionary=_loading_site
	if site.is_empty() and _core!=null and _core.get_ref()!=null: site=_core.get_ref().current_original_source_site()
	if site.is_empty(): return false
	var actual: Dictionary=_services.admission.verify_original_loading_boundary(site)
	if actual.get("success") != true: return false
	if actual.get("loading_scope") == scope: return true
	# Only the genuine current Map producer can witness an arrived cold phase.
	# The immutable bootstrap scope alone grants no permission after arrival.
	if _core == null or _core.get_ref() == null or actual.get("initial_launch_scope") != scope or actual.get("source_site") != site: return false
	var current: Dictionary = actual.get("current_map_loading_context",{})
	return current.get("contract_id") == "hardcore.main.current_map_loading.context.v1" and current.get("world_context") == _core.get_ref().current_world_identity() and site.get("world_context") == current.world_context and current.get("scope") == actual.get("loading_scope") and current.get("covered") == current.get("scope",{}).get("actual_provenance",{}).get("covered")

func actual_original_map_scope_release_site_is_current(scope: Dictionary, initial_scope: Dictionary) -> bool:
	if not cold_resource_calls_allowed() or _core == null or _core.get_ref() == null: return false
	var site: Dictionary = _loading_site
	if site.is_empty(): site = _core.get_ref().current_original_source_site()
	if site.is_empty() or site.get("world_context") != _core.get_ref().current_world_identity(): return false
	var proof: Dictionary = _services.admission.verify_original_loading_boundary({"source_site":site,"release_map_scope":scope})
	return proof.get("success") == true and proof.get("contract_id") == "hardcore.main.current_map_release.context.v1" and proof.get("source_site") == site and proof.get("world_context") == site.world_context and proof.get("requested_scope") == scope and proof.get("initial_launch_scope") == initial_scope

func original_budget_session_id() -> int:
	assert(OS.get_thread_caller_id()==_owner)
	return _id
var _profile_view_sequence := 0
func next_original_profile_view_sequence() -> int:
	assert(OS.get_thread_caller_id()==_owner)
	_profile_view_sequence+=1
	return _profile_view_sequence
func original_profile_handoff_identity() -> String:
	return preload("res://scripts/gameplay/world/world_profile_ui_view.gd").original_handoff_identity(_boot.profile_state_handoff)
func actual_original_close_process_producer_drained() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	return _host.has_method("original_close_process_producer_drained") and _host.original_close_process_producer_drained()


func original_source_tree_service() -> RefCounted:
	if OS.get_thread_caller_id()!=_owner: return null
	var actual: Variant=_services.get("source_tree")
	return actual if actual is RefCounted and actual.owner_thread_id()==_owner else null
func original_source_session_clock() -> RefCounted:
	if OS.get_thread_caller_id()!=_owner: return null
	return _clock
func original_persistent_path_bindings() -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or not _services.get("path_bindings") is RefCounted: return {}
	return _services.path_bindings.actual_persistent_path_bindings(self)


func actual_original_clock_frame() -> Dictionary:
	if OS.get_thread_caller_id()!=_owner: return {}
	return _host.current_clock_frame()
func actual_original_resource_commit_phase_active() -> bool:
	return OS.get_thread_caller_id()==_owner and _resource_commit_epoch==_clock.get_process_frames()

func actual_original_feature_callback_manifest() -> Dictionary:
	if OS.get_thread_caller_id()!=_owner: return {}
	return _boot.feature_resources.source_callback_manifest.duplicate(true)

# Read-only identity for a bounded continuation inside one original resource P.
# No journal allocation, phase transition, budget admission or clock advancement.
func capture_live_resource_continuation_context() -> Dictionary:
	if OS.get_thread_caller_id() != _owner or not live_resource_phase(): return {}
	if _host == null or _budget == null or _journal == null or _resource_commit_epoch != -1: return {}
	var frame: Dictionary = _host.current_clock_frame()
	if not frame.get("epoch") is int or not frame.get("source_process_frame") is int: return {}
	var core: RefCounted = _core.get_ref() as RefCounted if _core != null else null
	var journal_identity: Dictionary = _journal.next_original_event_identity()
	var value := {"contract_id":"hardcore.source.resource_continuation_context.v1",
		"session_object_id":get_instance_id(),"owner_session_id":_id,"owner_thread":_owner,
		"host_id":_host.get_instance_id(),"budget_id":_budget.get_instance_id(),
		"journal_id":_journal.get_instance_id(),"journal_generation":int(journal_identity.journal_generation),
		"bridge_generation":int(journal_identity.bridge_generation),"source_phase":_phase,
		"world_core_id":core.get_instance_id() if core != null else 0,
		"adopt_count":_adopt_count,"release_count":_release_count,
		"clock_epoch":int(frame.epoch),"source_process_frame":int(frame.source_process_frame),
		"closing_session":bool(frame.get("closing_session",false)),"source_boundary":str(frame.get("source_boundary",""))}
	value.make_read_only()
	return value

# The original Root has already written map/generation. This path never
# increments them, creates a Session/Core, resets a budget or clears old debt.
var _last_original_map_arrival: Dictionary = {}
func can_commit_original_source_map_arrival_context(root: RefCounted, core: RefCounted, publication: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _core == null or _core.get_ref() != core or core.original_root_owner() != root: return false
	if publication.get("contract_id") != "source.map.loading.publication.v1" or publication.get("world_context") != core.current_world_identity(): return false
	var descriptor: Dictionary = publication.get("owner_descriptor",{})
	return descriptor.get("source_root_id") == root.get_instance_id() and descriptor.get("owner_session_id") == _id and descriptor.get("world_context") == core.current_world_identity() and _host.has_method("commit_original_map_arrival") and _host.has_method("verify_committed_original_map_arrival")

func original_map_source_root_helpers(root: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != _owner or _core == null or _core.get_ref() == null or _core.get_ref().original_root_owner() != root: return {}
	var result := {}
	for method: StringName in [&"_preload_map_loot_icons",&"_prewarm_learned_skill_visuals",&"_warm_fire_wall_render_path"]:
		if not root.has_method(method): return {} # MISSING actual helper remains visible.
		result[method] = Callable(root,method)
	return result

func commit_original_source_map_arrival_context(core: RefCounted, root: RefCounted, map_id: int, source_generation: int) -> bool:
	if OS.get_thread_caller_id() != _owner or _core == null or _core.get_ref() != core: return false
	return core.commit_original_source_map_arrival_context(root,map_id,source_generation)

func validate_original_map_arrival_transaction(core: RefCounted, transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction) or _core == null or _core.get_ref() != core or transaction.get("owner_session_id") != _id or transaction.get("before_world") != _persistent_world_context: return false
	if is_faulted() or _phase not in ["LIVE","LOADING"] or not _loading_site.is_empty() or _budget.resource_external_segment_active(): return false
	var bindings: Script = load("res://scripts/gameplay/source/source_application_providers.gd")
	return bindings.can_commit_original_map_arrival(self,core,transaction,_services)

func apply_original_map_arrival_transaction(core: RefCounted, transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction) or _core == null or _core.get_ref() != core: return false
	if transaction == _last_original_map_arrival: return _persistent_world_context == transaction.after_world
	if transaction.get("owner_session_id") != _id or transaction.get("before_world") != _persistent_world_context or core.current_world_identity() != transaction.get("after_world") or not _host.verify_committed_original_map_arrival(transaction): return false
	var player: Object = core.actor_handle_for_runtime_id(transaction.player_runtime_id)
	if player == null or player.identity() != transaction.player_identity: return false
	var bindings: Script = load("res://scripts/gameplay/source/source_application_providers.gd")
	if not bindings.commit_original_map_arrival(self,core,transaction,_services): return false
	_persistent_world_context = transaction.after_world
	_last_original_map_arrival = transaction
	return true

# Final return authority remains on S until the actual prefix ACK and S teardown.
var _profile_return_intent: Dictionary
var _profile_return_export: Dictionary
var _profile_return_prefix: Dictionary
var _profile_return_prefix_registered := false
var _profile_return_prefix_acknowledged := false
func record_actual_profile_return_intent(core: RefCounted, root: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_owner or is_faulted() or _core==null or not is_same(_core.get_ref(),core) or core.original_root_owner()!=root or _profile.is_empty(): return false
	var prefix: Dictionary=_journal.freeze_prefix()
	if prefix.events.is_empty() or prefix.events.back().get("operation")!=&"original_character_select_transition": return false
	var fact: Dictionary={"owner_session_id":_id,"world_context":core.current_world_identity(),"source_root_id":root.get_instance_id(),"intent_event_ordinal":prefix.through_ordinal,"profile_id":_profile.profile.active_profile_id}
	if not _profile_return_intent.is_empty():
		for field: String in ["owner_session_id","world_context","source_root_id","profile_id"]:
			if _profile_return_intent.get(field)!=fact.get(field): return false
		return true # Same genuine intent may already have an accepted prefix.
	_profile_return_intent=fact
	return true

func publish_actual_terminal_profile_return(runtime: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_owner or runtime==null or runtime.get_script()!=preload("res://scripts/gameplay/source/source_session_runtime.gd") or not is_same(runtime.get("_session"),self) or runtime.get("_world")!=null or _core!=null and _core.get_ref()!=null: return false
	if _profile_return_intent.is_empty(): return true # Original QUIT stays unchanged.
	# Native93d refuses before changing the Source authority. The version gate
	# is compatibility only; actual capture and restore receipts are mandatory.
	if _host.capabilities().get("profile_terminal_global_random_return_contract_id")!="hardcore.profile.global_random.return.v1": return _reject("MISSING_actual_Native_Profile_global_random_terminal_return",{})
	if is_faulted() or _profile.is_empty() or _host.current_clock_frame().get("closing_session")!=true: return false
	const ReturnState = preload("res://scripts/gameplay/profile/profile_terminal_return.gd")
	var source: RefCounted=_profile.profile
	if _profile_return_export.is_empty():
		source.close_profile() # Original writer barrier, no extra save/create/reset.
		var captured: Dictionary=ReturnState.capture_source(source,self)
		if captured.get("ok")!=true: return _reject("actual_terminal_Profile_capture_failed",captured)
		var random_capture: Dictionary=_host.capture_original_terminal_gameplay_random(_global_random,_journal.next_original_event_identity())
		if random_capture.get("success")!=true or not random_capture.get("terminal_handoff") is Dictionary or random_capture.terminal_handoff.is_empty(): return _reject("actual_terminal_global_random_capture_failed",random_capture)
		var envelope: Dictionary={"global_random_terminal":random_capture.terminal_handoff,"contract_id":ReturnState.ENVELOPE,"actual_host_id":_host.get_instance_id(),"owner_session_id":_id,"bridge_generation":_host.capabilities().bridge_generation,"world_context":_persistent_world_context,"source_runtime_id":runtime.get_instance_id(),"source_session_object_id":get_instance_id(),"source_profile_model_id":source.get_instance_id(),"intent":_profile_return_intent,"state":captured.publication}
		var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
		var plain: Dictionary=graph.capture(envelope,true,false)
		if plain.get("success")!=true: return _reject("actual_terminal_Profile_export_not_plain",plain)
		_profile_return_export=plain.value
		if not _journal.append({"kind":"original_profile_transport","operation":&"original_profile_terminal_export","arguments":[_profile_return_export]}): return false
		_profile_return_prefix=_journal.freeze_prefix()
	if not ReturnState.writer_idle(source): return false
	for field: String in ReturnState.SOURCE_FIELDS:
		if source.get(field)!=_profile_return_export.state.source_fields[field]: return _reject("actual_Profile_changed_after_final_export",{"field":field})
	if _profile_return_prefix_acknowledged: return true
	if not _profile_return_prefix_registered:
		if not _journal.register_normal_publication(_profile_return_prefix) or not _host.register_published_original_main_prefix(_profile_return_prefix): return false
		_profile_return_prefix_registered=true
	var actual_ack: Dictionary=_host.completed_original_main_prefix_receipt()
	if not _journal.consume_normal_receipt(actual_ack): return _reject("actual_terminal_Profile_prefix_ack_invalid",actual_ack)
	if _journal.applied_ordinal()<_profile_return_prefix.through_ordinal: return false
	_profile_return_prefix_acknowledged=true
	return true
