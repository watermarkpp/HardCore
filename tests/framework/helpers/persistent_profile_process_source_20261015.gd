extends RefCounted
## Actual Session/Scope/Profile bodies on Native S; intentionally does not claim
## full selected-profile adoption, World construction, resource factory or APK.
const Session := preload("res://scripts/gameplay/source/source_session.gd")
const Profile := preload("res://scripts/gameplay/profile/profile_model.gd")
const Runtime := preload("res://scripts/gameplay/profile/profile_runtime_port.gd")
const Budget := preload("res://scripts/gameplay/source/source_session_budget.gd")
const Clock := preload("res://scripts/gameplay/source/source_session_clock.gd")
const Router := preload("res://scripts/gameplay/source/source_session_actor_router.gd")
const Actors := preload("res://scripts/gameplay/enemy/enemy_owner_service_actor_access.gd")
const ProfileBudget := preload("res://scripts/gameplay/world/world_profile_budget_port.gd")
const Coordinator := preload("res://scripts/features/runtime/feature_resource_owner_coordinator.gd")
const Applications := preload("res://scripts/gameplay/source/source_application_providers.gd")
const Primitives := preload("res://scripts/features/runtime/feature_resource_owner_primitives.gd")
const Prefix := preload("res://scripts/gameplay/world/world_resource_prefix_transport.gd")
const Transport := preload("res://scripts/gameplay/source/source_session_transport.gd")
const Journal := preload("res://scripts/gameplay/world/world_original_event_journal.gd")
const Engagement := preload("res://scripts/gameplay/world/world_owner_engagement_window.gd")
const PersistentTree := preload("res://scripts/gameplay/source/source_persistent_path_tree.gd")
var _host: Object
var _session: RefCounted
var _profile: RefCounted
var _checks: Array[Dictionary] = []
var _done := false
var _ordinary := 0
var _paused := 0
var _scope_id := 0
var _before := 0.0
var _signal_count := 0
var _budget: RefCounted
var _actors: RefCounted
var _clock: RefCounted
var _writer: RefCounted
var _submitted := false
var _resource_ready := false
var _exercise_live := false
var _live_request: Dictionary = {}
var _live_reservation: Dictionary = {}
var _live_submission: Dictionary = {}
var _live_settlement: Dictionary = {}
var _live_done := false
var _live_start_process := 0
var _live_prefix_retired := false
func _check(ok: bool, label: String) -> void:
	_checks.append({"passed":ok,"label":label})
	if not ok: print("PERSISTENT_SOURCE_CHECK_FAILED ",label)
func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_exercise_live = boot.get("exercise_main_live_feature") == true
	_session = Session.new()
	_session.set("_host",host)
	_check(OS.get_thread_caller_id() != OS.get_main_thread_id(),"actual Native S owns persistent state")
	_check(boot.root_membership.get("success") == true,"actual root membership is available without invented positions")
	if boot.root_membership.get("success") != true: _done = true; return
	var tree := PersistentTree.new()
	var publication: Dictionary = boot.root_membership.duplicate(true)
	publication.contract_id = "source.path.main_handoff.v1"
	# Read-only membership component, no scheduler birth/state adoption claimed.
	_check(publication.scheduler_lookup.get("found") == false,"this actual isolated tree has no preexisting scheduler requiring a separate state handoff")
	_check(tree.configure_bootstrap(host,publication),"real persistent Source root ledger consumes actual Main membership")
	_session.set("_services",{"source_tree":tree})
	_check(_session.has_method("configure_original_persistent_process_scopes"),"Session adopts the real Main persistent callback scopes")
	if not _session.has_method("configure_original_persistent_process_scopes"):
		_done = true
		return
	var application_api: Script = Applications
	var has_session_binding := false
	for method: Dictionary in application_api.get_script_method_list():
		if method.name == &"bind_original_session_services": has_session_binding = true
	_check(has_session_binding,"actual application owners bind once to the sole production Session before Profile adoption")
	if not has_session_binding: _done = true; return
	var applications: Dictionary = Applications.create_original_providers(host)
	_check(applications.get("success") == true and applications.services.size() == Applications.APPLICATION_ROLES.size(),"all seven actual application owners are constructed on the same Native S")
	var incomplete: Dictionary = applications.services.duplicate(false)
	incomplete.erase("WorldAudioProjection")
	_check(not application_api.bind_original_session_services(_session,host,incomplete),"missing actual owner rejects the set before binding any owner")
	for port: RefCounted in applications.services.values():
		_check(port.get("_session") == null,"rejected partial installation leaves every genuine owner unbound")
	var aliased: Dictionary = applications.services.duplicate(false)
	aliased.WorldAudioProjection = aliased.directory
	_check(not application_api.bind_original_session_services(_session,host,aliased),"one owner cannot silently replace two distinct production services")
	var wrong_role: Dictionary = applications.services.duplicate(false)
	var second_set: Dictionary = Applications.create_original_providers(host)
	wrong_role.WorldAudioProjection = second_set.services.directory
	_check(not application_api.bind_original_session_services(_session,host,wrong_role),"distinct wrong-role owner is rejected without relying on interface names")
	_check(application_api.bind_original_session_services(_session,host,applications.services),"the complete actual application set binds to exactly one Session")
	for port: RefCounted in applications.services.values():
		_check(is_same(port.get("_session").get_ref(),_session),"each owner points to the same actual production Session")
	_check(not application_api.bind_original_session_services(_session,host,applications.services),"a second binding cannot reset existing Session owners")
	var before_call: int = host.next_original_operation_sequence()
	var refused_call: Dictionary = applications.services.directory.prepare_directory("res://assets/data")
	_check(refused_call.get("status") == "MISSING" and refused_call.get("error") == "actual_Loading_or_application_CPS_required" and host.next_original_operation_sequence() == before_call,"bound but unprepared Session cannot spend a Native operation or claim directory readiness outside actual Loading")
	var coordinator := Coordinator.new()
	_check(coordinator.has_method("configure_original_idle_handoff"),"Source coordinator preserves original Main counters and cursors instead of restarting")
	if not coordinator.has_method("configure_original_idle_handoff"):
		_done = true
		return
	var restored: bool = coordinator.call("configure_original_idle_handoff",boot.coordinator_idle)
	_check(restored,"actual captured Main idle state restores atomically into the real Source constructor")
	for key: String in boot.coordinator_idle.fields:
		_check(coordinator.get(key) == boot.coordinator_idle.fields[key],"original coordinator field preserved:"+key)
	_check(not coordinator.call("configure_original_idle_handoff",boot.coordinator_idle),"second idle handoff cannot reset existing Source cursors")
	var probe: Dictionary = boot.coordinator_idle.duplicate(true)
	# Explicit component inputs: nonzero settled cursors represent completed old
	# work. This is not a claim that a full selected session has been admitted.
	for key: String in probe.fields:
		if probe.fields[key] is int: probe.fields[key] = 37
	var nonzero := Coordinator.new()
	_check(bool(nonzero.call("configure_original_idle_handoff",probe)),"valid nonzero settled cursors may be adopted without replaying work")
	for key: String in probe.fields:
		_check(nonzero.get(key) == probe.fields[key],"nonzero constructor field survives actual restore:"+key)
	var invalid: Dictionary = probe.duplicate(true)
	invalid.fields._tail += 1
	var rejected := Coordinator.new()
	_check(not rejected.call("configure_original_idle_handoff",invalid),"unsettled old queue cursor cannot be relabeled idle")
	_check(rejected.get("_next_request") == 0 and rejected.get("_tail") == 0,"failed restore never partially mutates Source counters")
	var accepted: bool = _session.call("configure_original_persistent_process_scopes",boot.origins)
	_check(accepted,"the one Session accepts exact Main paths/flags before disabling Main")
	if not accepted: _done = true; return
	_check(not _session.call("configure_original_persistent_process_scopes",boot.origins),"an explicit second scope adoption is rejected without resetting qualification")
	var wrong: Dictionary = boot.origins.duplicate(true)
	wrong.profile.source_sha256 = "0".repeat(64)
	var refused := Session.new()
	_check(not refused.configure_original_persistent_process_scopes(wrong),"an origin from different Script bytes is rejected before installation")
	var router := Router.new(_session)
	_actors = Actors.new()
	_check(_actors.configure_owner(router,router),"real owner-local ProcessLink/actor router installed")
	for scope: RefCounted in [_session.original_profile_process_scope(),_session.feature_resource_process_scope(),_session.get("_profile_receipt_scope")]:
		_check(_actors.register_process_owner(scope),"the same original scope is registered in the real service-owner ledger")
	_clock = Clock.new(_session,host,boot.settings)
	_budget = Budget.new()
	_check(_budget.configure_owner({"Engine":_clock,"Time":_clock,"ProjectSettings":_clock,"phase":_clock},_actors),"one actual Source budget uses the real Native clock and Main settings")
	_session.set("_id",115154)
	_session.set("_phase","LOADING")
	_session.set("_clock",_clock)
	_session.set("_budget",_budget)
	_session.set("_actor_router",router)
	_session.set("_service_actors",_actors)
	_session.set("_engagement",Engagement.new())
	_session.set("_journal",Journal.new(_session,115154,1))
	_check(_budget.configure_resource_continuations(Callable(_session,"_resource_failure")) and _budget.configure_session(115154,_session.cold_resource_calls_allowed),"real resource continuation budget retains exact Session cold gate")
	var prefix := Prefix.new(_session,host)
	var transport := Transport.new(_session,host,prefix)
	var primitives := Primitives.new()
	_check(primitives.configure_owner(_session,transport,_budget,_clock,boot.feature_resources),"real Source endpoint consumes actual Main registered references")
	_check(coordinator.configure_owner(primitives,_budget,_session.feature_resource_process_scope()),"restored actual coordinator and persistent Feature scope share the same budget")
	_session.set("_feature",{"success":true,"coordinator":coordinator,"primitives":primitives})
	_check(coordinator.configure_original_issued_claim_bridge(host,_session),"Native Source binding accepts exact current coordinator, original Session and shared ledger")
	_session.set("_persistent_world_context",boot.world_identity)
	_check(host.bind_original_world_context(boot.world_identity),"Native binds the exact immutable initial pre-map component identity")
	var probe_site := {"clock_epoch":0,"domain":&"P","entry_id":"isolated.persistent.pre_map","entry_ordinal":1,"bootstrap":true,"observation_process_epoch":int(host.current_clock_frame().source_process_frame),"world_context":boot.world_identity,"deadline_usec":Time.get_ticks_usec()+1000000}
	_resource_ready = primitives.begin_original_phase(probe_site)
	_check(_resource_ready,"Source endpoint admits the same bounded epoch0 pre-map context as Main and Native")
	if _resource_ready:
		if boot.get("exercise_main_resource_pump") == true:
			_check(primitives.exists("res://scenes/main.tscn","PackedScene"),"actual Source cold exists returns from genuine Main executor through Native ACK and result")
			var streaming := preload("res://scripts/gameplay/enemy/enemy_owner_resource_primitives.gd").new()
			_check(streaming.configure_owner(boot.streaming_catalog,transport,_budget,_clock,Callable(_session,"fault")),"actual Source streaming endpoint shares exact original clock, prefix and budget")
			_check(streaming.begin_original_phase(probe_site),"streaming uses the same genuine original cold source call site")
			_check(streaming.load_threaded_get_status("res://assets/__v115_missing_cold_probe__.png") == 0,"actual Native invalid-resource observation follows Feature sequence one")
			_check(not primitives.exists("res://scenes/__v115_missing_cold_probe__.tscn","PackedScene"),"Feature query resumes on the global sequence after streaming")
			_check(streaming.load_threaded_get_status("res://assets/__v115_missing_cold_probe__.png") == 0,"second actual streaming operation shares global ordinal after another Feature call")
			if boot.get("exercise_main_world_pump") == true:
				var world_primitives := preload("res://scripts/gameplay/world/world_original_primitive_port.gd").new()
				_check(world_primitives.configure_owner(_session,host,_budget,_clock),"actual world port shares the same Session budget and Native sequence")
				_check(world_primitives.begin_original_phase(probe_site),"world call retains the actual epoch0 original source site")
				var draw: Dictionary = world_primitives.exchange(&"global_randi_range",[7,7])
				_check(draw.get("executed") == true and draw.get("result") == 7,"actual world Main body returns through the genuine Native claimed ticket and ACK")
				_check(world_primitives.finish_original_phase(),"world call finishes its real original external budget segment")
			_check(streaming.finish_original_phase(),"interleaved streaming phase retires its actual external segment")
		_check(primitives.finish_original_phase(),"pre-map validation probe closes without inventing resource operations")
		var bad_site: Dictionary = probe_site.duplicate(true)
		bad_site.world_context.runtime_map_id = -2
		_check(not primitives.begin_original_phase(bad_site),"other negative map identities remain rejected")
		bad_site.world_context.runtime_map_id = -1
		bad_site.world_context.world_epoch = 1
		_check(not primitives.begin_original_phase(bad_site),"pre-map identity cannot substitute for a committed later world epoch")
	if not _resource_ready: _done = true; return
	var persistence := ProfileBudget.new(_budget,_session.original_profile_process_scope())
	_profile = Profile.new()
	_profile.test_mode = true
	_check(_profile._json_persistence.configure_owner("simulation",persistence) and _profile._world_json_persistence.configure_owner("simulation",persistence),"both genuine isolated writers share that same Source budget/scope")
	_profile.temporary_item_buffs = {"isolated_process_probe":{"remaining":100.0}}
	_profile.set("_relic_proc_state",{"item_id":-1,"remaining":0.0,"cooldown":0.0})
	var runtime := Runtime.new(_session)
	runtime.service_frame.connect(_signal_observed)
	_session.set("_profile",{"success":true,"profile":_profile,"runtime":runtime})
	_scope_id = _session.call("original_profile_process_scope").get_instance_id()
	var rows: Array = _session.call("original_persistent_callback_rows",&"P")
	rows.sort_custom(_session.original_callback_before)
	_check(rows.size() == 3,"exact Profile, paused-child and adopted Feature callbacks share one global order")
	_check(rows[0].method == &"original_paused_profile_receipts","real nondefault child priority precedes its parent despite source tree depth")
	for row: Dictionary in rows:
		var order: Dictionary = _session.call("original_persistent_callback_order",row.target.get_ref().get_instance_id(),row.method)
		_check(order.get("ok") == true and order.source_path == row.source_path,"persistent callback has its actual global Main source path")
		_check(row.entry == boot.origins.profile.scope.source_entry or row.entry == boot.origins.profile_receipts.scope.source_entry or row.entry == boot.origins.feature.scope.source_entry,"callback preserves the captured original entry")
func _signal_observed() -> void: _signal_count += 1
func _valid_probe(document: Dictionary) -> bool: return document.get("contract_id") == "isolated.persistent_process.probe.v1" and document.get("value") == 115
func _validate_probe(document: Dictionary) -> Dictionary: return {"valid":_valid_probe(document),"terminal":false}
func on_inputs(_domain: String, packets: Array) -> bool:
	for packet: Dictionary in packets:
		if packet.get("kind") == "persistent_process_fixture_pause": _host.set_simulation_paused(true)
	return true
func on_phase(phase: String, frame: Dictionary) -> bool:
	frame = _host.current_clock_frame() # Same Native getter used by the real dispatcher.
	if phase == "P_GROUP" and not _done:
		var paused: bool = _host.current_host_paused()
		if paused and not _submitted:
			_submitted = true
			_writer = _profile._json_persistence.submit("user://persistent_process_probe.json",{"probe":"v115"},{"contract_id":"isolated.persistent_process.probe.v1","value":115},_validate_probe)
			_check(_writer != null,"genuine durable writer accepted inside isolated user data on paused S")
		var old_signal: int = _signal_count
		var signal_ok: bool = _session.service_original_process_frame_without_world(int(frame.source_process_frame))
		_check(signal_ok,"actual no-world Session services P signal and its genuine deferred boundary")
		if not signal_ok: _done = true; return true
		_check(_signal_count == old_signal+1,"one original signal resumes once, including pause")
		_before = float(_profile.temporary_item_buffs.isolated_process_probe.remaining)
		var callbacks_ok: bool = _session.dispatch_original_persistent_without_world(phase,frame)
		_check(callbacks_ok,"actual global callbacks execute within genuine Native resource call sites")
		if not callbacks_ok: _done = true; return true
		var calls := 0
		if _session.get("_last_profile_node_frame") == int(frame.source_process_frame): calls += 1
		if _session.get("_last_profile_receipt_frame") == int(frame.source_process_frame): calls += 1
		if not paused:
			_check(calls == 2,"original ALWAYS child still runs but unpaused child body is a no-op")
			_check(is_equal_approx(float(_profile.temporary_item_buffs.isolated_process_probe.remaining),_before-float(frame.scaled_delta)),"real Profile timer advances once by exact original P delta")
			_ordinary += 1
		else:
			_check(calls == 1,"pause excludes original pausable Profile and preserves ALWAYS receipt child")
			_check(float(_profile.temporary_item_buffs.isolated_process_probe.remaining) == _before,"pause never advances gameplay timers")
			_paused += 1
		_check(_session.call("original_profile_process_scope").get_instance_id() == _scope_id,"same persistent scope survives every real Source phase")
		_check(_budget.snapshot().get("open_scopes") == 0,"all actual persistence budget scopes close within their original callback")
		if _exercise_live: _service_actual_async_feature(frame)
		if _ordinary >= 2 and _paused >= 2 and _profile._json_persistence.completed_count == 1 and (not _exercise_live or _live_done):
			_check(_profile._json_persistence.pending_count() == 0,"paused receipt child settles the real accepted writer without a second timer")
			_check(_writer.response.get("success") == true,"actual writer receipt reports success:"+str(_writer.response))
			var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://persistent_process_probe.json")) if FileAccess.file_exists("user://persistent_process_probe.json") else null
			_check(saved is Dictionary and _valid_probe(saved),"actual isolated file contains the accepted document after durable completion")
			_check(_profile._world_json_persistence.completed_count == 0,"unrelated world writer is neither duplicated nor silently committed")
			_done = true
			if _exercise_live: print("PROFILE_SOURCE_DONE ",{"ordinary":_ordinary,"paused":_paused,"completed_writes":_profile._json_persistence.completed_count})
	if phase == "PUBLISH": return _host.publish_snapshot({"done":_done,"need_pause":_ordinary>=2,"checks":_checks},[])
	return true
func _service_actual_async_feature(frame: Dictionary) -> void:
	if _live_done: return
	if _live_request.is_empty():
		if _live_submission.is_empty():
			_live_reservation = _budget.reserve_live("isolated.async_feature.exists",0,0)
			_check(not _live_reservation.is_empty(),"same genuine Session budget reserves the async Feature request")
			if _live_reservation.is_empty(): _done = true; return
			_live_start_process = int(frame.source_process_frame)
			var site := {"clock_epoch":int(frame.epoch),"domain":&"P","entry_id":"isolated.persistent.async_feature","entry_ordinal":1,"bootstrap":false,"observation_process_epoch":int(frame.source_process_frame),"world_context":_session.get("_persistent_world_context"),"deadline_usec":Time.get_ticks_usec()+1000000}
			_live_submission = {"protocol":"hardcore.streaming.live_primitives.v1","site":site,"op":&"feature.exists","args":["res://scenes/main.tscn","PackedScene"],"reservation":_live_reservation,"main_prefix":_session.freeze_original_main_prefix(),"submitted_usec":Time.get_ticks_usec(),"deadline_usec":site.deadline_usec,"order_key":"isolated.feature.exists","dependencies":[],"priority":0,"cleanup":false}
		var admitted: Dictionary = _host.submit_live_original_resource(_live_submission)
		if admitted.get("status") in ["BUSY","BACKPRESSURE"]: return
		_check(admitted.get("status") == "PENDING" and admitted.get("request") is Dictionary,"actual Native admits async immutable request without parking Source")
		if admitted.get("status") != "PENDING": _done = true; return
		_live_request = admitted.request
		print("LIVE_FEATURE_ADMITTED ",_live_request.identity)
		return
	var polled: Dictionary = _host.poll_live_original_resource(_live_request.identity)
	if polled.get("status") == "PENDING": return
	_check(polled.get("status") == "READY","actual Main async receipt returns through Native")
	if polled.get("status") != "READY": _done = true; return
	var reply: Dictionary = polled.reply
	if _live_settlement.is_empty():
		print("LIVE_FEATURE_ACTUAL_REPLY ",{"identity":_live_request.identity,"actual_result":reply.result})
		_check(reply.result == true and reply.executed == true,"real original Main ResourceLoader.exists result returns to Source")
		_check(int(frame.source_process_frame) > _live_start_process and _ordinary >= 2,"actual Source process callbacks continue while Main withholds the optional result")
		_live_settlement = _budget.settle_live(_live_reservation,_live_request.identity,reply,int(reply.native_received_usec),int(frame.epoch))
		_check(not _live_settlement.is_empty(),"same original budget charges the actual Main interval once on receipt")
		if _live_settlement.is_empty(): _done = true; return
	var settled: Dictionary = _host.settle_live_original_resource_status(_live_settlement)
	if settled.get("status") == "PENDING": return
	_check(settled.get("status") == "SETTLED","Native accepts the same actual original ledger settlement")
	if settled.get("status") != "SETTLED": _done = true; return
	if not _live_prefix_retired:
		_check(_session.ack_original_main_prefix(reply.native_main_prefix_receipt,_live_request.main_prefix),"Source journal consumes the actual async Main prefix acknowledgement")
		_live_prefix_retired = true
	if not _host.retire_live_original_resource(_live_request.identity): return
	_check(_budget.retire_settlement(int(_live_reservation.reservation_id)) and _budget.live_obligations() == 0,"actual Native retirement releases the original budget obligation")
	_live_done = true
	print("LIVE_FEATURE_RETIRED ",_live_request.identity)
var _close_diag_recorded := false
func close_session() -> bool:
	if _exercise_live and not _close_diag_recorded:
		_close_diag_recorded = true
		print("PROFILE_SOURCE_CLOSE_ENTER ",{"live_done":_live_done,"pending_writes":_profile._json_persistence.pending_count() if _profile != null else 0})
	if _exercise_live and not _live_done: return false
	if _profile != null and _profile._json_persistence.pending_count() != 0: return false
	_profile = null
	if _exercise_live: print("PROFILE_SOURCE_CLOSE_PROFILE_RELEASED")
	_session = null
	if _exercise_live: print("PROFILE_SOURCE_CLOSE_SESSION_RELEASED")
	_writer = null
	_clock = null
	_budget = null
	_actors = null
	return true
