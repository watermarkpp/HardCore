extends RefCounted
const Attachment:=preload("res://scripts/gameplay/world/world_main_root_attachment.gd")
const Observe:=preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
var _host: Object
var _launch: RefCounted
var _transport: RefCounted
var _identity: RefCounted
var _root: Node2D
var _receipt: Dictionary
func owner_thread_id() -> int:return OS.get_main_thread_id()
func configure_main(host: Object,actual_launch: RefCounted,actual_root_transport: RefCounted,actual_identity: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host!=null or host==null or not host.is_class("HardCoreSimulationHost"):return false
	if actual_launch==null or not actual_launch.has_method("capture_actual_original_launch_loading_scope") or actual_identity==null or not actual_identity.has_method("capture_actual_original_prepared_world_identity"):return false
	_host=host;_launch=actual_launch;_transport=actual_root_transport;_identity=actual_identity;return true
func prepare_original_character_blueprint(receiver: Node) -> Dictionary:
	if _host==null or _root!=null or not is_instance_valid(receiver) or receiver.get_script()!=preload("res://scripts/character_select.gd") or receiver!=receiver.get_tree().current_scene or not receiver._launch_in_progress:return Observe.missing("actual_current_CharacterSelect_launch")
	if _host.status().get("running")==true:return Observe.missing("actual_Main_pre_backend_claim_boundary")
	var scene: PackedScene=receiver._launch_scene_preload_resource
	var result: Dictionary=receiver._launch_code_result
	if scene==null or scene.resource_path!="res://scenes/main.tscn" or result.get("success")!=true or not result.get("lease") is RefCounted:return Observe.missing("actual_prepared_scene_and_code_lease")
	var code: Script=preload("res://scripts/game_root.gd")
	# Original PackedScene pins its own Root Script. The distinct internal code
	# lease is verified by the actual Loading owner below, not resource_at().
	var state: SceneState = scene.get_state()
	if state.get_node_count() != 1 or state.get_node_type(0) != &"Node2D": return Observe.missing("actual_original_prepared_scene_topology")
	var scene_code: Script
	for index: int in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0,index) == &"script": scene_code = state.get_node_property_value(0,index)
	if scene_code != code: return Observe.missing("actual_original_prepared_scene_Root_script_binding")
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_CAPTURE_ORIGINAL_COVER")
	var loading: Dictionary=_launch.capture_actual_original_launch_loading_scope(receiver,result)
	if loading.get("success")!=true or not loading.get("scope") is Dictionary:return Observe.missing("actual_original_launch_Loading_scope",loading)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ORIGINAL_MAIN_ROOT_CONSTRUCTOR")
	var born: Dictionary=Attachment.instantiate_original_source_root(scene,code,_transport,loading.scope)
	if born.get("success")!=true:return born
	_root=born.root
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_PREPARED_WORLD_IDENTITY")
	var identity: Dictionary=_identity.capture_actual_original_prepared_world_identity(_root,receiver,loading.scope)
	if identity.get("success")!=true or not identity.get("world") is Dictionary or identity.world.get("world_runtime_id")!=_root.get_instance_id():
		var rejected: Dictionary = identity if identity.get("success")!=true else Observe.missing("actual_world_authoring_session_identity",{"actual_root_observation":Observe.node(_root),"identity":identity})
		var cleanup: Dictionary = discard_actual_uncommitted_blueprint()
		if cleanup.get("success")!=true: return Observe.missing("actual_uncommitted_Main_root_cleanup_failed",{"cause":rejected,"cleanup":cleanup})
		return rejected
	# The existing root bridge binds actual Main READY; no legacy gameplay runs.
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_GUARDED_ROOT_TREE_ENTRY")
	receiver.get_tree().root.add_child(_root)
	if not _root.is_inside_tree() or _root.get("_original_source_main_attachment")!=born.attachment:return Observe.missing("actual_guarded_Main_root_membership")
	_receipt={"contract_id":"hardcore.main.prepared_blueprint.v1","actual_root_id":_root.get_instance_id(),"actual_receiver_id":receiver.get_instance_id(),"world_context":identity.world,"loading_receipt":loading,"actual_attachment_id":born.attachment.get_instance_id(),"root_observation":Observe.node(_root),"combat_source_template":born.original_combat_source_template,"loaded_script_sha256":code.get_source_code().sha256_text()}
	_receipt["original_constructor_capture"]=born.original_constructor_capture
	_receipt["actual_prepared_scene_id"]=scene.get_instance_id()
	_receipt["actual_retained_code_entry_id"]=result.resource.get_instance_id()
	return {"success":true,"root":_root,"world":identity.world,"receipt":_receipt,"attachment":born.attachment}
func actual_original_blueprint_receipt(root: Node2D) -> Dictionary:return _receipt if is_same(root,_root) else {}

func actual_retained_uncommitted_root() -> Node2D:
	return _root if OS.get_thread_caller_id()==OS.get_main_thread_id() else null

func discard_actual_uncommitted_blueprint() -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host==null or _host.status().get("running")==true: return Observe.missing("actual_Main_before_Source_claim_cleanup_required")
	if not is_instance_valid(_root): return {"success":true}
	if not _transport.has_method("begin_actual_uncommitted_abort") or not _transport.has_method("forget_actual_uncommitted_root") or not _transport.begin_actual_uncommitted_abort(): return Observe.missing("actual_uncommitted_Main_root_abort_owner_required")
	var actual: Node2D = _root
	if actual.is_inside_tree(): actual.get_parent().remove_child(actual)
	if not _transport.forget_actual_uncommitted_root(actual): return Observe.missing("actual_uncommitted_Main_root_release_rejected")
	actual.free()
	_root=null; _receipt={}
	return {"success":true}
