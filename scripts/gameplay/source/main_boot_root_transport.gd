extends RefCounted
## Concrete bridge used by the existing original GameRoot attachment.
## No physics actor, second model, input queue or frame scheduler is created.
const Observe := preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
const Loading := preload("res://scripts/gameplay/source/main_boot_launch_loading.gd")
const Views := preload("res://scripts/gameplay/world/world_main_views.gd")
const Attachment := preload("res://scripts/gameplay/world/world_main_root_attachment.gd")
const ROOT_SHA256 := "e148e75952a3dfae5b2256075ccdd00253e5f8eecc575d6823c83084edd06121"
const COMBAT_SHA256 := "49f65a1aba619f3915ab9910c2d45cad29ecca93d0522777899a1cfa1e682fbf"
var _host: Object
var _facade: Node
var _loading: RefCounted
var _transport: RefCounted
var _root: WeakRef
var _attachment: WeakRef
var _world: Dictionary
var _scope: Dictionary
var _combat_template: Dictionary
var _views: RefCounted
var _input_publisher: RefCounted
var _initial_input: Dictionary
var _ready_entered := false
var _aborting := false
var _exited := false
var _normal_terminal_authorization: Dictionary
var _normal_exit_receipt: Dictionary
var _window_quit_policy_acquired := false
var _previous_auto_accept_quit := false

func owner_thread_id() -> int: return OS.get_main_thread_id()

func configure_main(host: Object, loading: RefCounted, transport: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host != null: return false
	if host == null or not host.is_class("HardCoreSimulationHost") or loading == null or loading.get_script() != Loading: return false
	if transport == null or transport.get_script() != preload("res://scripts/gameplay/source/main_session_transport.gd"): return false
	_host = host; _loading = loading; _transport = transport; _facade = loading.get("_facade")
	if not is_instance_valid(_facade): return false
	return true

func verify_actual_original_source_root_launch(scene: PackedScene, code: Script, scope: Dictionary) -> Dictionary:
	if _host == null or _root != null or scene == null or scene.resource_path != "res://scenes/main.tscn" or code != preload("res://scripts/game_root.gd"): return _blocked("actual_single_prepared_original_Main_root_required")
	return _loading.verify_actual_original_loading_scope(scope)

static func inspect_actual_Main_constructor(host: Object, scene: PackedScene, code: Script) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or host == null or not host.is_class("HardCoreSimulationHost"): return _blocked("actual_Main_Host_preclaim_required")
	if host.status().get("running") == true: return _blocked("Main_GameRoot_constructor_after_Source_claim_forbidden")
	if scene == null or scene.resource_path != "res://scenes/main.tscn" or code != preload("res://scripts/game_root.gd"): return _blocked("actual_original_Main_scene_script_required")
	var state: SceneState = scene.get_state()
	if state.get_node_count() != 1 or state.get_node_type(0) != &"Node2D": return _blocked("actual_original_Main_scene_topology_changed")
	var actual_scene_script: Script
	for index: int in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0,index) == &"script": actual_scene_script = state.get_node_property_value(0,index)
	if actual_scene_script != code: return _blocked("actual_original_Main_scene_script_binding_changed")
	var combat_code: Script = preload("res://scripts/layers/runtime/combat_runtime_service.gd")
	if code.get_source_code().sha256_text() != ROOT_SHA256 or combat_code.get_source_code().sha256_text() != COMBAT_SHA256: return _blocked("reviewed_Main_constructor_source_changed")
	# These exact preimages have only the original plain CombatRuntimeService
	# child at _init. The attachment removes it before tree membership. Hash
	# drift blocks BEFORE scene.instantiate, not after a forbidden constructor.
	return {"success":true, "actual_Main_thread_id":OS.get_thread_caller_id(),
		"host_object_id":host.get_instance_id(), "root_source_sha256":ROOT_SHA256,
		"combat_source_sha256":COMBAT_SHA256, "scene_node_count":state.get_node_count(),
		"source_process_frame":Engine.get_process_frames()}

func verify_actual_Main_physics_constructor_preflight(scene: PackedScene, code: Script) -> Dictionary:
	return inspect_actual_Main_constructor(_host,scene,code)

func bind_actual_original_source_root(root: Node2D, attachment: RefCounted, scope: Dictionary, combat_template: Dictionary) -> Dictionary:
	if _root != null or root == null or root.is_inside_tree() or root.get_script() != preload("res://scripts/game_root.gd") or attachment == null or attachment.get_script() != Attachment or root.get("_original_source_main_attachment") != attachment: return _blocked("actual_detached_original_attachment_binding_required")
	var checked: Dictionary = _loading.verify_actual_original_loading_scope(scope)
	if checked.get("success") != true: return checked
	if root.get_child_count(true) != 0 or root.get("_combat_runtime") != null or combat_template.get("source_sha256") != COMBAT_SHA256: return _blocked("actual_original_plain_CombatRuntime_removal_required")
	_root = weakref(root); _attachment = weakref(attachment); _scope = scope.duplicate(true); _combat_template = combat_template.duplicate(true)
	return {"success":true, "actual_root_id":root.get_instance_id()}

func original_source_root_ready(root: Node2D, attachment: RefCounted, scope: Dictionary) -> Dictionary:
	if not _same_root(root) or _ready_entered or not is_same(attachment,_attachment.get_ref()) or scope != _scope: return _blocked("actual_once_original_Main_ready_required")
	# Original GameRoot._ready sets this on its SceneTree. The guarded Main
	# Root skips that gameplay body, so preserve its real window-routing effect
	# here; Source's virtual tree flag cannot suppress Main's automatic quit.
	_previous_auto_accept_quit = root.get_tree().auto_accept_quit
	root.get_tree().auto_accept_quit = false
	_window_quit_policy_acquired = true
	_ready_entered = true
	return {"success":false, "status":"PENDING", "actual_root_id":root.get_instance_id(), "reason":"actual_Source_assembly_not_adopted"}

func verify_actual_original_Main_root_receiver(root: Node2D,attachment: RefCounted) -> Dictionary:
	if not _same_root(root) or not root.is_inside_tree() or not _ready_entered or _aborting or _attachment==null or not is_same(_attachment.get_ref(),attachment) or attachment.get_script()!=Attachment or root.get("_original_source_main_attachment")!=attachment or root.get_script().get_source_code().sha256_text()!=ROOT_SHA256: return _blocked("actual_same_guarded_Main_Root_receiver_required")
	return {"success":true,"actual_root_id":root.get_instance_id(),"actual_attachment_id":attachment.get_instance_id(),"actual_host_id":_host.get_instance_id(),"guarded_original_ready_returned":true}

func bind_actual_original_world_views(world: Dictionary, views: RefCounted) -> Dictionary:
	if _views != null or _root == null or not is_instance_valid(_root.get_ref()) or views == null or views.get_script() != Views: return _blocked("actual_original_Main_views_required")
	if world.get("world_runtime_id") != _root.get_ref().get_instance_id() or views.get("_root") != _root.get_ref() or views.get("_world") != world: return _blocked("actual_same_world_Main_views_required")
	if _input_publisher == null or _initial_input.get("world_context") != world: return _blocked("actual_prepared_original_Main_input_owner_required")
	var hud: Node = views.get("_views").get("hud")
	if not is_instance_valid(hud) or not is_instance_valid(hud.get("attack_button")) or not _input_publisher.bind_original_attack_button(hud.get("attack_button")): return _blocked("actual_original_Main_attack_button_required")
	if not _transport.bind_actual_original_world_input(_input_publisher,world): return _blocked("actual_Main_input_transport_binding")
	_world = world.duplicate(true); _views = views
	return {"success":true}

func prepare_actual_original_world_input(root: Node2D,world: Dictionary) -> Dictionary:
	if not _same_root(root) or world.get("world_runtime_id") != root.get_instance_id(): return _blocked("actual_guarded_Root_input_owner_required")
	if _input_publisher != null:
		return {"success":true,"publication":_initial_input.duplicate(true)} if _initial_input.get("world_context") == world else _blocked("actual_input_owner_world_changed")
	var publisher: RefCounted = preload("res://scripts/gameplay/source/main_original_world_input.gd").new()
	if not publisher.configure_main(root,world): return _blocked("actual_Main_input_configuration")
	var initial: Dictionary = publisher.capture_original_main_input(0)
	if initial.get("success") != true: return initial
	_input_publisher = publisher; _initial_input = initial.publication
	return {"success":true,"publication":_initial_input.duplicate(true)}

func service_original_source_world_main_views(root: Node2D, _delta: float) -> bool:
	if not _same_root(root): return false
	# There is no prepared view service to advance before actual publication.
	if _views == null: return _host.status().get("running") != true
	return _views.service_actual_Main_overlay_demands()

func submit_original_world_hud_event(world: Dictionary, name: StringName, args: Array, context: Dictionary, sequence: int) -> Dictionary:
	if _views == null or world != _world: return _blocked("actual_bound_Main_world_views_required")
	return _transport.submit_original_world_hud_event(world,name,args,context,sequence)

func submit_original_root_notification(root: Node2D, what: int) -> Dictionary:
	if not _same_root(root): return _blocked("actual_original_Main_root_required")
	return _submit_actual_original_root_input(root,&"notification",[what])

func submit_original_root_ui_cancel(root: Node2D) -> Dictionary:
	if not _same_root(root): return _blocked("actual_original_Main_root_required")
	return _submit_actual_original_root_input(root,&"unhandled_ui_cancel",[])

func submit_original_root_pointer_press(root: Node2D) -> Dictionary:
	if not _same_root(root): return _blocked("actual_original_Main_root_required")
	return _submit_actual_original_root_input(root,&"viewport_pick_press",[])

func _submit_actual_original_root_input(root: Node2D, name: StringName, args: Array) -> Dictionary:
	if _views == null or _attachment == null or _attachment.get_ref() == null: return _blocked("actual_bound_Main_Root_input_owner_required")
	# Reuse the original view input outbox, sequence and Native submission.
	# Backpressure leaves this exact callback captured, never replays gameplay.
	var captured: Dictionary = _views.submit_actual_original_root_input(root,_attachment.get_ref(),name,args)
	return {"success":captured.get("status") in ["RETAINED","CLOSED"],"status":captured.get("status","INVALID"),"details":captured}

func begin_actual_uncommitted_abort() -> bool:
	if _host == null or not is_instance_valid(_facade) or _host.status().get("running") == true or _views != null: return false
	var gate: RefCounted = _facade.get("_source_domain_gate")
	if gate != null and gate.state() != "MAIN": return false
	_aborting = true
	return true

func record_actual_original_source_root_exit(root: Node2D, attachment: RefCounted) -> bool:
	if not _same_root(root) or not is_same(_attachment.get_ref(),attachment): return false
	if not _aborting:
		if _normal_terminal_authorization.is_empty() or attachment.get("_exited") != true or attachment.get("_callback_depths").get("exit") != 1 or _transport.get("_state") != "CLOSED" or _transport.get("_terminal") != _normal_terminal_authorization.terminal: return false
		for callback: String in attachment.get("_callback_depths"):
			if callback != "exit" and attachment.get("_callback_depths")[callback] != 0: return false
		_normal_exit_receipt = {"success":true,"actual_root_id":root.get_instance_id(),"actual_attachment_id":attachment.get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}
	if _window_quit_policy_acquired and (_host.status().get("started") == false or not _normal_terminal_authorization.is_empty()):
		root.get_tree().auto_accept_quit = _previous_auto_accept_quit
		_window_quit_policy_acquired = false
	_exited = true
	return true

func finish_actual_original_terminal_root_exit(source_exit: Dictionary, terminal: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _transport == null or _aborting or _exited or not _normal_terminal_authorization.is_empty(): return _blocked("actual_once_Main_terminal_Root_exit_required")
	var root: Node2D = retained_root()
	var attachment: RefCounted = _attachment.get_ref() if _attachment != null else null
	if not is_instance_valid(root) or attachment == null or not root.is_inside_tree() or root.get_parent() != root.get_tree().root or _views == null or source_exit.get("actual_root_id") != root.get_instance_id() or source_exit.get("fact",{}).get("world_context") != _world or _transport.get("_state") != "CLOSED" or terminal.get("success") != true or terminal != _transport.get("_terminal"): return _blocked("actual_same_Source_exit_and_Main_terminal_required")
	var application: Variant = root.get_tree().root.get_meta(&"hardcore_original_main_boot_application",null)
	if not application is RefCounted or application.get_script().resource_path != "res://scripts/gameplay/source/main_boot_application.gd" or not is_same(application.get("_root_transport"),self) or application.get("_actual_source_root_exit") != source_exit or application.get("_actual_loading_release").get("success") != true or application.get("_terminal_transition_active") != true: return _blocked("actual_same_Main_application_terminal_owner_required")
	var native: Dictionary = _host.status()
	if native.get("close_quiescent") != true or native.get("join_complete") != true or native.get("map_owner_closed") != true or native.get("running") != false: return _blocked("actual_Map_and_Host_terminal_required_before_Main_Root_exit")
	if attachment.verify_actual_original_Main_receiver_closure(root).get("success") != true: return _blocked("actual_Main_Root_callback_not_returned")
	_normal_terminal_authorization = {"terminal":terminal.duplicate(true),"source_exit":source_exit.duplicate(true)}
	var tree: SceneTree = root.get_tree()
	var root_id: int = root.get_instance_id()
	if tree.current_scene == root: tree.current_scene = null
	# Real propagation invokes Attachment.original_main_exit; no direct ACK.
	root.free()
	if not _exited or is_instance_id_valid(root_id) or _normal_exit_receipt.get("success") != true: return _blocked("actual_Main_Root_exit_callback_or_final_free_missing")
	_root = null; _attachment = null; _views = null; _input_publisher = null
	_scope = {}; _combat_template = {}; _initial_input = {}
	return _normal_exit_receipt.duplicate(true)

func retained_root() -> Node2D: return _root.get_ref() if _root != null else null

func can_commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not _same_root(retained_root()) or _world != transaction.get("before_world") or _views == null or _aborting or _exited or _input_publisher == null: return false
	return _input_publisher.can_commit_actual_original_map_arrival(transaction) and _host.verify_committed_original_map_arrival(transaction)
func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_commit_actual_original_map_arrival(transaction): return false
	# The transport commits the same input publisher. Do not reset its serial or
	# rewrite the initial input checkpoint retained in the immutable boot.
	_world = transaction.after_world.duplicate(true)
	return true
func forget_actual_uncommitted_root(root: Node2D) -> bool:
	if _host == null or _host.status().get("running") == true or _views != null or _root == null or not is_same(_root.get_ref(),root): return false
	if root.is_inside_tree() and not _aborting: return false
	_root = null; _attachment = null; _scope = {}; _combat_template = {}
	_input_publisher = null; _initial_input = {}
	_ready_entered = false; _aborting = false; _exited = false
	return true
func _same_root(root: Node2D) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and not _exited and _root != null and is_instance_valid(root) and is_same(_root.get_ref(),root)
static func _blocked(code: String) -> Dictionary: return {"success":false,"status":"BLOCKED","error":code}
