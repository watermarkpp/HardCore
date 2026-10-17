extends RefCounted
## Real Main observation/preparation before Host.start. No physics body, fake
## root ID or invented scheduler lookup is used. Nonportable state is MISSING.
const Scheduler:=preload("res://scripts/monster_ai_package/path_scheduler.gd")
const Terrain:=preload("res://scripts/monster_terrain_navigation_policy.gd")
const Context:=preload("res://scripts/monster_ai_package/m30/context_token.gd")
const Polygon:=preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Search:=preload("res://scripts/monster_ai_package/path_search.gd")
const Fields:=preload("res://scripts/gameplay/source/source_persistent_path_bindings.gd")
const ObjectCodec:=preload("res://scripts/gameplay/source/source_path_object_codec.gd")
const SCHEDULER_FIELDS: Array[String]=["jobs","queue","service_count","cancelled_count","expansions_count","maximum_wait_frames","diagnostic_pump_calls","diagnostic_pump_usec","maximum_completion_latency_usec","_budget_category"]
var _host: Object
var _tree: SceneTree
var _actual_node: WeakRef
var _admission: WeakRef
var _prepared: Dictionary
var _publication: Dictionary
var _physical_prepared:=false
func owner_thread_id() -> int:return OS.get_main_thread_id()
func prepare_original_path_publication(host: Object,tree: SceneTree,admission: RefCounted,prepared: Dictionary,actualWorldRoot: Node2D) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host!=null or host==null or not host.is_class("HardCoreSimulationHost") or tree==null:return _missing("actual_Main_once_Path_capture")
	if host.status().get("running")==true or not is_instance_valid(actualWorldRoot) or not actualWorldRoot.is_inside_tree() or actualWorldRoot.get_parent()!=tree.root or actualWorldRoot.get_script()!=preload("res://scripts/game_root.gd"):return _missing("actual_Main_Root_membership_before_backend_claim")
	if admission==null or not admission.get("_gate") is RefCounted or not admission.get("_gate").has_method("state") or admission.get("_committed")!=false or admission.get("_prepared")!=prepared.get("receipt") or prepared.get("receipt",{}).get("contract_id")!="hardcore.main.profile_source.prepared.v1" or admission.get("_gate").state()!="PREPARED":return _missing("actual_original_Profile_preparation")
	var found: Node=tree.root.get_node_or_null(NodePath(Scheduler.NODE_NAME))
	if found!=null and found.get_script()!=Scheduler:return _missing("original_named_child_has_other_Script")
	if found!=null and found.is_queued_for_deletion():return _missing("actual_Main_queued_scheduler_lifetime_handoff")
	if found!=null and (not found.jobs.is_empty() or not found.queue.is_empty()):return _missing("actual_Main_pending_path_search_or_callback_handoff",{"jobs":found.jobs.size(),"queue":found.queue.size()})
	# Existing polygon cache objects cross as exact value descriptors, then are
	# reconstructed on S with the same joint-root aliases and container modes.
	var state: Dictionary={"terrain_state":{"_budget_physics_frame":Terrain._budget_physics_frame,"_queries_this_physics_frame":Terrain._queries_this_physics_frame,"_path_query_count":Terrain._path_query_count,"_path_budget_rejection_count":Terrain._path_budget_rejection_count,"_path_expansion_count":Terrain._path_expansion_count,"_walkability_context_caches":Terrain._walkability_context_caches},
		"context_state":{"_contexts":Context._contexts,"_tokens":Context._tokens,"_next_token":Context._next_token},"polygon_state":{"_loaded":Polygon._loaded,"_pending":Polygon._pending},
		"shared_state":{"shared_heuristics":Search.shared_heuristics,"shared_heuristic_order":Search.shared_heuristic_order,"shared_walkability":Search.shared_walkability,"shared_walkability_order":Search.shared_walkability_order,"shared_goal_fields":Search.shared_goal_fields,"shared_goal_field_order":Search.shared_goal_field_order,"diagnostic_frontier_rebuilds":Search.diagnostic_frontier_rebuilds,"diagnostic_frontier_rebuild_usec":Search.diagnostic_frontier_rebuild_usec,"diagnostic_frontier_rebuild_max_cells":Search.diagnostic_frontier_rebuild_max_cells,"diagnostic_shared_field_services":Search.diagnostic_shared_field_services,"diagnostic_shared_field_expansions":Search.diagnostic_shared_field_expansions,"diagnostic_shared_field_fallbacks":Search.diagnostic_shared_field_fallbacks}}
	for part: String in state:
		for field: String in state[part]:
			if state[part][field]==null:return _missing("actual_Main_static_field_get_failed",{"part":part,"field":field})
	var scheduler_state: Dictionary={}
	if found!=null:scheduler_state={"fields":_fields(found,SCHEDULER_FIELDS),"scope":_scope(found),"original_node_id":found.get_instance_id()}
	state["scheduler_state"]=scheduler_state
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var checked: Dictionary=ObjectCodec.capture(state)
	if checked.get("ok")!=true:return _missing("actual_nonplain_Main_path_static_state_handoff",checked)
	# This actual Node template never enters the tree or runs _ready. The native
	# Node READY algorithm and its genuine script override define later birth.
	var template: Node=Scheduler.new()
	var scheduler_script: Script=Scheduler
	var birth: Dictionary={"script_path":scheduler_script.resource_path,"script_sha256":_script_source_sha(scheduler_script),"disk_script_sha256":FileAccess.get_sha256(scheduler_script.resource_path),"has_physics_callback":template.has_method("_physics_process"),"scope":_scope(template),"actual_constructor_node_id":template.get_instance_id()}
	template.free()
	if birth.script_sha256.is_empty():return _missing("actual_loaded_Path_script_source_SHA")
	var membership: Dictionary=capture_actual_root_membership(tree)
	if membership.get("success")!=true:return membership
	var children: Array=membership.root_children
	var lookup: Dictionary={"found":found!=null,"parent_id":tree.root.get_instance_id(),"node_id":found.get_instance_id() if found!=null else 0,"actual_prepared_transfer":found!=null}
	# One authority for the joint state, object descriptors and container modes.
	# Repeating the same roots/modes as top-level fields doubles expanded graph
	# accounting even when their aliases are retained by the Native copier.
	var captured: Dictionary=graph.capture({"contract_id":"source.path.main_handoff.v1","source_tree_root":membership.source_tree_root,"tree_paused":tree.paused,"root_children":children,"scheduler_lookup":lookup,"birth_template":birth,"path_object_publication":checked.value,"prepared_profile_receipt":prepared.receipt,"capture_process_frame":Engine.get_process_frames(),"capture_physics_frame":Engine.get_physics_frames()},true,false)
	if captured.get("success")!=true:return _missing("actual_Path_publication_graph",captured)
	_host=host;_tree=tree;_admission=weakref(admission);_prepared=prepared;_publication=captured.value
	if found!=null:
		_actual_node=weakref(found)
		# Ownership preparation, not a performance shortcut: actual state was
		# captured first, and Source imports/dispatches the identical H callback.
		found.set_physics_process(false);_physical_prepared=true
	return {"success":true,"publication":_publication}
func abort_original_path_preparation(prepared_receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host==null or _host.status().get("running")==true or prepared_receipt!=_prepared.receipt:return false
	var actual_admission: RefCounted=_admission.get_ref()
	if actual_admission==null or actual_admission.get("_committed")!=false or actual_admission.get("_prepared")!=prepared_receipt or actual_admission.get("_gate").state()!="PREPARED":return false
	if _physical_prepared and _actual_node.get_ref()!=null:_actual_node.get_ref().set_physics_process(_publication.path_object_publication.roots.scheduler_state.scope.physics_processing_enabled)
	_physical_prepared=false
	return true
static func capture_actual_root_membership(tree: SceneTree) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or tree==null or not tree.root.is_inside_tree():return _missing("actual_Main_source_root_membership_required")
	var normal: Array[Node]=tree.root.get_children(false)
	if normal.is_empty():return _missing("actual_persistent_autoload_sibling_required")
	var children: Array[Dictionary]=[]
	for child: Node in tree.root.get_children(true):
		var script: Script=child.get_script()
		children.append({"node_id":child.get_instance_id(),"parent_id":tree.root.get_instance_id(),"index":child.get_index(true),"name":child.name,"script_path":script.resource_path if script!=null else "","loaded_script_sha256":_script_source_sha(script),"native_class":child.get_class(),"inside_tree":child.is_inside_tree()})
	var scheduler: Node=tree.root.get_node_or_null(NodePath(Scheduler.NODE_NAME))
	return {"success":true,"source_tree_root":{"node_id":tree.root.get_instance_id(),"native_class":tree.root.get_class(),"inside_tree":true,"normal_child_count":normal.size(),"normal_append_index":normal.back().get_index(true)+1,"effective_process_mode":_scope(tree.root).effective_process_mode},"root_children":children,"tree_paused":tree.paused,"scheduler_lookup":{"found":scheduler!=null,"parent_id":tree.root.get_instance_id(),"node_id":scheduler.get_instance_id() if scheduler!=null else 0}}
static func _script_source_sha(script: Script) -> String:
	if script==null or not script.has_source_code():return ""
	var hashing:=HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256)!=OK:return ""
	if hashing.update(script.get_source_code().to_utf8_buffer())!=OK:return ""
	return hashing.finish().hex_encode()
static func _fields(source: Object,fields: Array[String]) -> Dictionary:
	var out: Dictionary={}
	for key: String in fields:out[key]=source.get(key)
	return out
static func _scope(node: Node) -> Dictionary:
	var process_mode: int=node.process_mode
	var ancestor: Node=node
	while process_mode==Node.PROCESS_MODE_INHERIT and ancestor.get_parent()!=null:
		ancestor=ancestor.get_parent();process_mode=ancestor.process_mode
	if process_mode==Node.PROCESS_MODE_INHERIT:process_mode=Node.PROCESS_MODE_PAUSABLE
	return {"runtime_present":is_instance_valid(node),"inside_world":node.is_inside_tree(),"queued_for_retirement":node.is_queued_for_deletion(),"parent_scope_id":node.get_parent().get_instance_id() if node.get_parent()!=null else 0,"can_process":node.can_process() if node.is_inside_tree() else false,"process_processing_enabled":node.is_processing(),"physics_processing_enabled":node.is_physics_processing(),"ordinary_p_enabled":node.has_method("_process"),"raw_h_enabled":node.has_method("_physics_process"),"physics_priority":node.process_physics_priority,"process_priority":node.process_priority,"process_mode":node.process_mode,"effective_process_mode":process_mode}
static func _missing(code: String,details: Dictionary={}) -> Dictionary:return {"success":false,"status":"MISSING","error":code,"details":details}
