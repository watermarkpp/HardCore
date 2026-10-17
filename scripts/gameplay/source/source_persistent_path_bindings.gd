extends RefCounted
## All six objects live with Session, not with its first Core. JobLink keeps
## its original resolver separately; this service never redirects accepted jobs.
const Polygon:=preload("res://scripts/gameplay/enemy/enemy_owner_polygon_runtime.gd")
const Terrain:=preload("res://scripts/gameplay/enemy/enemy_owner_terrain_navigation.gd")
const Context:=preload("res://scripts/gameplay/enemy/enemy_owner_context_token.gd")
const StateGraph:=preload("res://scripts/gameplay/source/source_path_state_graph.gd")
const TERRAIN_FIELDS: Array[String]=["_budget_physics_frame","_queries_this_physics_frame","_path_query_count","_path_budget_rejection_count","_path_expansion_count","_walkability_context_caches"]
const CONTEXT_FIELDS: Array[String]=["_contexts","_tokens","_next_token"]
const POLYGON_FIELDS: Array[String]=["_loaded","_pending"]
const SHARED_FIELDS: Array[String]=["shared_heuristics","shared_heuristic_order","shared_walkability","shared_walkability_order","shared_goal_fields","shared_goal_field_order","diagnostic_frontier_rebuilds","diagnostic_frontier_rebuild_usec","diagnostic_frontier_rebuild_max_cells","diagnostic_shared_field_services","diagnostic_shared_field_expansions","diagnostic_shared_field_fallbacks"]
var _owner:=OS.get_thread_caller_id()
var _session: WeakRef
var _tree: WeakRef
var _publication: Dictionary
var _state: Dictionary
var _bindings: Dictionary
var _shared_adopted:=false
func owner_thread_id() -> int:return _owner
func configure_bootstrap(publication: Dictionary,tree: RefCounted) -> bool:
	if _tree!=null or _owner==OS.get_main_thread_id() or publication.get("contract_id")!="source.path.main_handoff.v1" or tree.owner_thread_id()!=_owner:return false
	for key: String in ["scheduler_lookup","root_children","birth_template"]:
		if not publication.has(key):return false
	var restored: Dictionary
	if publication.has("path_object_publication"):
		if not publication.path_object_publication is Dictionary or publication.has("state_roots") or publication.has("container_modes"): return false
		restored = preload("res://scripts/gameplay/source/source_path_object_codec.gd").restore(publication.path_object_publication)
	else:
		if not publication.get("state_roots") is Dictionary or not publication.get("container_modes") is Array: return false
		restored = StateGraph.restore(publication.state_roots,publication.container_modes)
	if restored.get("ok")!=true:return false
	_state=restored.value
	_tree=weakref(tree);_publication=publication
	return true
func actual_persistent_path_bindings(session: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or session==null or session.owner_thread_id()!=_owner or _tree==null:return {}
	if _session!=null:return _bindings if is_same(_session.get_ref(),session) else {}
	if not session.has_method("original_source_session_clock"):return {}
	for key: String in ["terrain_state","context_state","polygon_state","shared_state","scheduler_state"]:
		if not _state.get(key) is Dictionary:return {}
	var clock: RefCounted=session.original_source_session_clock()
	var budget: RefCounted=session.original_frame_budget()
	var access: RefCounted=session.original_service_actors()
	var polygon:=Polygon.new()
	var terrain:=Terrain.new()
	var context:=Context.new()
	if not polygon.configure_owner({},access) or not context.configure_owner({},access) or not terrain.configure_owner({"Engine":clock,"HCPPolyRuntime":polygon},access):return {}
	# Native copied this joint publication as one runtime graph; assigning each
	# root preserves its imported alias relationships and actual counter values.
	if not _adopt_exact(polygon,_state.polygon_state,POLYGON_FIELDS) or not _adopt_exact(context,_state.context_state,CONTEXT_FIELDS) or not _adopt_exact(terrain,_state.terrain_state,TERRAIN_FIELDS):return {}
	if not _tree.get_ref().bind_original_path_session(session,self):return {}
	_session=weakref(session)
	_bindings={"Terrain":terrain,"HCM30ContextTokenScript":context,"HCPPolyRuntime":polygon,"FrameBudget":budget,"Engine":clock,"Time":clock}
	return _bindings
func owns_exact_bindings(bindings: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=_owner or _bindings.is_empty() or bindings.size()!=6:return false
	for key: String in _bindings:
		if not bindings.has(key) or not is_same(bindings[key],_bindings[key]):return false
	return true
func adopt_original_shared_search_state(shared: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_owner or _shared_adopted or _bindings.is_empty() or shared.owner_thread_id()!=_owner:return false
	if not _adopt_exact(shared,_state.shared_state,SHARED_FIELDS):return false
	_shared_adopted=true
	return true
func actual_original_static_state() -> Dictionary:return _state
static func _adopt_exact(target: RefCounted,state: Dictionary,fields: Array[String]) -> bool:
	var expected: Array=fields.duplicate();var actual: Array=state.keys();expected.sort();actual.sort()
	if actual!=expected:return false
	for key: String in fields:
		if typeof(target.get(key))!=typeof(state[key]):return false
	for key: String in fields:target.set(key,state[key])
	return true
func original_static_owner_evidence() -> Dictionary:
	return {"owner":_owner,"session":_session.get_ref().original_budget_session_id() if _session!=null else 0,"bindings_ids":_bindings_ids(),"shared_adopted":_shared_adopted}
func _bindings_ids() -> Dictionary:
	var out: Dictionary={}
	for key: String in _bindings:out[key]=_bindings[key].get_instance_id()
	return out
