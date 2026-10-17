extends RefCounted
## Instantiate the genuine prepared Main scene without running legacy gameplay
## _ready. The original loaded GameRoot Script remains installed, so its actual
## Feature code-retention identity is preserved.
var _root: WeakRef
var _script: WeakRef
var _transport: RefCounted
var _loading_scope: Dictionary
var _ready_entered := false
var _exited := false
var _actual_pointer_event: InputEvent
var _callback_depths := {"ready":0,"process":0,"notification":0,"unhandled_input":0,"exit":0}
func owner_thread_id() -> int: return OS.get_main_thread_id()
static func capture_original_constructor_before_tree_entry(root: Node2D) -> Dictionary:
	# Real constructor checkpoint, before removing its original plain combat
	# child and before guarded Main READY. No _ready/RNG is replayed.
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not is_instance_valid(root) or root.is_inside_tree(): return {"success":false,"status":"MISSING","error":"actual_detached_Root_constructor_checkpoint"}
	var combat: Node = root.get("_combat_runtime")
	if not is_instance_valid(combat) or combat.get_parent()!=root or combat.is_inside_tree() or combat.get_script()!=preload("res://scripts/layers/runtime/combat_runtime_service.gd"): return {"success":false,"status":"MISSING","error":"actual_original_combat_constructor_child"}
	var fields: Dictionary = preload("res://scripts/gameplay/source/main_world_source_fields_capture.gd").capture_original_constructor_fields(root)
	if fields.get("success")!=true: return fields
	var value: Dictionary = fields.duplicate(false)
	value.original_combat_source_template = {"name":str(combat.name),"source_path":combat.get_script().resource_path,"source_sha256":combat.get_script().get_source_code().sha256_text(),"process_priority":combat.process_priority,"process_mode":combat.process_mode,"process_enabled":combat.is_processing(),"physics_enabled":combat.is_physics_processing()}
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture(value,true,false)
	return captured.value if captured.get("success")==true else {"success":false,"status":"MISSING","error":"actual_constructor_checkpoint_not_plain"}
static func instantiate_original_source_root(scene: PackedScene, loaded_code: Script, transport: RefCounted, loading_scope: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or scene==null or scene.resource_path!="res://scenes/main.tscn" or loaded_code==null or loaded_code.resource_path!="res://scripts/game_root.gd": return {"success":false,"status":"MISSING","error":"actual_original_prepared_Main_scene_code"}
	for method: String in ["verify_actual_original_source_root_launch","verify_actual_Main_physics_constructor_preflight","bind_actual_original_source_root","original_source_root_ready","service_original_source_world_main_views","submit_original_world_hud_event","submit_original_root_notification","submit_original_root_ui_cancel","record_actual_original_source_root_exit"]:
		if transport==null or not transport.has_method(method): return {"success":false,"status":"MISSING","error":"actual_Main_root_transport:"+method}
	var admitted: Dictionary=transport.verify_actual_original_source_root_launch(scene,loaded_code,loading_scope)
	if admitted.get("success")!=true: return admitted
	var physics: Dictionary=transport.verify_actual_Main_physics_constructor_preflight(scene,loaded_code)
	if physics.get("success")!=true: return physics
	# Pinned main.tscn has one Node2D root. The original _init child below is
	# CombatRuntimeService (plain Node), never CharacterBody2D/Area2D.
	var state: SceneState=scene.get_state()
	if state.get_node_count()!=1 or state.get_node_type(0)!=&"Node2D": return {"success":false,"status":"MISSING","error":"actual_original_Main_scene_topology_changed"}
	var root: Node=scene.instantiate()
	if not root is Node2D or root.get_script()!=loaded_code or root.is_inside_tree() or root.get("_original_source_main_attachment")!=null:
		root.free()
		return {"success":false,"status":"MISSING","error":"actual_original_Main_root_script_identity"}
	# GameRoot._init creates this original gameplay-only Node. Its source
	var constructor: Dictionary = capture_original_constructor_before_tree_entry(root)
	if constructor.get("success")!=true:
		root.free()
		return constructor
	# template is captured while detached; it never enters the Main SceneTree.
	var original_combat: Node=root.get("_combat_runtime")
	if original_combat==null or original_combat.get_script()!=preload("res://scripts/layers/runtime/combat_runtime_service.gd") or original_combat.is_inside_tree():
		root.free()
		return {"success":false,"status":"MISSING","error":"actual_original_CombatRuntime_init_child"}
	var template: Dictionary=constructor.original_combat_source_template
	root.remove_child(original_combat);original_combat.free();root.set("_combat_runtime",null)
	var attachment:=new()
	attachment._root=weakref(root);attachment._script=weakref(loaded_code);attachment._transport=transport;attachment._loading_scope=loading_scope.duplicate(true)
	root.set("_original_source_main_attachment",attachment)
	var bound: Dictionary=transport.bind_actual_original_source_root(root,attachment,loading_scope,template)
	if bound.get("success")!=true:
		root.free()
		return bound
	return {"success":true,"root":root,"attachment":attachment,"actual_root_id":root.get_instance_id(),"original_combat_source_template":template,"original_constructor_capture":constructor}
func original_main_ready(root: Node2D) -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id() and is_same(_root.get_ref(),root) and root.get_script()==_script.get_ref() and not _ready_entered)
	_ready_entered=true
	_callback_depths.ready += 1
	var admitted: Dictionary=_transport.original_source_root_ready(root,self,_loading_scope)
	_callback_depths.ready -= 1
	assert(admitted.get("status") in ["ACCEPTED","PENDING","READY"],"actual_Source_world_ready_admission_failed")
func original_main_process(root: Node2D, delta: float) -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id() and is_same(_root.get_ref(),root))
	if _exited: return
	_callback_depths.process += 1
	if not _transport.service_original_source_world_main_views(root,delta):
		push_error("actual_Main_view_service_failed")
	_callback_depths.process -= 1
func original_main_notification(root: Node2D, what: int) -> void:
	if _exited or what not in [Node.NOTIFICATION_WM_GO_BACK_REQUEST,Node.NOTIFICATION_APPLICATION_PAUSED,Node.NOTIFICATION_APPLICATION_FOCUS_OUT,Node.NOTIFICATION_APPLICATION_RESUMED,Node.NOTIFICATION_WM_CLOSE_REQUEST]: return
	_callback_depths.notification += 1
	_transport.submit_original_root_notification(root,what)
	_callback_depths.notification -= 1
func original_main_unhandled_input(root: Node2D, event: InputEvent) -> void:
	if _exited: return
	_callback_depths.unhandled_input += 1
	if event.is_action_pressed("ui_cancel"):
		_transport.submit_original_root_ui_cancel(root)
	elif not preload("res://scripts/gameplay/presentation/main_original_pick_input.gd").capture_main(root,event).is_empty():
		_actual_pointer_event=event
		_transport.submit_original_root_pointer_press(root)
		_actual_pointer_event=null
	_callback_depths.unhandled_input -= 1
func original_main_exit(root: Node2D) -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id() and is_same(_root.get_ref(),root) and not _exited)
	_exited=true
	_callback_depths.exit += 1
	if not _transport.record_actual_original_source_root_exit(root,self):
		push_error("actual_original_Main_root_exit_receipt_failed")
	_callback_depths.exit -= 1

func verify_actual_original_Main_receiver_closure(root: Node2D) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _exited or not _ready_entered or _root==null or not is_same(_root.get_ref(),root) or _script==null or root.get_script()!=_script.get_ref() or root.get("_original_source_main_attachment")!=self: return {"success":false,"error":"actual_entered_guarded_Main_Root_required"}
	for depth: int in _callback_depths.values():
		if depth != 0: return {"success":false,"error":"actual_Main_Root_callback_not_returned"}
	var physical: Dictionary = _transport.verify_actual_original_Main_root_receiver(root,self)
	if physical.get("success")!=true: return physical
	return {"success":true,"runtime_id":root.get_instance_id(),"script":root.get_script().resource_path,"script_sha256":root.get_script().get_source_code().sha256_text(),"attachment_id":get_instance_id(),"callbacks":_callback_depths.duplicate(true),"actual_transport":physical}
