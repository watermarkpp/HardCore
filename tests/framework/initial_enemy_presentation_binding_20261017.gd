extends "res://tests/framework/live_sprite_birth_order_20261017.gd"
## Smaller genuine protocol regression. Inherited Host/Session/Main execution
## is real; inherited Registry/Handle/VisualModel are controlled component
## owners. This does NOT prove World/Enemy wake, birth or shell upgrade.
@export_enum("ordinary", "controlled_late") var binding_test_mode := "ordinary"
var _withhold_identity: Dictionary = {}
var _withhold_start_poll := -1
var _withhold_start_h := -1
var _withhold_released := false
const InitialCore := preload("res://tests/framework/helpers/initial_enemy_presentation_binding_source_20261017.gd")

func start() -> void:
	host = ClassDB.instantiate("HardCoreSimulationHost")
	observer = ClassDB.instantiate("HardCoreResourceObservation")
	main = MainPrimitives.new()
	check(main.configure_main(Callable(host,"validate_original_primitive_ticket") if use_shared_main_pump else validate_ticket, observer, generation), "actual Main primitive owner configured")
	prefix = PrefixConsumer.new(host, self)
	if use_shared_main_pump:
		feature_main = preload("res://scripts/features/runtime/feature_resource_main_primitives.gd").new()
		check(feature_main.configure_main(ContentLayers._feature_resources(),observer,Callable(host,"validate_original_primitive_ticket"),_unexpected_feature_call,_unexpected_feature_call,generation),"same actual Main Feature vault configures the shared production pump")
		shared_pump = preload("res://scripts/gameplay/source/main_original_resource_pump.gd").new()
		check(shared_pump.configure_main(host,prefix,feature_main,generation),"production resource pump retains this exact Native Host and prefix consumer")
	var texture := GradientTexture2D.new()
	texture.width = 4
	texture.height = 4
	texture.gradient = Gradient.new()
	var path := "user://initial_enemy_presentation_binding_20261017.tres"
	check(ResourceSaver.save(texture, path) == OK, "actual Texture2D fixture saved only in isolated test userdata")
	texture = null
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),
		"world_epoch":1,"runtime_map_id":913203,"profile_id":"binding_fifo_protocol_component"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,
		"bridge_generation":generation,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),
		"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb")) * 256,
		"primitive_request_capacity":65536,"primitive_result_capacity":65536,"live_primitive_capacity":2}
	var boot := {"binding_test_mode":binding_test_mode,"world_identity":world,"gameplay_random_handoff":host.capture_main_gameplay_random(),
		"catalog":main.capture_catalog(PackedInt32Array()),"texture_path":path,"settings":{
		"hardcore/performance/frame_optional_budget_usec":ProjectSettings.get_setting("hardcore/performance/frame_optional_budget_usec",1200),
		"hardcore/performance/frame_progress_budget_usec":ProjectSettings.get_setting("hardcore/performance/frame_progress_budget_usec",6000)}}
	if use_prepared_channels:
		check(host.prepare_original_main_channels(config).get("status") == "PREPARED", "real Native channels prepare without starting Source")
		check(host.status().get("started") == false and host.status().get("owner_thread") == 0 and host.capabilities().get("bridge_generation") == generation, "preparation creates no Source owner and Main reads actual capabilities")
		check(shared_pump.bind_actual_original_live_streaming(main), "the actual streaming owner binds BEFORE Source starts")
	check(host.start_clock_fixture(InitialCore, boot, config), "actual Host-created S protocol fixture started")
	var script_sha: String = FileAccess.get_sha256("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd")
	if not use_prepared_channels:
		check(shared_pump.bind_actual_original_live_streaming(main) if use_shared_main_pump else main.configure_live_main(host, script_sha), "actual fixed Main resource vault bound by native provenance")
	if use_shared_main_pump:
		check(host.finalize_original_main_resource_vault().get("status") == "PENDING" and main.get("_generation_closed") == false,"the real finalizer cannot close a bound physical vault before Source has actually closed")
	deadline = Time.get_ticks_usec() + 8000000


func _process(_delta: float) -> void:
	if host == null or deadline == 0: return
	var publication: Dictionary = host.acquire_presentation(tick + 1, 16)
	if not publication.is_empty():
		tick = int(publication.tick)
		var frame: Dictionary = publication.frame
		_last_control_frame = frame
		last_source_stage = str(frame.stage)
		check(frame.valid == true, "Source protocol remains valid while Main result delivery is asynchronous")
		host.ack_events(int(publication.through_ordinal))
		if frame.done and not source_done:
			source_done = true
			source_rows = frame.rows
			source_trace = frame.trace
	# The negative scene withholds the whole production service before it
	# acquires anything; accepted packets remain owned by the actual mailbox.
	if use_shared_main_pump and not source_done and not _withhold_actual_main_service():
		var served: Dictionary = shared_pump.service_original_main_resources()
		check(served.get("status") in ["PENDING","SERVICED"],"shared production pump preserves the actual streaming execution and physical transfer")
		executions = int(shared_pump.inspect_actual_original_pending_resources().live_completed)
	if not use_shared_main_pump and held.is_empty() and not source_done:
		held = host.acquire_pending_live_original_resource()
		if not held.is_empty(): release_tick = tick + (2 if held.request.op == &"bind_or_clear" else 0)
	if not use_shared_main_pump and not held.is_empty() and tick >= release_tick:
		var request: Dictionary = held.request
		if reply.is_empty():
			var applied: Dictionary = prefix.apply_prefix(request.main_prefix)
			if applied.get("status") == "BUSY": return
			check(applied.get("status") == "APPLIED", "real Main prefix precedes actual binding primitive")
			if applied.get("status") != "APPLIED": return
			if not host.ack_live_original_main_prefix(request.identity, request.main_prefix): return
			if not prefix.confirm_prefix_acknowledged(request.main_prefix): return
			reply = main.execute_live_original_primitive(request)
			if reply.is_empty(): return
			executions += 1
			check(reply.get("executed") == true, "actual Main operation generated its real result")
			if not host.submit_live_original_resource_result(request.identity, reply): return
		var transfer: Dictionary = main.transfer_current_live_obligations()
		if transfer.get("status") == "PENDING": return
		check(transfer.get("status") == "TRANSFERRED", "actual resource responsibility transferred or retired, not guessed empty")
		if transfer.get("status") != "TRANSFERRED": return
		held = {}
		reply = {}
	if source_done and not close_requested:
		if use_shared_main_pump and not host_close_started:
			host_close_started = true
			host.request_close()
		var closed: Dictionary = {}
		if use_shared_main_pump:
			var source_was_closed: bool = host.status().get("source_model_close_completed") == true
			var final_service: Dictionary = shared_pump.service_original_main_resources()
			check(final_service.get("status") in ["PENDING","SERVICED"], "same production Main service continues through the actual Source close boundary")
			if source_was_closed:
				check(host.status().get("live_resource_vault_closed") == true, "the production service invokes the real vault finalizer before Native join")
				closed = host.finalize_original_main_resource_vault() # Actual idempotence query only after the production service.
		else:
			closed = main.certify_actual_live_vault_closed({"fixture_done":true})
		var actual_closed: bool = closed.get("status") == "READY" if use_shared_main_pump else closed.get("ok") == true
		if actual_closed:
			close_requested = true
			check(true, "actual native vault close certificate after real renderer, escrow and texture release")
			if use_shared_main_pump:
				check(host.status().get("source_model_close_completed") == true and host.status().get("live_resource_vault_closed") == true,"Native finalizer observes actual Source close and independently certifies its original physical vault")
			host.request_close()
	if not timeout_reported and Time.get_ticks_usec() > deadline:
		timeout_reported = true
		check(false, "protocol component timeout, accepted responsibilities retained")
		print("BINDING_FIFO_TIMEOUT ", {"host":host.status(),"stage":last_source_stage,"tick":tick,"held":held,"reply":reply})
		host.request_close()
	if close_requested and host.status().join_complete:
		check(host.close_and_join(), "S closed and Main joined only after all actual obligations")
		if binding_test_mode == "controlled_late":
			check(_withhold_released and not _withhold_identity.is_empty(), "controlled-late scene actually held one accepted Native binding then released the same production pump")
		for row: Dictionary in source_rows: check(row.passed, row.label)
		check(executions > 15 and source_trace.size() > 0, "multiple real loading/binding/cleanup operations exercised")
		print("BINDING_FIFO_TRACE ", JSON.stringify(source_trace))
		host = null
		main = null
		prefix = null
		observer = null
		shared_pump = null; feature_main = null
		var scene_id := scene_file_path.get_file().get_basename()
		var written: bool = proof.write_receipt(scene_id, proof.records.size(), failures)
		print(scene_id.to_upper()+"_", "PASS" if written and failures == 0 else "FAIL")
		get_tree().quit(0 if written and failures == 0 else 1)

var _last_control_frame: Dictionary = {}

func _withhold_actual_main_service() -> bool:
	if binding_test_mode != "controlled_late" or _withhold_released: return false
	if _last_control_frame.get("stage") != "binding" or int(_last_control_frame.get("case_index",-1)) != 0: return false
	# Preparation has completed. Fence the first visibility binding, before
	# pressure operations could otherwise occupy the two-slot Native queue.
	var control: Dictionary = _last_control_frame.get("initial_binding_control", {})
	var actual: Dictionary = control.get("identity", {})
	if _withhold_identity.is_empty():
		if actual.is_empty(): return true
		_withhold_identity = actual.duplicate(true)
		_withhold_start_poll = int(_last_control_frame.polls)
		_withhold_start_h = int(_last_control_frame.ticks)
		check(control.get("pending_operation") == "bind_or_clear", "controlled delay fences an actually accepted first visibility binding")
		return true
	check(actual == _withhold_identity, "accepted Native binding identity remains unchanged while Main service is withheld")
	if int(_last_control_frame.polls) - _withhold_start_poll < 2: return true
	check(int(_last_control_frame.ticks) > _withhold_start_h, "Source H advances while actual Native binding remains pending across two Source P polls")
	_withhold_released = true
	print("INITIAL_BINDING_CONTROLLED_DELAY ", JSON.stringify({"identity":_withhold_identity,
		"start_poll":_withhold_start_poll,"release_poll":_last_control_frame.polls,
		"start_h":_withhold_start_h,"release_h":_last_control_frame.ticks}))
	return false
