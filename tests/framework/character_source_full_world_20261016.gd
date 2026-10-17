extends Node
## Real button, original save transaction, Native SourceSession and full World.
## No fake World/renderer/ready/capability/terminal receipt is supplied here.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const CatalogGate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const NPCDisplay := preload("res://scripts/gameplay/world/world_npc_visual_shell.gd")
const PortalDisplay := preload("res://scripts/gameplay/world/world_portal_visual_shell.gd")
var _proof := Proof.new()
var _failed := 0
var _launcher: Control
var _facade: Node
var _resident: PackedScene
var _host: Object
var _application: RefCounted
var _clicked := false
var _deadline := 0
var _diagnostic_seconds := 30
var _closing := false
var _finishing := false
var _last_state := ""
var _assembly_verified := false
var _recorded_native_fault := false
var _recorded_launch_abort := false
var _next_progress_usec := 0
var _expected_derived_profile_view: Dictionary = {}
var _closing_transport: RefCounted
var _actual_world_root_id := 0
var _actual_launcher_id := 0
var _actual_terminal_rng_capability_verified := false
var _actual_stale_view_outbox_recorded := false
var _actual_enemy_shells: Dictionary = {}
var _actual_enemy_upgrades: Dictionary = {}
var _actual_enemy_presentations_ready := false
var _actual_interactable_before: Dictionary = {}
var _actual_interactable_arrival_checked := false
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("ACTUAL_FULL_WORLD_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS # Diagnostics and its deadline must survive a paused loading/abort.
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"real production APIs use isolated user data")
	check(CatalogGate.reader_count() == 0,"no Source catalog reader before actual launch")
	if _failed > 0: _finish(); return
	_facade = get_tree().root.get_node("PlayerState")
	_facade.test_mode = true; _facade.reset_progress(false)
	var base: String = "user://actual_full_world_%d" % Time.get_ticks_usec()
	_facade.profile_directory = base.path_join("characters")
	_facade.profile_index_path = base.path_join("profiles.json")
	_facade.shared_warehouse_path = base.path_join("warehouse.json")
	_facade.shared_warehouse_transaction_log_path = base.path_join("warehouse.transaction.json")
	_facade._shared_warehouse_initialized = false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_facade.profile_directory)) == OK,"isolated save directory")
	_facade.test_mode = false
	var error: String = _facade.create_character("World115")
	check(error.is_empty(),"original canonical character transaction: "+error)
	if not error.is_empty(): _finish(); return
	check(_facade.select_character(_facade.active_profile_id),"original persisted profile selected before Source handoff")
	var model: RefCounted = _facade.get("_model")
	_expected_derived_profile_view = {"profession_id":model.profession_id,"profession":model.profession,"learned_skills":model.learned_skills.duplicate(true)}
	_resident = load("res://scenes/main.tscn")
	_launcher = load("res://scenes/character_select.tscn").instantiate()
	_launcher.force_launch_preload_for_test = true
	# Exercise the complete real application retirement, then let this receipt
	# owner exit the test process. The original production quit remains enabled.
	_launcher.suppress_quit_for_test = true
	_actual_launcher_id = _launcher.get_instance_id()
	get_tree().root.add_child(_launcher); get_tree().current_scene = _launcher
	# User-approved external functional diagnostic only; production bootstrap
	# deadlines and all frame/performance acceptance criteria are unchanged.
	var requested_seconds: int = int(ProjectSettings.get_setting("hardcore/diagnostics/full_world_test_timeout_seconds",30))
	check(requested_seconds in [30,120,180],"exact approved diagnostic timeout")
	_diagnostic_seconds = requested_seconds if requested_seconds in [30,120,180] else 30
	_deadline = Time.get_ticks_usec()+_diagnostic_seconds*1000000
func _process(_delta: float) -> void:
	if _finishing or (not _clicked and not is_instance_valid(_launcher)): return
	if not _clicked:
		_clicked = true; _launcher.enter_button.pressed.emit()
	var producer: RefCounted = _launcher.get("_source_startup_producer") if is_instance_valid(_launcher) else null
	if producer != null:
		_host = producer.actual_host(); _application = producer.actual_application()
	if not _actual_terminal_rng_capability_verified and _host!=null and _host.status().get("main_channels_prepared")==true:
		var caps: Dictionary = _host.capabilities()
		check(caps.get("profile_terminal_global_random_return_contract_id")=="hardcore.profile.global_random.return.v1","actual prepared production Host exposes exact terminal global RNG return contract")
		var manifest_path: String = str(ProjectSettings.get_setting("hardcore/diagnostics/full_world_native_manifest_path",""))
		var manifest_sha: String = str(ProjectSettings.get_setting("hardcore/diagnostics/full_world_native_manifest_sha256",""))
		var manifest_ok: bool = manifest_path.begins_with("res://outputs/v115_multicore/") and manifest_sha.length()==64 and FileAccess.get_sha256(manifest_path)==manifest_sha
		check(manifest_ok,"actual explicit Native manifest bytes match immutable invocation SHA")
		var native_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if manifest_ok else null
		var expected_native: String = str(native_manifest.get("source_sha256","")) if native_manifest is Dictionary else ""
		var identity_ok: bool = expected_native.length()==64 and caps.get("native_source_identity_injected")==true and caps.get("native_source_sha256")==expected_native
		check(identity_ok,"actual prepared production Host reports the exact compiled Native source fingerprint")
		var identity := {"status":"PASS" if identity_ok and manifest_ok else "FAIL","native_manifest_path":manifest_path,"native_manifest_sha256":manifest_sha,"capabilities":caps,"expected_native_source_sha256":expected_native,"engine_binary_sha256":FileAccess.get_sha256(OS.get_executable_path()),"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"scope":"Actual prepared production Host identity only; full World/Android/device acceptance is separate"}
		var identity_path := "res://outputs/test_logs/framework/character_source_full_world_20261016.native_identity.json"
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(identity_path.get_base_dir()))==OK,"actual compiled Native identity evidence directory")
		var identity_file := FileAccess.open(identity_path,FileAccess.WRITE)
		check(identity_file!=null,"actual compiled Native identity evidence can be saved")
		if identity_file!=null:
			identity_file.store_string(JSON.stringify(identity,"  ")); identity_file.close()
			print("ACTUAL_FULL_WORLD_NATIVE_IDENTITY_SHA256 ",FileAccess.get_sha256(identity_path))
		_actual_terminal_rng_capability_verified=true
	if not _assembly_verified and _application != null and not _application.get("_world_assembly_result").is_empty():
		var assembly: Dictionary = _application.get("_world_assembly_result").world_boot.assembly
		check(assembly.source_fields.fields.has("background") and assembly.source_fields.fields.background == null,"actual original constructor captures the late-bound Background slot")
		check(assembly.source_domain_publication.synchronous_monster_visual_loading_for_tests == preload("res://scripts/monster_visual.gd")._synchronous_loading_for_tests,"original MonsterVisual test policy is captured from its actual owner")
		var closure: Dictionary = _application.get("_world_loading_pin_closure")
		var npc: RefCounted = _application.get("_services").caster_executor.get("_interactable")
		check(npc != null and npc.inspect_actual_original_loading_pins(closure.interactable_loading).get("success") == true,"same physical NPC textures are pinned before actual Source start")
		if npc != null:
			_actual_interactable_before = {"id":npc.get_instance_id(),"proof":npc.get("_proof").duplicate(true),"io":npc.inspect_actual_original_interactable_io()}
		check(assembly.get("owner_session_id",0) > 0 and assembly.owner_session_id == _application.get("_session_front").session_id,"actual World publication binds the one persistent Session")
		for field: String in ["profile_publication","profile_state","content_snapshot","feature_resource_boot"]:
			check(not assembly.has(field),"World does not republish Session authority: "+field)
		_assembly_verified = true
	# Inspect Main-owned values only; do not resubmit, relabel or discard input.
	if not _actual_stale_view_outbox_recorded and _application != null:
		var debug_composition: RefCounted = _application.get("_main_composition")
		var debug_views: RefCounted = debug_composition.get("_views") if debug_composition != null else null
		if debug_views != null:
			var outbox: Array = debug_views.get("_input_outbox")
			if not outbox.is_empty() and outbox.front().context.get("world_context") != debug_views.get("_world"):
				_actual_stale_view_outbox_recorded = true
				print("ACTUAL_STALE_VIEW_OUTBOX ",JSON.stringify({"Main_frame":Engine.get_process_frames(),"current_world":debug_views.get("_world"),"pending_count":outbox.size(),"first":outbox.front(),"last_arrival":debug_views.get("_last_map_arrival")}))
	var observed: Dictionary = _observed_state()
	_record_actual_loading_progress()
	if not _recorded_launch_abort and producer==null and is_instance_valid(_launcher) and _clicked and _launcher.get("_launch_in_progress")==false:
		_recorded_launch_abort=true
		check(false,"actual original CharacterSelect aborted before Source: "+JSON.stringify(_bounded_diagnostic(_launcher.get("_launch_code_result"))))
		_finishing=true
		_finish.call_deferred()
		return
	if not _recorded_native_fault and not str(observed.get("native",{}).get("fault","")).is_empty():
		_recorded_native_fault = true
		check(false,"actual Source fault: "+str(observed.native.fault))
		# Preserve this invocation's failure immediately. Keep the same real
		# cleanup running until terminal/outer deadline; never forge a join.
		_write_receipt()
	var encoded: String = JSON.stringify(observed)
	if encoded != _last_state:
		_last_state = encoded; print("ACTUAL_FULL_WORLD_STATE ",encoded)
	if not _closing and _application != null:
		_check_actual_interactable_arrival()
		_sample_actual_initial_enemy_presentations()
		var transport: RefCounted = _application.get("_transport")
		var root: Node2D = _application.get("_root_transport").retained_root()
		var world: Dictionary = transport.get("_world")
		if transport.get("_state") == "S" and world.get("runtime_map_id",-1) >= 0 and is_instance_valid(root) and get_tree().current_scene == root and (not is_instance_valid(_launcher) or not _launcher.launch_loading_overlay.visible) and _actual_enemy_presentations_ready:
			var composition: RefCounted = _application.get("_main_composition")
			var registry: RefCounted = composition.get("_registry")
			check(registry.actual_original_player_view(world) != null,"same actual Source player has a real Main renderer after first map arrival")
			check(_facade.get("_source_domain_gate").state() == "S" and int(transport.get("_model_id")) != 0,"actual Source owns the unique loaded Profile")
			check(CatalogGate.reader_count() == 1,"one persistent Source catalog reader while actual World is live")
			for field: String in _expected_derived_profile_view:
				check(_facade.get("_source_domain_gate").read_original_profile_view(field) == _expected_derived_profile_view[field],"initial Main UI preserves original Profile getter: "+field)
			check(not _actual_enemy_upgrades.is_empty(),"real initially structural Enemy shell upgrades through actual Source binding completion")
			var interactable: RefCounted = composition.get("_views").get("_caster").get("_interactable")
			var physical_npcs := 0
			var physical_portals := 0
			for actual_node: Dictionary in interactable.inspect_actual_original_interactable_io().actual_nodes:
				var display: Node = instance_from_id(int(actual_node.actual_node_id))
				if not is_instance_valid(display) or display.get_parent() != root or not display.is_inside_tree(): continue
				if display is NPCDisplay: physical_npcs += 1
				if display is PortalDisplay: physical_portals += 1
			check(_actual_interactable_arrival_checked and physical_npcs > 0 and physical_portals > 0,"real Source-created NPC and zone_portal both have actual Main children in the arrived map")
			print("ACTUAL_INTERACTABLE_NODES ",JSON.stringify({"world":world,"npc_count":physical_npcs,"portal_count":physical_portals}))
			print("ACTUAL_MAIN_ENEMY_BINDING_UPGRADES ",JSON.stringify(_actual_enemy_upgrades))
			_closing = true
			_closing_transport = transport
			_actual_world_root_id = root.get_instance_id()
			root.notification(NOTIFICATION_WM_CLOSE_REQUEST) # Real original Root notification transport.
	var application_exit: Dictionary = _application.actual_original_terminal_exit() if _application != null else {}
	if _closing and application_exit.get("success") == true:
		check(_closing_transport != null and _closing_transport.get("_state") == "CLOSED","actual full-world/Main IO terminal proof precedes Native join")
		check(_host.status().get("join_complete") == true,"actual Source join precedes completed Main retirement")
		check(_host.close_and_join(),"actual external physics lease and Source thread join")
		check(CatalogGate.reader_count() == 0,"Source catalog reader released after actual owner cleanup")
		check(_host.status().get("main_channels_unbound_after_close") == true,"actual Native retires started nine-owner bindings")
		check(_actual_world_root_id != 0 and not is_instance_id_valid(_actual_world_root_id),"actual Main game Root is physically final-freed")
		check(_actual_launcher_id != 0 and not is_instance_id_valid(_actual_launcher_id),"actual retained CharacterSelect is physically final-freed")
		check(application_exit.get("actual_startup_producer_retired",{}).get("success") == true,"actual original startup producer and catalogue owner retired")
		_finishing = true; _finish.call_deferred()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"real full-world launch/exit completes within%ds: " % _diagnostic_seconds+encoded)
		_finishing = true
		if _host != null and _host.status().get("started") == true:
			_host.request_close()
			# Never quit an engine with live Source physics or forge a terminal bit.
			# The scoped external runner preserves/kills a stuck diagnostic process.
			_write_receipt()
		else: _finish.call_deferred()
func _observed_state() -> Dictionary:
	var value: Dictionary = {"clicked":_clicked,"closing":_closing,"application":_application != null}
	value.actual_initial_enemy_presentations = {"observed_shells":_actual_enemy_shells.size(),"observed_upgrades":_actual_enemy_upgrades.size(),"ready":_actual_enemy_presentations_ready}
	if is_instance_valid(_launcher):
		value.launch_in_progress = _launcher.get("_launch_in_progress")
		value.launch_receipt = _launcher.get("_source_startup_receipt").get("error","")
		value.cover_visible = _launcher.launch_loading_overlay.visible
		if _launcher.get("_launch_in_progress")==false:
			value.actual_launch_code_failure=_bounded_diagnostic(_launcher.get("_launch_code_result"))
			value.actual_launch_message=str(_launcher.message_label.text)
	if _host != null:
		var actual: Dictionary = _host.status()
		var native: Dictionary = {}
		for field: String in ["started","running","fault","close_requested","join_complete","source_model_close_completed","map_owner_closed","accepted_live_resource_obligations","original_primitive_in_flight"]: native[field] = actual.get(field)
		value.native = native
	if _application != null:
		var transport: RefCounted = _application.get("_transport")
		var actual_composition: RefCounted = _application.get("_main_composition")
		if transport != null:
			value.world = transport.get("_world")
			value.transport = transport.get("_state")
		if actual_composition != null:
			value.composition_stage = actual_composition.get("_stage")
			value.composition_failure = actual_composition.actual_failure()
			if _host != null and _host.status().get("close_requested") == true:
				var closing: RefCounted = actual_composition.get("_closing_frames")
				if closing != null:
					var obligations: Dictionary = closing.capture_actual_closing_process_obligations()
					var accepted: Array = obligations.get("accepted",[])
					value.actual_closing_process = {"accepted_count":accepted.size(),"first_sequence":accepted.front().get("publication",{}).get("sequence") if not accepted.is_empty() else null,"last_sequence":accepted.back().get("publication",{}).get("sequence") if not accepted.is_empty() else null,"capture_stopped":obligations.get("capture_stopped"),"pending_service":_bounded_diagnostic(obligations.get("pending_service",{})),"stop_receipt":_bounded_diagnostic(obligations.get("stop_receipt",{})),"fault":_bounded_diagnostic(obligations.get("fault",{}))}
					value.actual_closing_process.armed = closing.get("_armed")
					value.actual_closing_process.finished = closing.get("_finished")
					value.actual_closing_process.last_main_signal = closing.get("_last_main_signal")
					value.actual_closing_process.last_published_sequence = closing.get("_last_published_sequence")
					value.actual_closing_process.actual_signal_connected = get_tree().process_frame.is_connected(closing._on_actual_process_frame_signal)
				value.actual_closing_signal_highwater = _host.original_close_process_signal_highwater()
				value.actual_next_published_prefix = _host.inspect_next_original_published_prefix()
				var failure: RefCounted = _application.get("_main_failure")
				if failure != null: value.actual_Main_faults = _bounded_diagnostic(failure.actual_original_main_source_faults())
		value.actual_application_exit = _bounded_diagnostic(_application.actual_original_terminal_exit())
		value.last_launch_receipt = _bounded_diagnostic(_application.last_launch_receipt())
		if _host != null and not str(_host.status().get("fault","")).is_empty():
			var actual_pump: RefCounted = _application.get("_main_composition").get("_pump")
			if actual_pump!=null: value.actual_Main_pump = actual_pump.inspect_actual_original_pending_resources()
			var main_failure: RefCounted = _application.get("_main_failure")
			if main_failure != null: value.actual_Main_faults = _bounded_diagnostic(main_failure.actual_original_main_source_faults().slice(0,4))
			var composition: RefCounted = _application.get("_main_composition")
			var prefix: RefCounted = composition.get("_prefix")
			var registry: RefCounted = composition.get("_registry")
			if registry != null: value.actual_renderer_failure = registry.failure()
			if prefix != null:
				value.actual_prefix_failure = prefix.failure()
				var event: Dictionary = prefix.actual_current_original_event()
				value.actual_failed_event = {"kind":event.get("kind"),"operation":event.get("operation"),"event":event.get("event"),"ordinal":event.get("ordinal")}
				if event.get("operation") == &"caster_presentation" and event.get("arguments") is Array and event.arguments.size() == 1:
					value.actual_failed_caster_command = _bounded_diagnostic(event.arguments[0])
					var caster_views: RefCounted = composition.get("_views")
					var caster: RefCounted = caster_views.get("_caster") if caster_views != null else null
					if caster != null:
						value.actual_failed_caster = {"execution_failure":caster.get("_execution_failure"),"last_command":_bounded_diagnostic(caster.get("_last_command")),"claimed_ticket":caster.get("_claimed_ticket"),"awaiting_reply":caster.get("_awaiting_reply"),"closed":caster.get("_closed")}
				if event.get("operation") == &"map_loading" and event.get("arguments") is Array and event.arguments.size() == 1:
					var request: Dictionary = event.arguments[0]
					value.actual_failed_map_request = {"operation":request.get("operation"),"request_sequence":request.get("request_sequence"),"owner_descriptor":request.get("owner_descriptor"),"scope":_bounded_diagnostic(request.get("scope")),"identity":event.get("reply_identity")}
					var views: RefCounted = composition.get("_views")
					if views != null:
						var executor: RefCounted = views.get("_map_executor")
						if executor != null: value.actual_failed_map_executor = {"fault":executor.get("_fault"),"descriptor":executor.actual_owner_descriptor(),"pending":executor.has_pending_original_map_reply()}
						var producer: RefCounted = views.get("_map_producer")
						if producer != null: value.actual_failed_map_owner = {"descriptor":producer.get("_descriptor"),"scope":_bounded_diagnostic(producer.get("_scope")),"arrival":_bounded_diagnostic(producer.get("_arrival_transaction")),"closing":producer.get("_closing"),"release_stage":_bounded_diagnostic(producer.get("_release_stage"))}
			var primitive: RefCounted = _application.get("_services").get("feature_main")
			if primitive != null:
				value.last_actual_Main_operation = primitive.get("_last_request").get("operation")
				value.last_actual_Main_reply = _bounded_diagnostic(primitive.get("_last_reply").get("result"))
	return value
func _record_actual_loading_progress() -> void:
	# Bounded diagnostic sampling on Main only; no Source object read, added
	# gameplay timer, resource poll, clock advancement or readiness substitute.
	if _host==null or _application==null or _host.status().get("started")!=true or Time.get_ticks_usec()<_next_progress_usec: return
	_next_progress_usec=Time.get_ticks_usec()+5000000
	var value := {"wall_usec":Time.get_ticks_usec(),"actual_Main_frame":Engine.get_process_frames(),"native":_host.status()}
	var composition: RefCounted = _application.get("_main_composition")
	if composition!=null:
		var pump: RefCounted = composition.get("_pump")
		if pump!=null: value.actual_Main_pump=pump.inspect_actual_original_pending_resources()
		var streaming: RefCounted = composition.get("_streaming")
		if streaming!=null:
			var request: Dictionary = streaming.get("_last_request")
			value.last_actual_streaming_request={"op":request.get("op"),"args":_bounded_diagnostic(request.get("args")),"identity":_bounded_diagnostic(request.get("identity"))}
		var views: RefCounted = composition.get("_views")
		if views!=null:
			var leaf: RefCounted = views.get("_map_leaf")
			var executor: RefCounted = views.get("_map_executor")
			if leaf!=null:
				var requested: Dictionary = leaf.get("_last_request")
				var result: Dictionary = leaf.get("_last_result")
				var descriptors: Array = leaf.get("_descriptors")
				value.actual_Main_map={"operation":requested.get("operation"),"request_sequence":requested.get("request_sequence"),"next_sequence":leaf.get("_next_sequence"),"result_ok":result.get("ok"),"result_error":result.get("error"),"result_complete":result.get("complete"),"result_requested":result.get("requested"),"descriptors_remaining":descriptors.size(),"loading_receipt_status":leaf.get("_loading_receipt").get("status")}
				var coordinator: RefCounted = leaf.get("_coordinator")
				if coordinator!=null:
					value.actual_Main_map.coordinator_stage=coordinator.get("stage")
					value.actual_Main_map.coordinator_generation=coordinator.get("generation")
			if executor!=null:
				var effect: Dictionary = executor.get("_effect")
				var reply: Dictionary = executor.get("_reply")
				var last_reply: Dictionary = executor.get("_last_reply")
				value.actual_Main_map_reply={"effect_held":not effect.is_empty(),"reply_held":not reply.is_empty(),"fault":executor.get("_fault"),"last_operation":last_reply.get("source_request",{}).get("operation"),"last_identity":last_reply.get("identity"),"last_result":_bounded_diagnostic(last_reply.get("result"))}
				value.actual_Main_map_reply.source_request_epoch=last_reply.get("source_request",{}).get("source_clock",{}).get("epoch")
				value.actual_Main_map_reply.started_usec=last_reply.get("started_usec")
				value.actual_Main_map_reply.finished_usec=last_reply.get("finished_usec")
				value.actual_Main_map_reply.actual_Main_CPU_usec=last_reply.get("actual_Main_CPU_usec")
	print("ACTUAL_FULL_WORLD_PROGRESS ",JSON.stringify(value))
func _bounded_diagnostic(value: Variant,depth: int = 0) -> Variant:
	# Failure diagnostics must not serialize a successful full database graph
	# nested inside an error. Assertions still inspect the complete live objects.
	if value is Dictionary:
		if depth >= 4: return {"type":"Dictionary","fields":value.size()}
		var out: Dictionary = {}
		var count := 0
		for key: Variant in value:
			if count >= 20: out["additional_fields"] = value.size()-count; break
			out[str(key)] = _bounded_diagnostic(value[key],depth+1); count += 1
		return out
	if value is Array:
		if depth >= 4 or value.size() > 32: return {"type":"Array","entries":value.size()}
		var out: Array = []
		for child: Variant in value: out.append(_bounded_diagnostic(child,depth+1))
		return out
	if value is String: return value if value.length() <= 512 else value.substr(0,512)+"..."
	if value is Object: return {"type":value.get_class()} if is_instance_valid(value) else null
	if value is PackedByteArray: return {"type":"PackedByteArray","bytes":value.size()}
	return value
func _write_receipt() -> bool:
	return _proof.write_receipt("character_source_full_world_20261016",_proof.records.size(),_failed)
func _finish() -> void:
	set_process(false)
	var written: bool = _write_receipt()
	print("CHARACTER_SOURCE_FULL_WORLD_20261016_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)

func _sample_actual_initial_enemy_presentations() -> void:
	var composition: RefCounted = _application.get("_main_composition")
	if composition == null: return
	var registry: RefCounted = composition.get("_registry")
	if registry == null: return
	var pending := 0
	var complete := 0
	for id: int in registry.get("_actors"):
		var row: Dictionary = registry.get("_actors")[id]
		if row.get("kind",row.get("last",{}).get("kind","")) != "enemy": continue
		if row.get("structural_only") == true: pending += 1
		else: complete += 1
		var view: Node2D = row.view
		if not is_instance_valid(view) or view.visual == null or view.visual.sprite == null or view.overhead == null or row.assets == null: continue
		var marker: Sprite2D = view.overhead.rank_marker
		var label: Label = view.overhead.name_label
		var font: Font = label.get_theme_font("font") if label != null else null
		var physical := {"view":view.get_instance_id(),"visual":view.visual.get_instance_id(),"sprite":view.visual.sprite.get_instance_id(),"overhead":view.overhead.get_instance_id(),"assets":row.assets.get_instance_id(),"marker":marker.get_instance_id() if marker != null else 0,"marker_texture":marker.texture.get_instance_id() if marker != null and marker.texture != null else 0,"font":font.get_instance_id() if font != null else 0}
		if row.get("structural_only") == true:
			if not _actual_enemy_shells.has(id): _actual_enemy_shells[id] = {"physical":physical,"identity":row.identity.duplicate(true),"service_id":view.visual.canonical_service_id,"main_frame":Engine.get_process_frames()}
		elif _actual_enemy_shells.has(id) and not _actual_enemy_upgrades.has(id):
			var earlier: Dictionary = _actual_enemy_shells[id]
			check(earlier.physical == physical,"same actual Enemy shell/Sprite/overhead/marker/font/asset owners survive first complete projection")
			check(earlier.identity == row.identity and earlier.service_id == view.visual.canonical_service_id,"actual Enemy shell upgrade preserves exact actor/service identity")
			check(row.last.publication_sequence >= 1,"actual complete Source projection owns the physical upgrade")
			_actual_enemy_upgrades[id] = {"actor_identity":row.identity.duplicate(true),"service_id":view.visual.canonical_service_id,"physical":physical,"source_sequence":row.last.publication_sequence,"main_frame":Engine.get_process_frames()}
	_actual_enemy_presentations_ready = complete > 0 and pending == 0 and not _actual_enemy_upgrades.is_empty()

func _check_actual_interactable_arrival() -> void:
	if _actual_interactable_arrival_checked or _actual_interactable_before.is_empty(): return
	var composition: RefCounted = _application.get("_main_composition")
	var views: RefCounted = composition.get("_views") if composition != null else null
	if views == null or views.get("_last_map_arrival").is_empty(): return
	var transaction: Dictionary = views.get("_last_map_arrival")
	var npc: RefCounted = views.get("_caster").get("_interactable")
	var io: Dictionary = npc.inspect_actual_original_interactable_io()
	check(npc.get_instance_id() == _actual_interactable_before.id and io.world_context == transaction.after_world,"same actual NPC owner follows the verified Native map arrival before new-map commands")
	check(npc.get("_proof") == _actual_interactable_before.proof and io.actual_texture_pins == _actual_interactable_before.io.actual_texture_pins,"map arrival retains exact original NPC Loading proof and physical texture pins")
	check(not npc.can_commit_actual_original_map_arrival(transaction),"already consumed before-world cannot replay NPC routing mutation")
	var forged: Dictionary = transaction.duplicate(true)
	forged.before_world = transaction.after_world.duplicate(true)
	forged.after_world.world_epoch += 1
	check(not npc.commit_actual_original_map_arrival(forged) and npc.get("_world") == transaction.after_world,"uncommitted next-map values cannot mutate the real NPC owner")
	_actual_interactable_arrival_checked = true
	print("ACTUAL_INTERACTABLE_MAP_ARRIVAL ",JSON.stringify({"producer_runtime_id":npc.get_instance_id(),"world":io.world_context,"actual_texture_pins":io.actual_texture_pins,"original_proof_world":npc.get("_proof").world_context}))
