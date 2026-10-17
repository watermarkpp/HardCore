extends Node
## Real character launch/code lease/opaque cover and checkpoint. This fixture
## creates only isolated documents and never starts S or legacy gameplay.
const Character := preload("res://scripts/character_select.gd")
const Loading := preload("res://scripts/gameplay/source/main_boot_launch_loading.gd")
const Router := preload("res://scripts/gameplay/source/main_root_checkpoint_router.gd")
const Transport := preload("res://scripts/gameplay/source/main_session_transport.gd")
const Failure := preload("res://scripts/gameplay/source/main_source_failure.gd")
const Identity := preload("res://scripts/gameplay/source/main_boot_application.gd")
const Admission := preload("res://scripts/gameplay/source/main_source_admission.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
class BeforeSourceFallback extends RefCounted:
	var receiver: WeakRef
	func _init(actual: Node) -> void: receiver = weakref(actual)
	func apply_original_main_journal_event(event: Dictionary) -> bool:
		# Deliberately fail any unexpected Source execution in this Main-only
		# constructor fixture. This is not an application/world dispatcher.
		return receiver.get_ref().apply_original_main_journal_event(event)
var _proof := Proof.new()
var _failed := 0
var _facade: Node
var _content: Node
var _launcher: Control
var _resident_scene: PackedScene
var _root: Node2D
var _root_transport: RefCounted
var _host: Object
var _loading: RefCounted
var _router: RefCounted
var _fatal: RefCounted
var _clicked := false
var _observed := false
var _finishing := false
var _deadline := 0
var _last_diagnostic := ""
@export var exercise_actual_main_views := false
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void:
	print("LAUNCH_SCOPE_STAGE ready ",Time.get_ticks_msec())
	_run.call_deferred()
func _run() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"all actual profile/code preparation work uses official isolated user data")
	if _failed > 0: _finish(); return
	_facade = get_tree().root.get_node("PlayerState")
	_content = get_tree().root.get_node("ContentLayers")
	print("LAUNCH_SCOPE_STAGE isolated_profile_begin ",Time.get_ticks_msec())
	_facade.test_mode = true
	_facade.reset_progress(false)
	var base: String = "user://actual_launch_scope_%d" % Time.get_ticks_usec()
	_facade.profile_directory = base.path_join("characters")
	_facade.profile_index_path = base.path_join("profiles.json")
	_facade.shared_warehouse_path = base.path_join("warehouse.json")
	_facade.shared_warehouse_transaction_log_path = base.path_join("warehouse.transaction.json")
	_facade._shared_warehouse_initialized = false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_facade.profile_directory)) == OK,"actual isolated character directory created")
	_facade.test_mode = false
	var error: String = _facade.create_character("Scope115")
	check(error.is_empty(),"original production transaction creates its own canonical selected character: "+error)
	if not error.is_empty(): _finish(); return
	if exercise_actual_main_views:
		check(_facade.select_character(_facade.active_profile_id),"original selection loads the isolated saved character once before Main loaded handoff")
	print("LAUNCH_SCOPE_STAGE selected_profile_created ",Time.get_ticks_msec())
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_fatal = Failure.new()
	check(_fatal.configure_main(_host),"actual failure owner binds without creating Source or a fake fault sink")
	_loading = Loading.new()
	check(_loading.configure_main(get_tree(),_facade,_content),"actual Loading observer uses the real autoloads")
	_router = Router.new()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/gameplay/source/main_original_receiver_manifest.json"))
	var configured: Dictionary = _router.configure_main(get_tree(),_facade,Transport.new(),_fatal,manifest)
	check(configured.get("success") == true,"actual checkpoint validates all fixed receiver Script bytes")
	if configured.get("success") != true: _finish(); return
	_resident_scene = load("res://scenes/main.tscn") # Real cached scene for this narrow Main permission component, not a fake entitlement.
	print("LAUNCH_SCOPE_STAGE receiver_create ",Time.get_ticks_msec())
	_launcher = load("res://scenes/character_select.tscn").instantiate()
	_launcher.suppress_scene_change_for_test = true # Original prepared lease is still acquired; no fake ready.
	_launcher.force_launch_preload_for_test = true
	_launcher.character_launch_requested.connect(_inspect_actual_launch)
	print("LAUNCH_SCOPE_STAGE receiver_enter_begin ",Time.get_ticks_msec())
	get_tree().root.add_child(_launcher)
	print("LAUNCH_SCOPE_STAGE receiver_enter_end ",Time.get_ticks_msec())
	get_tree().current_scene = _launcher
	_deadline = Time.get_ticks_usec()+26000000 # Fits the unchanged 60s outer bound after actual Script/asset loading.
func _process(_delta: float) -> void:
	if _launcher == null or _finishing: return
	if not _clicked:
		print("LAUNCH_SCOPE_STAGE original_button_press ",Time.get_ticks_msec())
		_clicked = true
		_launcher.enter_button.pressed.emit() # The unchanged original input/await chain owns its real ledger.
	if _clicked and not _observed:
		var actual_state: String = JSON.stringify({"launch":_launcher.get("_launch_in_progress"),"code":_launcher.launch_code_preparation_diagnostic(),"preload":str(_launcher.get("_launch_scene_preload_state")),"cover_visible":_launcher.launch_loading_overlay.visible,"message":_launcher.message_label.text})
		if actual_state != _last_diagnostic:
			_last_diagnostic = actual_state
			print("LAUNCH_SCOPE_STATE ",actual_state)
		if not _launcher.get("_launch_in_progress") and _launcher.get("_original_main_callback_ledger").get("_enter_selected_character",0) == 0:
			check(false,"original launch rejected before checkpoint: "+actual_state)
			_finishing = true
			_finish.call_deferred()
			return
	if _observed and _launcher.get("_original_main_callback_ledger").get("_enter_selected_character",0) == 0:
		_finishing = true
		_finish.call_deferred()
	elif Time.get_ticks_usec() > _deadline:
		check(false,"actual original launch reaches its checkpoint within explicit heavy-fixture deadline: "+JSON.stringify(_launcher.launch_code_preparation_diagnostic()))
		_finishing = true
		_finish.call_deferred()
func _inspect_actual_launch(_request: Dictionary) -> void:
	print("LAUNCH_SCOPE_STAGE original_launch_signal ",Time.get_ticks_msec())
	_observed = true
	check(_launcher.get("_original_main_callback_ledger").get("_enter_selected_character") == 1,"checkpoint runs inside the genuine suspended original launch stack")
	var prepared: Dictionary = _launcher.get("_launch_code_result")
	check(prepared.get("success") == true and prepared.get("lease") is RefCounted,"original code verifier acquired a real physical code lease")
	var captured: Dictionary = _loading.capture_actual_original_launch_loading_scope(_launcher,prepared)
	check(captured.get("success") == true,"actual covered original launch and current code retention produce the Loading scope: "+JSON.stringify(captured))
	if captured.get("success") != true: return
	_root_transport = preload("res://scripts/gameplay/source/main_boot_root_transport.gd").new()
	check(_root_transport.configure_main(_host,_loading,Transport.new()),"real Main Root transport binds the same original launch Loading owner")
	var born: Dictionary = preload("res://scripts/gameplay/world/world_main_root_attachment.gd").instantiate_original_source_root(_resident_scene,load("res://scripts/game_root.gd"),_root_transport,captured.scope)
	check(born.get("success") == true,"genuine source Root attachment captures the constructor before removing the original plain combat child")
	if born.get("success") != true: return
	_root = born.root
	var observed: Dictionary = Identity.inspect_original_root_identity(_root,_facade)
	check(observed.get("success") == true,"same actually selected character produces the genuine original pre-map Root identity")
	if observed.get("success") != true: return
	get_tree().root.add_child(_root)
	var birth_inputs: Dictionary = Identity.capture_actual_original_world_birth_inputs(_root,observed.world)
	check(birth_inputs.get("success") == true,"real covered guarded Root produces actual original Root scope and service constructor inputs")
	if birth_inputs.get("success") == true:
		var expected_kinds: Array = ["loot_runtime_manager","m30_summon_queue","monster_visual","node_timer","player_visual","polygon_pursuit_driver"]
		var actual_kinds: Array = birth_inputs.publication.service_birth_scopes.keys()
		actual_kinds.sort()
		check(birth_inputs.publication.original_root_scope.node_id == _root.get_instance_id() and actual_kinds == expected_kinds,"one actual Root identity supplies its structural scope and exact six original service kinds including Native Timer")
		var timer: Dictionary = birth_inputs.publication.original_service_constructor_witnesses.get("node_timer",{})
		check(timer.get("original_class") == "Timer" and timer.get("actual_original_child_count") == 0 and timer.get("timer_constructor",{}).get("time_left") == 0.0,"original Timer constructor is captured without starting or attaching it")
		check(_root.get_child_count(true) == 0 and _root.current_map_id == -1 and _root._zone_generation == 0,"birth publication does not execute player/combat/READY/map activation")
	var foreign_birth_world: Dictionary = observed.world.duplicate(true)
	foreign_birth_world.profile_id += ".foreign"
	check(Identity.capture_actual_original_world_birth_inputs(_root,foreign_birth_world).get("success") != true,"another profile cannot borrow this actual original Root birth checkpoint")
	var physical_vault := preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd").new()
	check(physical_vault.configure_main(Callable(_host,"validate_original_primitive_ticket"),ClassDB.instantiate("HardCoreResourceObservation"),115164),"actual Main constructor vault is configured before Source ownership")
	var prefix := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd").new(_host,self)
	var phase_bridge := preload("res://scripts/gameplay/presentation/main_original_visual_phase_bridge.gd").new()
	check(phase_bridge.configure_main(_root,observed.world,_host,prefix,physical_vault,115164),"actual pre-map renderer receiver uses the same real Root and prefix")
	var visual_registry := preload("res://scripts/gameplay/presentation/main_actor_visual_registry.gd").new()
	var structural_ok: bool = visual_registry.configure_original_structural_main(_root,observed.world,phase_bridge)
	check(structural_ok,"exact genuine -1/map-generation0 Root can prepare a pure player shell before first ActorRef binding")
	if structural_ok:
		var shell: Dictionary = visual_registry.prepare_original_player_shell()
		check(shell.get("success") == true and shell.view is Node2D and not shell.view is CollisionObject2D,"actual structural player shell has no physics actor or gameplay writer")
		check(visual_registry.actual_original_prepared_player_shell(observed.world) == shell.view and visual_registry.get("_player_id") == 0 and visual_registry.get("_actors").is_empty() and _root.get("player") == null,"preparation creates no accepted ActorRef, source player identity or second model")
		if exercise_actual_main_views:
			_facade.get("_model")._before_state_transaction(true)
			var handoff: Dictionary = preload("res://scripts/gameplay/profile/profile_state_handoff.gd").capture_main(_facade.get("_model"),_facade)
			check(handoff.get("ok") == true,"actual loaded selected Profile supplies its original document handoff: "+str(handoff.get("errors",handoff.get("error",handoff.get("reason",{})))))
			if handoff.get("ok") == true:
				var view := preload("res://scripts/gameplay/world/world_profile_ui_view.gd").new()
				var snapshot: Dictionary = view.capture_original_main_loaded(_facade.get("_model"),handoff.publication,115164,observed.world)
				check(not snapshot.is_empty() and view.accept_original_journal_snapshot(snapshot),"actual Main loaded readonly Profile view feeds the original HUD")
				var feature := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd").new()
				check(feature.configure_main(_content._feature_resources(),ClassDB.instantiate("HardCoreResourceObservation"),Callable(_host,"validate_original_primitive_ticket"),_unexpected_resource_call,_unexpected_resource_call,115164),"actual same Host configures the Main Feature reference vault")
				check(physical_vault.configure_original_actor_asset_inputs(_loading,prefix),"actual streaming vault retains its original texture authority and binds the actor asset sub-ledger")
				var inputs: Dictionary = physical_vault.prepare_original_player_renderer_inputs(view,observed.world,captured.scope)
				check(inputs.get("success") == true and inputs.get("phase") == "INPUTS_PINNED" and inputs.get("fact_count",0)>0,"actual original Player appearance/alias/shader input closure is prepared under its genuine cover: "+str(inputs))
				if inputs.get("success") == true:
					check(physical_vault.prepare_original_player_renderer_inputs(view,observed.world,captured.scope) == inputs,"same physical input template is reused without a second load or future actor identity")
				var views := preload("res://scripts/gameplay/world/world_main_views.gd").new()
				var built: Dictionary = views.create_original_main_views(_root,observed.world,shell.view,view,Transport.new(),physical_vault,feature,visual_registry,_loading,BeforeSourceFallback.new(self))
				check(built.get("success") == true,"actual original world HUD/background/camera/menu/effects are constructed under the genuine launch cover: "+str(built))
				if built.get("success") == true:
					var map_cursor: RefCounted = views.actual_original_map_executor()
					check(map_cursor != null and map_cursor.get_script() == preload("res://scripts/gameplay/world/world_map_event_main.gd") and map_cursor.actual_owner_descriptor().is_empty(),"one actual Map reply cursor exists before a Source owner descriptor is born")
					check(views.flush_original_main_replies().get("status") == "READY" and not views.has_pending_original_main_replies(),"original empty-effect reply body permits the first cold prefix without inventing a Map owner or result")
					check(is_instance_valid(_root.hud) and _root.background.get_script() == preload("res://scripts/gameplay/world/world_main_background.gd"),"real Root fields point to actual constructed Main views")
					check(views.abort_actual_original_uncommitted_views(_host).get("success") == true,"actual unstarted world views release their owned nodes and SourceFrames handoff")
					check(_root.hud == null and _root.background == null and shell.view.is_inside_tree(),"view abort preserves prepared player shell and actual selected Root")
					check(views.abort_actual_original_uncommitted_views(_host).get("success") != true,"an already retired view owner cannot replay its abort")
				if inputs.get("success") == true:
					check(physical_vault.release_original_actor_input_template(inputs.template_key).get("status") == "READY","actual input template roots retire independently of global original asset caches")
					check(physical_vault.get("_actor_assets").terminal(),"actual actor texture/audio/auxiliary responsibility is empty after template retirement")
	var wrong_generation: Dictionary = observed.world.duplicate(true); wrong_generation.world_epoch = 1
	var rejected_registry := preload("res://scripts/gameplay/presentation/main_actor_visual_registry.gd").new()
	check(not rejected_registry.configure_original_structural_main(_root,wrong_generation,phase_bridge),"negative-map exception never accepts a later generation")
	var initial: Dictionary = _root_transport.prepare_actual_original_world_input(_root,observed.world)
	check(initial.get("success") == true,"actual guarded Main Root publishes its genuine initial InputMap state")
	if initial.get("success") == true:
		check(initial.publication.actions.has("attack") and initial.publication.actions.has("skill_4"),"original Main action registration body executes without gameplay _ready")
		check(_root_transport.prepare_actual_original_world_input(_root,observed.world) == initial,"same initial input publication and owner are reused without a sequence reset")
	# Original code retention is now genuine under its real cover. Exercise the
	# SAME request/monitor bodies on a real cached scene so this synchronous
	# permission component remains inside the original launch stack. This does
	# not claim the full uncached launch scheduler or actual Source adoption.
	_launcher._request_launch_scene_preload()
	var requested_scene_path: String = _launcher.get("_launch_scene_preload_path")
	check(ResourceLoader.load_threaded_get_status(requested_scene_path) == ResourceLoader.THREAD_LOAD_LOADED,"actual accepted cached-scene request is terminal before its genuine monitor")
	if ResourceLoader.load_threaded_get_status(requested_scene_path) != ResourceLoader.THREAD_LOAD_LOADED: return
	_launcher._monitor_launch_scene_preload(int(_launcher.get("_launch_scene_preload_generation")),requested_scene_path)
	check(_launcher.get("_launch_scene_preload_resource") == _resident_scene,"original monitor retrieved the same actual resource through its accepted entitlement")
	var begun: Dictionary = _router.begin_original_character_launch(_launcher,observed.world)
	check(begun.get("success") == true,"real callback ledger proves actual UI receiver closure without empty fabricated counters: "+JSON.stringify(begun))
	if begun.get("success") != true: return
	var paths: Array[String] = [_facade._profile_path(_facade.active_profile_id),_facade.profile_index_path,_facade.shared_warehouse_path]
	var before: Dictionary = {}
	for path: String in paths: before[path] = FileAccess.get_sha256(path)
	var binding_present: bool = _router.has_method("bind_actual_original_launch_loading")
	check(binding_present,"checkpoint binds the same genuine Loading producer instead of returning only a source-site name")
	if binding_present:
		check(_router.bind_actual_original_launch_loading(_loading),"checkpoint adopts the actual existing Loading observer once")
		check(not _router.bind_actual_original_launch_loading(_loading),"repeated Loading binding cannot reset the checkpoint owner")
		var site := {"clock_epoch":0,"domain":"P","entry_id":"res://scripts/game_root.gd:_ready","entry_ordinal":1,"bootstrap":true,"observation_process_epoch":int(begun.checkpoint.process_frame),"world_context":observed.world,"deadline_usec":Time.get_ticks_usec()+1000000}
		var result: Dictionary = _router.verify_original_loading_source_site(site)
		check(result.get("success") == true and result.get("loading_scope") == captured.scope,"Main Loading verification returns the exact physically retained scope to Source consumers")
		var foreign: Dictionary = site.duplicate(true); foreign.world_context.world_runtime_id += 1
		check(_router.verify_original_loading_source_site(foreign).get("success") != true,"another Root cannot borrow this launch scope")
		foreign = site.duplicate(true); foreign.bootstrap = false; foreign.clock_epoch = 1
		check(_router.verify_original_loading_source_site(foreign).get("success") != true,"launch scope does not authorize a later gameplay or map Loading epoch")
		foreign = site.duplicate(true); foreign.observation_process_epoch += 1
		check(_router.verify_original_loading_source_site(foreign).get("success") != true,"source-site observation counter must match the original checkpoint")
	check(_router.abort_original_checkpoint(begun.checkpoint).get("success") == true,"uncommitted checkpoint restores actual UI flags through its original abort body")
	for path: String in paths: check(FileAccess.get_sha256(path) == before[path],"scope capture/verify/abort does not rewrite actual isolated saved document: "+path.get_file())
	check(_fatal.actual_original_main_source_faults().is_empty() and _host.status().get("running") == false,"valid Main preparation neither claims Source nor emits an accidental legacy write")
func apply_original_main_journal_event(_event: Dictionary) -> bool:
	check(false,"no Source prefix is executed by this before-adoption launch fixture")
	return false
func _unexpected_resource_call(_a: Variant = null,_b: Variant = null,_c: Variant = null,_d: Variant = null) -> Dictionary:
	check(false,"pre-Source actual Main view construction must not fabricate Native resource execution")
	return {}
func _finish() -> void:
	set_process(false)
	if _facade != null: _facade.test_mode = true
	if is_instance_valid(_root):
		if _root_transport != null: check(_root_transport.begin_actual_uncommitted_abort(),"actual uncommitted Root authorizes its own exit before teardown")
		_root.free()
	if is_instance_valid(_launcher):
		_launcher.queue_free()
		await _launcher.tree_exited
		await get_tree().process_frame # Actual tree deletion after exit callbacks, not an invented readiness timer.
	if _content != null:
		var idle := Admission.new()
		idle.set("_legacy_resources",_content._feature_resources())
		var until: int = Time.get_ticks_usec()+5000000
		while idle.capture_original_resource_idle_state().get("success") != true and Time.get_ticks_usec() < until:
			await get_tree().process_frame
		check(idle.capture_original_resource_idle_state().get("success") == true,"original Main coordinator actually retires accepted launch code work before fixture exit")
	var scene_id := scene_file_path.get_file().get_basename()
	var written: bool = _proof.write_receipt(scene_id,_proof.records.size(),_failed)
	print(scene_id.to_upper()+"_","PASS" if written and _failed == 0 else "FAIL"," checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
