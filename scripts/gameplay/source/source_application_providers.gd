extends RefCounted
## S attachments only. Session/Core remain the only gameplay and journal owners.
const SessionScript := preload("res://scripts/gameplay/source/source_session.gd")
const APPLICATION_ROLES: Array[String] = ["directory","feature_retirement","main_io","WorldViewTransport","WorldAudioProjection","WorldUiLoading","WorldMapLoadingAdmission"]
const CoordinatorScript := preload("res://scripts/features/runtime/feature_resource_owner_coordinator.gd")

class Binding extends RefCounted:
	var _owner := OS.get_thread_caller_id()
	var _host: Object
	var _session: WeakRef
	var _core: WeakRef
	var _publication: Dictionary = {}
	# The wire descriptor is not a reference owner. Keep the actual interned
	# Source proxy alive until this world's final original child-free checkpoint.
	var _main_service_reference: RefCounted
	var _main_service_released := false
	var _world_binding: WeakRef
	var _missing: Dictionary = {}
	var _application_live: RefCounted
	var _map_arrival_prepared: Dictionary = {}
	func owner_thread_id() -> int: return _owner
	func configure_owner(host: Object) -> bool:
		if _host != null or _owner == OS.get_main_thread_id() or host == null or not host.is_class("HardCoreSimulationHost"): return false
		_host = host
		return true
	func bind_original_session(session: RefCounted) -> bool:
		if OS.get_thread_caller_id() != _owner or _session != null or session == null or session.get_script() != SessionScript or session.owner_thread_id() != _owner: return false
		_session = weakref(session)
		return true
	func bind_original_world(core: RefCounted, publication: Dictionary) -> bool:
		if not _bound() or core == null or core.owner_thread_id() != _owner or not is_same(core.original_source_session(), _session.get_ref()): return false
		if publication.get("world_context") != core.current_world_identity() or publication.get("contract_id") != "world.Main.view_services.publication.v1": return false
		if _core != null and _core.get_ref() != null:
			if is_same(_core.get_ref(), core): return publication == _publication and _main_service_reference != null and not _main_service_released
			if not _core.get_ref().is_original_world_closed(): return false
		if not publication.get("main_service_reference") is Dictionary: return false
		var reference: Variant = _session.get_ref().feature_resource_session().primitives.decode_original_source_value(publication.main_service_reference)
		if not reference is RefCounted: return false
		_main_service_reference = reference
		_main_service_released = false
		_core = weakref(core)
		_publication = publication.duplicate(true)
		return true
	func _bound() -> bool:
		return OS.get_thread_caller_id() == _owner and _host != null and _session != null and _session.get_ref() != null
	func _world(world: Dictionary) -> bool:
		return _bound() and _core != null and _core.get_ref() != null and _core.get_ref().current_world_identity() == world
	func _fail(code: String, details: Dictionary = {}, status := "MISSING") -> Dictionary:
		_missing = {"success":false,"status":status,"errors":[code],"error":code,"details":details}
		return _missing.duplicate(true)
	func actual_original_missing_boundary() -> Dictionary: return _missing.duplicate(true)
	func bind_original_world_context(port: RefCounted) -> bool:
		if _world_binding != null or port == null or port.owner_thread_id() != _owner: return false
		_world_binding = weakref(port)
		return true
	func _loading_call(operation: String, arguments: Array) -> Dictionary:
		if not _bound(): return _fail("actual_bound_Source_Session_required")
		var session: RefCounted = _session.get_ref()
		# Native currently has no such method whitelist/capability. Detect before
		# allocating a call ordinal, consuming Budget, or entering _exchange.
		if _host.capabilities().get("source_application_loading_call") != true:
			return _fail("Native_feature_object_call_source_application_call_2", {"operation":operation})
		if not session.cold_resource_calls_allowed():
			if _host.capabilities().get("source_application_loading_cps") != true: return _fail("actual_Loading_or_application_CPS_required", {"operation":operation})
			if session.get("_phase") != "LIVE" or (session.is_faulted() and not (operation in ["panel_state","release_map_scope","map_warm_state","world_view_exit_state","actor_view_free_state"] and session.actual_original_closing_resource_service())): return _fail("actual_LIVE_application_or_closing_cleanup_required",{},"INVALID")
			var live_publication: Dictionary = _publication
			if live_publication.is_empty() and _world_binding != null and _world_binding.get_ref() != null: live_publication = _world_binding.get_ref().get("_publication")
			if _application_live == null:
				_application_live = preload("res://scripts/gameplay/source/source_application_live_call.gd").new()
				if not _application_live.configure_owner(session,self): return _fail("actual_Session_application_consumer_required",{},"INVALID")
			return _application_live.poll_or_submit(operation,arguments,live_publication)
		var primitives: RefCounted = session.feature_resource_session().primitives
		var site: Dictionary = primitives.current_original_source_site()
		# Existing cold Native transport is bootstrap-only. A later LOADING label
		# or P_WAKE does not authorize a synchronous LIVE resource park.
		if site.get("bootstrap") != true or site.get("clock_epoch") != 0 or site.clock_epoch != _host.current_clock_frame().get("epoch"):
			return _fail("actual_nonzero_Loading_application_CPS_required", {"operation":operation,"site":site})
		var publication: Dictionary = _publication
		if publication.is_empty() and _world_binding != null and _world_binding.get_ref() != null: publication = _world_binding.get_ref().get("_publication")
		if publication.is_empty(): return _fail("actual_Main_service_reference_outside_World_required", {"operation":operation})
		var initial_scope: Dictionary = publication.get("bootstrap_resources",{}).get("loading_scope",{})
		var current_scope: bool = session.actual_original_map_scope_release_site_is_current(arguments[0],initial_scope) if operation == "release_map_scope" and arguments.size() == 1 and arguments[0] is Dictionary else session.actual_original_loading_scope_is_current(initial_scope)
		if not current_scope:
			return _fail("actual_current_Main_Loading_scope_required")
		var target: RefCounted = _main_service_reference
		if target == null or _main_service_released or target.get("descriptor") != publication.get("main_service_reference",{}): return _fail("actual_Main_service_reference_required")
		var result: Variant = primitives.object_call(target,"source_application_call",[operation,arguments])
		return result if result is Dictionary else _fail("actual_plain_application_receipt_required", {"operation":operation},"INVALID")

	func _next_actual_application_service() -> bool:
		if not _bound() or _core == null or _core.get_ref() == null: return false
		var session: RefCounted = _session.get_ref()
		var budget: RefCounted = session.original_frame_budget()
		if budget.snapshot().open_scopes != 0 or budget.resource_external_segment_active():
			_fail("application_await_must_not_hold_scalar_or_external_scope",{},"INVALID"); return false
		await _core.get_ref().profile_runtime.next_service()
		return _bound()
	func _await_loading_call(operation: String, arguments: Array) -> Dictionary:
		# A real Main HUD callback can resume an original loading coroutine in
		# H_INPUT/P_INPUT. Keep that coroutine suspended until the original
		# Profile process service; the LIVE resource lane still admits only its
		# genuine P_GROUP (or closing SERVICE) source entry. Never relabel the
		# input callback, create a frame, or park Main while S waits for service.
		if _bound() and not _session.get_ref().cold_resource_calls_allowed():
			var actual: Dictionary = _session.get_ref().actual_original_clock_frame()
			if actual.get("phase") not in ["P_GROUP","P_CLOSE_SERVICE"]:
				if not await _next_actual_application_service(): return _fail("actual_original_application_entry_service_unavailable")
		if _bound() and _session.get_ref().actual_original_clock_frame().get("closing_session") == true and operation not in ["panel_state","release_map_scope","map_warm_state","world_view_exit_state","actor_view_free_state"] and (_application_live == null or not _application_live.has_accepted_call_for(operation,arguments)):
			return {"success":false,"status":"CANCELLED","accepted":false,"reason":"actual_close_stopped_unaccepted_application_work"}
		var result: Dictionary = _loading_call(operation,arguments)
		while result.get("status") in ["PENDING","BUSY","BACKPRESSURE"] and (not result.has("identity") or result.get("success") != true):
			# A plain Main business PENDING result is delivered with success=true;
			# its caller owns the next business observation. Only transport waits
			# are serviced here, on original Source P signals without Main waits.
			if result.get("success") == true: return result
			if not await _next_actual_application_service(): return _fail("actual_original_application_service_unavailable")
			if _session.get_ref().actual_original_clock_frame().get("closing_session") == true and operation not in ["panel_state","release_map_scope","map_warm_state","world_view_exit_state","actor_view_free_state"] and (_application_live == null or not _application_live.has_accepted_call_for(operation,arguments)):
				return {"success":false,"status":"CANCELLED","accepted":false,"reason":"actual_close_stopped_unaccepted_application_work"}
			result = _loading_call(operation,arguments)
		return result

class Directory extends Binding:
	func prepare_directory(path: String) -> Dictionary:
		# Main calls ProfilePublication.prepare_feature_directory, which performs
		# actual authoring I/O and the original complete canonical compilation.
		# No mkdir, cached catalog, or second S parser can substitute for that.
		if path.is_empty(): return _fail("original_feature_registry_path_required",{},"INVALID")
		var result: Dictionary = await _await_loading_call("prepare_directory",[path])
		if result.get("success") == true:
			for field: String in ["candidate","authority"]:
				if not result.get(field) is Dictionary: return _fail("canonical_directory_result:"+field,{},"INVALID")
			if not result.get("bindings") is Array or not result.get("enabled") is Array: return _fail("canonical_directory_result_arrays",{},"INVALID")
		return result

class FeatureRetirement extends Binding:
	func original_session_retirement_state() -> Dictionary:
		if not _bound(): return _fail("actual_bound_Feature_Session_required")
		var session: RefCounted = _session.get_ref()
		var feature: Dictionary = session.feature_resource_session()
		if not feature.get("coordinator") is RefCounted or feature.coordinator.get_script() != CoordinatorScript: return _fail("actual_canonical_Feature_coordinator_required")
		var coordinator: RefCounted = feature.coordinator
		var primitives: RefCounted = feature.primitives
		if primitives.failed(): return _fail("actual_Feature_owner_fault",{},"INVALID")
		if coordinator.get("_issued_source_session_id") != session.original_budget_session_id() or not is_same(coordinator.Budget,session.original_frame_budget()): return _fail("actual_same_Feature_claim_owner_required",{},"INVALID")
		var claims: Dictionary = coordinator.threaded_claim_diagnostics()
		if not claims.has_all(["pending","missing"]): return _fail("actual_original_claim_diagnostics_required",{},"INVALID")
		# These are the original coordinator records/FIFOs, including accepted
		# Native claim associations. Never call original_process from this reader.
		var accepted_terminal: bool = coordinator.get("_issued_accepting").is_empty() and coordinator.get("_issued_active_retirement").is_empty() and coordinator.get("_issued_source_records").is_empty() and claims.pending == 0 and claims.missing == 0
		var drained := true
		var sizes := {}
		for key: String in ["_requests","_jobs","_work","_applications","_retirements","_deferred_completions","_live_cleanup_context"]:
			var ledger: Variant = coordinator.get(key)
			sizes[key] = ledger.size()
			drained = drained and ledger.is_empty()
		drained = drained and not coordinator.get("_quantum_active") and not coordinator.get("_live_service_active") and coordinator.get("_applying_request") == 0 and coordinator.get("_code_world_handoff_id") == 0
		# Checks accepted retention grants AND physical Main reference-release
		# receipts, including Script/Code lease references. Queue admission alone
		# leaves this false. This conservative existing verifier can retain a
		# non-Resource Main service reference; the exact debt remains visible.
		var leases_retired: bool = primitives.actual_original_live_receipt_debt_free()
		var ready: bool = accepted_terminal and drained and leases_retired
		return {"success":ready,"status":"READY" if ready else "PENDING","accepted_claims_terminal":accepted_terminal,"code_leases_retired":leases_retired,"coordinator_id":coordinator.get_instance_id(),"owner_session_id":session.original_budget_session_id(),"claims":claims,"original_ledger_sizes":sizes,"original_retire_head":coordinator.get("_retire_head"),"original_retire_tail":coordinator.get("_retire_tail")}

class MainIO extends Binding:
	var _last_publication: Dictionary
	var _last_io: Dictionary
	func service_original_source_main_io_cleanup(session: RefCounted, core: RefCounted, frame: Dictionary) -> bool:
		if not _bound() or not is_same(_session.get_ref(),session) or frame != _host.current_clock_frame() or frame.get("closing_session") != true or frame.get("source_boundary") != "NODE_PROCESS_SERVICE": return false
		if core != null and (core.owner_thread_id() != _owner or not is_same(core.original_source_session(),session)): return false
		var publication: Variant = frame.get("closing_process_publication")
		if not publication is Dictionary or publication.get("phase") != "NODE_PROCESS_SERVICE": return false
		var io: Variant = publication.get("main_io")
		if not io is Dictionary or io.get("contract_id") != "hardcore.source.main_io_observation.v1" or io.get("owner_session_id") != session.original_budget_session_id() or io.get("bridge_generation") != publication.get("bridge_generation") or io.get("actual_main_process_frame") != publication.get("main_process_frame") or io.get("physical_owners_retained") != true or io.get("status") not in ["OWNERS_RETAINED","BUSINESS_DRAINED"]: return false
		if core != null and io.get("world_runtime_id") != core.current_world_identity().get("world_runtime_id"): return false
		if not _last_publication.is_empty():
			if publication.sequence < _last_publication.sequence: return false
			if publication.sequence == _last_publication.sequence: return publication == _last_publication
		_last_publication = publication; _last_io = io
		return true # Actual Native SERVICE consumption; not a Session terminal.
	func actual_original_world_io_retention_state(core: RefCounted) -> Dictionary:
		if not _bound() or core == null or not is_same(core.original_source_session(),_session.get_ref()): return _fail("actual_same_IO_Core_required",{},"INVALID")
		if _last_io.is_empty(): return {"success":false,"status":"PENDING"}
		if _last_io.get("world_runtime_id") != core.current_world_identity().get("world_runtime_id") or _last_io.get("physical_owners_retained") != true: return _fail("actual_Main_IO_retention_Root_changed",{},"INVALID")
		return {"success":true,"status":"READY","world":core.current_world_identity(),"core_object_id":core.get_instance_id(),"actual_io_owners_retained":true,"actual_native_receipt":true,"actual_closing_publication":_last_publication,"actual_main_io":_last_io}
	func actual_original_session_io_retirement_state(session: RefCounted) -> Dictionary:
		if not _bound() or not is_same(_session.get_ref(),session): return _fail("actual_same_IO_Session_required",{},"INVALID")
		if _last_io.is_empty() or _last_io.status != "BUSINESS_DRAINED" or not session.get("_live_tickets").is_empty() or session.original_frame_budget().live_obligations() != 0: return {"success":false,"status":"PENDING"}
		return {"success":true,"status":"READY","owner_session_id":session.original_budget_session_id(),"actual_native_receipt":true,"loaders_terminal":true,"accepted_callbacks_terminal":true,"renderer_consumers_retired":true,"actual_closing_publication":_last_publication,"actual_main_io":_last_io}

class ViewTransport extends Binding:
	func original_world_view_ready_receipt(world: Dictionary, player_id: int, proof: Dictionary) -> Dictionary:
		if not _world(world) or proof != _publication: return _fail("actual_same_world_view_publication",{},"INVALID")
		return _loading_call("view_ready",[world,player_id])
	func publish_original_world_view_prefix(prefix: Dictionary) -> Dictionary:
		if not _bound() or _core == null or _core.get_ref() == null: return _fail("actual_bound_Source_World_publisher_required",{},"INVALID")
		var journal: RefCounted = _session.get_ref().original_event_journal()
		# Current producer equality is independent of Native acceptance. A full
		# FIFO leaves this intention unregistered and grants no Main receipt.
		if not journal.is_current_original_prefix(prefix): return _fail("actual_current_original_journal_prefix_required",{},"INVALID")
		if not _host.has_method("try_register_published_original_main_prefix"): return _fail("actual_Native_try_publication_API_required",{},"INVALID")
		var accepted: Dictionary = _host.try_register_published_original_main_prefix(prefix)
		match accepted.get("status"):
			"PENDING": return accepted
			"READY":
				# Source cannot consume a later ACK between this real Native
				# acceptance and its matching original producer registration.
				if not journal.register_normal_publication(prefix): return _fail("actual_accepted_original_journal_registration",{},"INVALID")
				return accepted
			_:
				# Keep the original bounded shape diagnosis on true rejection;
				# ordinary queue pressure neither faults nor logs every frame.
				var actual: Dictionary = _host.status()
				var operations := {}
				for event: Dictionary in prefix.events:
					var operation := str(event.get("operation",event.get("event",event.get("kind",""))))
					operations[operation] = int(operations.get(operation,0)) + 1
				print("HC_PUBLISHED_PREFIX_REJECTED ",JSON.stringify({"event_count":prefix.events.size(),"wire_bytes":var_to_bytes(prefix).size(),"through_ordinal":prefix.through_ordinal,"source_applied_ordinal":journal.applied_ordinal(),"native_applied_ordinal":actual.get("original_main_applied_prefix"),"unsettled_prefixes":actual.get("unsettled_original_published_prefixes"),"primitive_in_flight":actual.get("original_primitive_in_flight"),"operations":operations,"admission":accepted}))
				return _fail("actual_Native_original_prefix_rejected",accepted,"INVALID")
	func actual_original_world_view_exit_receipt(world: Dictionary) -> Dictionary:
		if not _world(world): return _fail("actual_same_world_exit",{},"INVALID")
		var result: Dictionary = _loading_call("world_view_exit_state",[world])
		if result.get("status") == "READY" and (result.get("world") != world or result.get("actual_original_exit") != true): return _fail("actual_world_view_exit_receipt_identity",{},"INVALID")
		return result
	func actual_original_actor_view_free_receipt(identity: Dictionary) -> Dictionary:
		if not _bound() or _core == null or _core.get_ref() == null or not preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts_retiring_actor(identity): return _fail("actual_original_retiring_actor_identity",{},"INVALID")
		var core: RefCounted = _core.get_ref()
		var handle: Object = core.actor_handle_for_runtime_id(int(identity.runtime_id))
		if handle == null or handle.kind() not in [&"player",&"enemy"] or handle.get("_world") != identity.world or handle.model() == null or handle.model().current_life() != identity.life_generation: return _fail("actual_canonical_retiring_actor_required",{},"INVALID")
		var scope: RefCounted = core.get("_actor_scopes").get(identity.runtime_id)
		if scope == null or not scope.exit_callbacks_complete: return _fail("actual_original_actor_exit_before_Node_retirement",{},"INVALID")
		var result: Dictionary = _loading_call("actor_view_free_state",[identity])
		if result.get("status") == "READY" and (result.get("actor_identity") != identity or result.get("world") != identity.world or result.get("runtime_id") != identity.runtime_id or result.get("actual_node_absent") != true or result.get("actual_assets",{}).get("actual_physical_pins_released") != true or result.get("actual_assets",{}).get("actual_original_obligations_terminal") != true or not result.get("service_id") is int or result.service_id < 0 or not result.get("metadata_released") is bool or not result.get("renderer_registration_retired") is bool): return _fail("actual_actor_view_free_receipt_identity",{},"INVALID")
		if result.get("status") == "READY" and result.actual_assets.has("owner_descriptor") and result.actual_assets.owner_descriptor.get("actor_identity") != result.get("actual_presented_identity"): return _fail("actual_actor_asset_owner_retirement_identity",{},"INVALID")
		return result

class AudioProjection extends Binding:
	func capture_original_audio_source(actor_id: int) -> Dictionary:
		if not _bound() or _core == null or _core.get_ref() == null: return _fail("actual_audio_Core_required")
		var core: RefCounted = _core.get_ref()
		var handle: Object = core.actor_handle_for_runtime_id(actor_id)
		if handle == null or handle.kind() != &"enemy": return _fail("actual_audio_Enemy_identity_required",{},"INVALID")
		var identity: Dictionary = handle.identity()
		var model: RefCounted = handle.model()
		if identity.get("world") != core.current_world_identity() or model == null: return _fail("actual_current_audio_Source_owner",{},"INVALID")
		var result := {"actor_identity":identity,"monster_id":model.monster_id,"position_screen_px":model.global_position,"source_present":handle.runtime_object_is_present(),"source_inside_world":handle.is_inside_world(),"source_retiring":handle.is_queued_for_retirement()}
		if not preload("res://scripts/gameplay/world/world_audio_source_contract.gd").accepts(result): return _fail("actual_audio_Source_pose",{},"INVALID")
		return result

class UiLoading extends Binding:
	var _panel_observations: Dictionary = {}
	var _ui_calls_active: Dictionary = {}
	var _map_warm_calls: Dictionary = {}
	func execute_original_map_warm(request: Dictionary) -> Dictionary:
		if not _bound() or not preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts_map_warm_request(request) or not _world(request.world_context): return _fail("actual_Source_map_warm_request_required",{},"INVALID")
		var core: RefCounted = _core.get_ref()
		var root: RefCounted = core.original_root_owner()
		if request.source_root_id != root.get_instance_id() or request.owner_session_id != _session.get_ref().original_budget_session_id() or request.transition_id != root.get("_active_map_transition_id") or request.coordinator_generation != root.original_map_coordinator_generation() or not root.original_map_coordinator_is_current(int(request.coordinator_generation)): return _fail("actual_Source_Root_map_warm_boundary_required",{},"INVALID")
		var budget: RefCounted = _session.get_ref().original_frame_budget()
		if budget.snapshot().open_scopes != 0 or budget.resource_external_segment_active(): return _fail("map_warm_await_must_not_hold_scalar_or_external_scope",{},"INVALID")
		if _host.capabilities().get("source_application_loading_cps") != true: return _fail("actual_map_warm_application_CPS_required")
		var key: String = str(request.transition_id)+":"+str(request.operation)
		if _map_warm_calls.has(key): return _fail("same_Source_map_warm_caller_already_waiting",{},"INVALID")
		_map_warm_calls[key] = request
		var result: Dictionary = await _await_loading_call("map_warm_start",[request])
		while result.get("success") == true and result.get("completed") != true:
			if result.get("request") != request or result.get("actual_Main_capture") != true: return _fail("actual_accepted_map_warm_observation_required",{},"INVALID")
			# Existing Source service signals and the same single Session Native
			# application consumer deliver every observation. Main never waits on S.
			if not await _next_actual_application_service(): return _fail("actual_map_warm_Source_service_unavailable",{},"INVALID")
			result = await _await_loading_call("map_warm_state",[request])
		if result.get("success") != true or result.get("completed") != true:
			if result.get("status") == "CANCELLED" and result.get("accepted") == false: _map_warm_calls.erase(key)
			return result # Unknown accepted debt remains recorded for factual close.
		if result.get("request") != request or result.get("actual_Main_capture") != true or not result.get("result") is Dictionary or not result.get("completed_usec") is int or result.completed_usec < int(result.get("started_usec",0)): return _fail("actual_completed_map_warm_receipt_required",{},"INVALID")
		_map_warm_calls.erase(key)
		return result.result
	func has_pending_original_map_warm() -> bool:
		return not _map_warm_calls.is_empty()
	func _remember_panel(result: Dictionary, hud_id: int) -> void:
		if result.get("success") == true and result.get("hud_id") == hud_id and result.get("actual_Main_capture") == true and result.get("actual_Main_process_frame") is int:
			_panel_observations[hud_id] = result.duplicate(true)
	func prewarm_all_panels(hud_id: int, menu_id: int) -> bool:
		if not _bound() or _host.capabilities().get("source_application_loading_cps") != true:
			_fail("Native_original_UI_Loading_CPS_and_reply_required"); return false
		var result: Dictionary = await _await_loading_call("prewarm_panels",[hud_id,menu_id])
		_remember_panel(result,hud_id)
		while result.get("success") == true and result.get("completed") != true:
			if _session.get_ref().actual_original_clock_frame().get("closing_session") == true: return false
			if not await _next_actual_application_service(): return false
			result = await _await_loading_call("panel_state",[hud_id])
			_remember_panel(result,hud_id)
		return result.get("success") == true and result.get("completed") == true
	func _run_original_ui_call(operation: String, arguments: Array, hud_id: int) -> void:
		var key: String = operation + ":" + str(hud_id)
		if _ui_calls_active.has(key): return
		_ui_calls_active[key] = true
		var result: Dictionary = await _await_loading_call(operation,arguments)
		_remember_panel(result,hud_id)
		_ui_calls_active.erase(key)
		if result.get("status") == "CANCELLED" and result.get("accepted") == false: return
		if result.get("success") != true and result.get("status") not in ["PENDING","BUSY","BACKPRESSURE"] and _bound():
			_session.get_ref().fault("actual_original_UI_application_call_failed",result)
	func _panel_observation(hud_id: int) -> Dictionary:
		if not _bound(): return {}
		# Query through the same admitted asynchronous call. This synchronous
		# getter returns only the last actual Main observation; a pending query
		# is never fabricated into completion or a zero-cost resource result.
		# A synchronous gameplay getter may run inside its caller's scalar
		# budget. Only an actual service boundary can start a yielding refresh;
		# the getter still reports its last real observation while that scope is
		# open, rather than opening a continuation that faults on its first wait.
		if _bound():
			var budget: RefCounted = _session.get_ref().original_frame_budget()
			if budget.snapshot().open_scopes == 0 and not budget.resource_external_segment_active():
				Callable(self,"_run_original_ui_call").call("panel_state",[hud_id],hud_id)
		return _panel_observations.get(hud_id,{})
	func start_original_catalog_icon_prewarm(hud_id: int, background_mode: bool) -> void:
		Callable(self,"_run_original_ui_call").call("catalog_icons",[hud_id,background_mode],hud_id)
	func actual_original_panels_prewarmed(hud_id: int) -> bool:
		return _panel_observation(hud_id).get("completed") == true
	func actual_original_panel_prewarm_diagnostic(hud_id: int) -> Dictionary:
		return _panel_observation(hud_id).get("diagnostic",{})
	func actual_original_catalog_icon_prewarm_complete(hud_id: int) -> bool:
		return _panel_observation(hud_id).get("catalog_icon_prewarm_complete") == true
	func start_original_budgeted_panel_prewarm(hud_id: int, menu_id: int) -> void:
		Callable(self,"_run_original_ui_call").call("budgeted_panels",[hud_id,menu_id],hud_id)

class MapAdmission extends Binding:
	var _arrived_scopes: Array[Dictionary] = []
	var _release_pending_scope: Dictionary = {}
	func has_pending_original_map_scope_release() -> bool: return not _release_pending_scope.is_empty()
	func request_original_map_loading_boundary(descriptor: Dictionary, transition: String, generation: int, map_id: int) -> Dictionary:
		if not _world(descriptor.get("world_context",{})) or descriptor != _publication.get("map_loading",{}).get("owner_descriptor",{}) or transition.is_empty() or generation < 0 or map_id < 0: return _fail("actual_map_request_identity",{},"INVALID")
		var result: Dictionary = await _await_loading_call("map_scope",[descriptor,transition,generation,map_id])
		if result.get("status") != "READY": return result
		var scope: Dictionary = result.get("scope",{})
		if not _host.verify_original_map_loading_scope(scope,descriptor,transition,generation,map_id): return _fail("actual_Native_map_scope_rejected",{},"INVALID")
		# Use the actual producer-issued full scope as the poll identity. Never
		# allocate a fake request serial or rewrite LOADING to RETAINED locally.
		return {"status":"ACCEPTED","identity":scope.duplicate(true)}
	func poll_original_map_loading_boundary(identity: Dictionary) -> Dictionary:
		if not _bound() or identity.get("contract_id") != "source.map.loading.scope.v1" or not identity.get("owner_descriptor") is Dictionary: return _fail("actual_map_scope_identity_required",{},"INVALID")
		var descriptor: Dictionary = identity.owner_descriptor
		if not _arrived_scopes.has(identity) and (not _world(descriptor.get("world_context",{})) or descriptor != _publication.get("map_loading",{}).get("owner_descriptor",{})): return _fail("actual_current_or_retained_arrived_map_owner_required",{},"INVALID")
		if not _host.verify_original_map_loading_scope(identity,descriptor,str(identity.get("transition_id","")),int(identity.get("coordinator_generation",-1)),int(identity.get("map_id",-1))): return _fail("actual_map_scope_no_longer_current",{},"INVALID")
		return {"status":"READY","scope":identity.duplicate(true)}
	func release_original_map_loading_boundary(scope: Dictionary) -> Dictionary:
		if not _bound() or _core == null or _core.get_ref() == null: return _fail("actual_Map_release_Core_required",{},"INVALID")
		var root: RefCounted = _core.get_ref().original_root_owner()
		var coordinator: RefCounted = root.get("_world_bootstrap_coordinator") if root != null else null
		var transport: RefCounted = root.original_map_loading_transport() if root != null else null
		if coordinator == null or transport == null or transport.get("_scope") != scope: return _fail("actual_canonical_Map_release_scope",{},"INVALID")
		var current: Dictionary = poll_original_map_loading_boundary(scope)
		if current.get("status") != "READY":
			if _session.get_ref().actual_original_clock_frame().get("closing_session") != true: return current
			# Main can finish an internally-owned close before a suspended old
			# business callback observes its final scope. Only the authenticated
			# actual SERVICE terminal receipt may discharge that same old scope.
			_release_pending_scope = scope.duplicate(true)
			return await _await_actual_terminal_map_release(scope,coordinator,transport)
		# The producer, not this S wrapper, owns scope state and resident pins.
		_release_pending_scope = scope.duplicate(true)
		while true:
			var result: Dictionary = await _await_loading_call("release_map_scope",[scope])
			if result.get("success") == true and result.get("status") == "READY":
				if not coordinator.acknowledge_actual_original_map_scope_release(scope,result):
					if _session.get_ref().actual_original_clock_frame().get("closing_session") == true: return await _await_actual_terminal_map_release(scope,coordinator,transport)
					return _fail("actual_Source_Map_release_ack_rejected",{},"INVALID")
				var confirmed: Dictionary = await _await_loading_call("release_map_scope",[result.scope])
				while confirmed.get("success") == true and confirmed.get("status") == "PENDING":
					if not await _next_actual_application_service(): return _fail("actual_Map_release_confirmation_service",{},"INVALID")
					confirmed = await _await_loading_call("release_map_scope",[result.scope])
				if confirmed != result: return _fail("actual_same_Map_release_confirmation_receipt",{},"INVALID")
				_release_pending_scope = {}
				_arrived_scopes.erase(scope)
				return result
			if result.get("status") != "PENDING" or result.get("success") != true: return result
			# Native may already hold the same scope's RETAINED stage. Resume the
			# exact accepted release input, rather than re-poll old LOADING bytes.
			if not await _next_actual_application_service(): return _fail("actual_Map_release_service_unavailable",{},"INVALID")
		return _fail("actual_Map_release_tail",{},"INVALID")
	func _await_actual_terminal_map_release(scope: Dictionary, coordinator: RefCounted, transport: RefCounted) -> Dictionary:
		while true:
			var receipt: Dictionary = coordinator.get("_actual_map_owner_terminal_receipt")
			var retained: Dictionary = scope.duplicate(true); retained.state = "RETAINED"
			if not receipt.is_empty():
				if receipt.get("contract_id") != "hardcore.main.map_owner.terminal.v1" or receipt.get("scope") != retained or receipt.get("producer_runtime_id") != scope.get("producer_runtime_id") or receipt.get("owner_descriptor",{}).get("world_context") != _core.get_ref().current_world_identity(): return _fail("actual_closed_Map_scope_terminal_identity",{},"INVALID")
				_release_pending_scope = {}; _arrived_scopes.erase(scope)
				return {"success":true,"status":"READY","scope":retained,"actual_owner_terminal":receipt.duplicate(true)}
			var budget: RefCounted = _session.get_ref().original_frame_budget()
			if budget.snapshot().open_scopes != 0 or budget.resource_external_segment_active() or _host.current_clock_frame().get("closing_session") != true or transport.get("_scope") != scope or transport.has_pending_original_map_continuation(): return _fail("actual_Map_terminal_wait_qualification",{},"INVALID")
			await transport.actual_original_map_close_service
		return _fail("actual_Map_terminal_wait_tail",{},"INVALID")
	func _next_actual_application_service() -> bool:
		if not _bound() or _core == null or _core.get_ref() == null: return false
		var session: RefCounted = _session.get_ref()
		var budget: RefCounted = session.original_frame_budget()
		if budget.snapshot().open_scopes != 0 or budget.resource_external_segment_active(): return false
		if session.actual_original_clock_frame().get("closing_session") != true:
			await _core.get_ref().profile_runtime.next_service()
		if not _bound(): return false
		# A normal wait can cross close admission. Profile's SIGNAL watermark
		# may wake it, but only the real Map NODE_PROCESS_SERVICE may settle it.
		if session.actual_original_clock_frame().get("closing_session") == true:
			var root: RefCounted = _core.get_ref().original_root_owner()
			var transport: RefCounted = root.original_map_loading_transport() if root != null else null
			if transport == null: return false
			await transport.actual_original_map_close_service
			var frame: Dictionary = session.actual_original_clock_frame()
			return _bound() and frame.get("phase") == "P_CLOSE_SERVICE" and frame.get("source_boundary") == "NODE_PROCESS_SERVICE" and budget.snapshot().open_scopes == 0 and not budget.resource_external_segment_active()
		return _bound()

static func create_original_providers(host: Object) -> Dictionary:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or host == null or not host.is_class("HardCoreSimulationHost"): return {"success":false,"status":"MISSING","errors":["actual_Native_S_application_factory_required"]}
	var services := {"directory":Directory.new(),"feature_retirement":FeatureRetirement.new(),"main_io":MainIO.new(),"WorldViewTransport":ViewTransport.new(),"WorldAudioProjection":AudioProjection.new(),"WorldUiLoading":UiLoading.new(),"WorldMapLoadingAdmission":MapAdmission.new()}
	for port: RefCounted in services.values():
		if not port.configure_owner(host): return {"success":false,"status":"MISSING","errors":["actual_S_application_provider_construction"]}
	if not services.directory.bind_original_world_context(services.WorldViewTransport): return {"success":false,"status":"MISSING","errors":["actual_directory_view_context_attachment"]}
	return {"success":true,"services":services}

## Bind the existing concrete owners; construction alone does not authorize a
## Main call, claim adoption, view readiness or physical owner retirement.
static func _is_original_role(role: String, port: Variant) -> bool:
	match role:
		"directory": return port is Directory
		"feature_retirement": return port is FeatureRetirement
		"main_io": return port is MainIO
		"WorldViewTransport": return port is ViewTransport
		"WorldAudioProjection": return port is AudioProjection
		"WorldUiLoading": return port is UiLoading
		"WorldMapLoadingAdmission": return port is MapAdmission
	return false

static func bind_original_session_services(session: RefCounted, host: Object, services: Dictionary) -> bool:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or session == null or session.get_script() != SessionScript or session.owner_thread_id() != OS.get_thread_caller_id() or session.get("_host") != host: return false
	var seen: Dictionary = {}
	# Validate the complete fixed set BEFORE mutating any WeakRef. An absent,
	# aliased, foreign or already-bound owner cannot leave a half-bound set.
	for role: String in APPLICATION_ROLES:
		var port: Variant = services.get(role)
		if not _is_original_role(role,port) or port.owner_thread_id() != session.owner_thread_id() or port.get("_host") != host or port.get("_session") != null or seen.has(port.get_instance_id()): return false
		seen[port.get_instance_id()] = true
	for role: String in APPLICATION_ROLES:
		if not services[role].bind_original_session(session):
			session.fault("actual_application_session_bind_changed_after_validation",{"role":role})
			return false
	return true

static func bind_original_world_services(session: RefCounted, core: RefCounted, publication: Dictionary, services: Dictionary) -> bool:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or session == null or session.get_script() != SessionScript or core == null or core.owner_thread_id() != session.owner_thread_id() or not is_same(core.original_source_session(),session): return false
	if publication.get("contract_id") != "world.Main.view_services.publication.v1" or publication.get("world_context") != core.current_world_identity(): return false
	for role: String in APPLICATION_ROLES:
		var port: Variant = services.get(role)
		if not _is_original_role(role,port) or port.owner_thread_id() != session.owner_thread_id() or port.get("_session") == null or not is_same(port.get("_session").get_ref(),session): return false
		var old: WeakRef = port.get("_core")
		if old != null and old.get_ref() != null:
			if is_same(old.get_ref(),core):
				if port.get("_publication") != publication: return false
			elif not old.get_ref().is_original_world_closed(): return false
	for role: String in APPLICATION_ROLES:
		if not services[role].bind_original_world(core,publication):
			session.fault("actual_application_world_bind_changed_after_validation",{"role":role})
			return false
	return true

static func release_original_world_service_references(session: RefCounted, core: RefCounted, root: RefCounted, services: Dictionary) -> bool:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or session == null or session.get_script() != SessionScript or core == null or core.owner_thread_id() != session.owner_thread_id() or not is_same(core.original_source_session(),session) or not is_same(core.original_root_owner(),root): return false
	# Called only after the actual original Root exit and final child free.
	# Accepted application continuations must finish before their target drops.
	if root.get("_exit_step") != 17 or root.get("_children_exited") != true: return false
	for role: String in APPLICATION_ROLES:
		var port: Variant = services.get(role)
		if not _is_original_role(role,port) or not port._world(core.current_world_identity()) or not is_same(port.get("_session").get_ref(),session): return false
		var live: RefCounted = port.get("_application_live")
		if live != null and not live.live_operations_drained(): return false
	for role: String in APPLICATION_ROLES:
		services[role].set("_main_service_released",true)
		services[role].set("_main_service_reference",null)
	# The last proxy invokes the existing real release_reference path. Physical
	# release/debt is still checked by the existing Session retirement verifier.
	return not session.feature_resource_session().primitives.failed()

## Stage current routing only. Captured loading proofs and old scope records
## stay immutable; Native authenticates the complete arrival transaction.
static func can_commit_original_map_arrival(session: RefCounted, core: RefCounted, transaction: Dictionary, services: Dictionary) -> bool:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or session == null or session.get_script() != SessionScript or core == null or session.owner_thread_id() != OS.get_thread_caller_id() or not is_same(core.original_source_session(),session): return false
	if not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction) or transaction.get("owner_session_id") != session.original_budget_session_id() or transaction.get("world_core_id") != core.get_instance_id() or core.current_world_identity() != transaction.before_world: return false
	var staged: Dictionary = {}
	for role: String in APPLICATION_ROLES:
		var port: Variant = services.get(role)
		if not _is_original_role(role,port) or port.owner_thread_id() != session.owner_thread_id() or port.get("_session") == null or not is_same(port.get("_session").get_ref(),session) or port.get("_core") == null or not is_same(port.get("_core").get_ref(),core): return false
		var publication: Dictionary = port.get("_publication")
		if publication.get("world_context") != transaction.before_world: return false
		var live: RefCounted = port.get("_application_live")
		if live != null and live.has_accepted_call(): return false
		var prior: Dictionary = port.get("_map_arrival_prepared")
		if not prior.is_empty() and prior.transaction != transaction: return false
		var next: Dictionary = publication.duplicate(true)
		next.world_context = transaction.after_world.duplicate(true)
		if next.has("map_loading"):
			if not next.map_loading is Dictionary or not next.map_loading.get("owner_descriptor") is Dictionary or next.map_loading.owner_descriptor.get("world_context") != transaction.before_world: return false
			next.map_loading.owner_descriptor.world_context = transaction.after_world.duplicate(true)
		staged[role] = {"transaction":transaction.duplicate(true),"before":publication,"after":next}
	# Complete validation precedes any staging mutation, and no await splits
	# the owner-thread transaction. Staging itself grants no new world access.
	for role: String in APPLICATION_ROLES: services[role].set("_map_arrival_prepared",staged[role])
	return true

static func commit_original_map_arrival(session: RefCounted, core: RefCounted, transaction: Dictionary, services: Dictionary) -> bool:
	if not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction): return false
	if OS.get_thread_caller_id() == OS.get_main_thread_id() or session == null or session.get_script() != SessionScript or core == null or session.owner_thread_id() != OS.get_thread_caller_id() or not is_same(core.original_source_session(),session) or core.current_world_identity() != transaction.get("after_world"): return false
	for role: String in APPLICATION_ROLES:
		var port: Variant = services.get(role)
		if not _is_original_role(role,port) or port.get("_session") == null or not is_same(port.get("_session").get_ref(),session) or port.get("_core") == null or not is_same(port.get("_core").get_ref(),core): return false
		var staged: Dictionary = port.get("_map_arrival_prepared")
		if staged.is_empty() or staged.transaction != transaction or staged.before != port.get("_publication"): return false
	for role: String in APPLICATION_ROLES:
		var port: RefCounted = services[role]
		var staged: Dictionary = port.get("_map_arrival_prepared")
		port.set("_publication",staged.after)
		port.set("_map_arrival_prepared",{})
		if port is MapAdmission: port._arrived_scopes.append(transaction.loading_scope.duplicate(true))
	return true

static func missing_native_contracts(host: Object) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for method: String in ["register_published_original_main_prefix"]:
		if not host.has_method(method): missing.append({"method":method,"status":"MISSING"})
	for capability: String in ["source_application_loading_call","source_application_loading_cps"]:
		if host.capabilities().get(capability) != true: missing.append({"capability":capability,"status":"MISSING"})
	return missing
