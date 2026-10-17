extends RefCounted
## Persistent Source SceneTree-root ledger. Runtime scope owns qualification;
## captured actual Node indices and actual Source append own callback order.
const Scope:=preload("res://scripts/gameplay/world/world_temporal_scope.gd")
var _owner:=OS.get_thread_caller_id()
var _host: Object
var _session: WeakRef
var _bindings_owner: WeakRef
var _publication: Dictionary
var _children: Array[Dictionary]=[]
var _reserved: Dictionary
var _scheduler: WeakRef
var _scope: RefCounted
var _handle: Object
var _row: Dictionary
var _commits:=0
var _retired:=false
var _final:=false
var _actual_tree_exit: Dictionary
func owner_thread_id() -> int:return _owner
func configure_bootstrap(host: Object,publication: Dictionary) -> bool:
	if _host!=null or _owner==OS.get_main_thread_id() or host==null or not host.is_class("HardCoreSimulationHost"):return false
	if publication.get("contract_id")!="source.path.main_handoff.v1" or not publication.get("root_children") is Array or not publication.get("source_tree_root") is Dictionary or not publication.get("scheduler_lookup") is Dictionary:return false
	if not publication.source_tree_root.get("node_id") is int or publication.source_tree_root.node_id<=0 or publication.source_tree_root.get("inside_tree")!=true or publication.source_tree_root.get("effective_process_mode") not in [1,2,3,4] or not publication.source_tree_root.get("normal_child_count") is int or publication.source_tree_root.normal_child_count<0:return false
	if not publication.source_tree_root.get("normal_append_index") is int or publication.source_tree_root.normal_append_index<publication.source_tree_root.normal_child_count:return false
	if publication.get("tree_paused")!=host.current_host_paused():return false
	var seen: Dictionary={}
	for child: Variant in publication.root_children:
		if not child is Dictionary or not child.get("node_id") is int or child.node_id<=0 or seen.has(child.node_id) or not child.get("index") is int or child.index!=_children.size() or child.get("parent_id")!=publication.source_tree_root.node_id:return false
		seen[child.node_id]=true;_children.append(child.duplicate(true))
	var lookup: Dictionary=publication.scheduler_lookup
	if not lookup.get("found") is bool or lookup.get("parent_id")!=publication.source_tree_root.node_id:return false
	if lookup.found and (not seen.has(lookup.get("node_id")) or lookup.get("actual_prepared_transfer")!=true):return false
	_host=host;_publication=publication
	return true
func bind_original_path_session(session: RefCounted,bindings: RefCounted) -> bool:
	if _session!=null:return is_same(_session.get_ref(),session) and is_same(_bindings_owner.get_ref(),bindings)
	if _host==null or session.owner_thread_id()!=_owner or bindings.owner_thread_id()!=_owner:return false
	_session=weakref(session);_bindings_owner=weakref(bindings)
	return true
func validate_original_session_path_bindings(bindings: Dictionary) -> bool:
	return _bindings_owner!=null and _bindings_owner.get_ref()!=null and _bindings_owner.get_ref().owns_exact_bindings(bindings)
func adopt_original_shared_search_state(shared: RefCounted) -> bool:
	return _bindings_owner!=null and _bindings_owner.get_ref()!=null and _bindings_owner.get_ref().adopt_original_shared_search_state(shared)
func lookup_original_source_tree_path_scheduler() -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or _host==null or _final:return {"ok":false}
	if _scheduler!=null and _scheduler.get_ref()!=null:return {"ok":true,"found":true,"handle":_handle,"owner_domain":&"Source"}
	var actual: Dictionary=_publication.scheduler_lookup
	return {"ok":true,"found":actual.found,"owner_domain":&"prepared_Main" if actual.found else &"absent_actual_Main","actual_main_lookup":actual}
func birth_original_source_tree_path_scheduler() -> Dictionary:
	if _session==null or _scheduler!=null or not _reserved.is_empty() or _final:return {"ok":false}
	var template: Dictionary=_publication.birth_template
	if template.get("script_path")!="res://scripts/monster_ai_package/path_scheduler.gd" or template.get("has_physics_callback")!=true or not template.get("script_sha256") is String or template.script_sha256.length()!=64:return {"ok":false}
	var adoption: bool=_publication.scheduler_lookup.found
	var actual: Dictionary=_bindings_owner.get_ref().actual_original_static_state().scheduler_state.scope if adoption else template.scope
	_scope=Scope.new()
	var source: Dictionary=actual.duplicate(true)
	# Life generation comes from this actual new Source qualification constructor.
	# Admission is separate from original tree membership/ready commit below.
	source.life_generation=_scope.life_generation
	source.inside_world=false;source.parent_scope_id=_publication.source_tree_root.node_id
	if not adoption and source.process_mode==0:source.effective_process_mode=_publication.source_tree_root.effective_process_mode
	if not _scope.configure_source(source,_session.get_ref()):return {"ok":false}
	_reserved={"scope":_scope,"adoption":adoption,"source_tree_runtime_id":_publication.source_tree_root.node_id,"original_main_lookup":_publication.scheduler_lookup}
	return {"ok":true,"scope":_scope,"source_tree_runtime_id":_publication.source_tree_root.node_id,"adoption":adoption}
func commit_original_source_tree_path_scheduler(handle: Object,scope: RefCounted,scheduler: RefCounted,method: StringName,priority: int) -> bool:
	if OS.get_thread_caller_id()!=_owner or _reserved.is_empty() or handle==null or scheduler==null or not is_same(scope,_scope) or handle.get_instance_id()<=0 or scheduler.owner_thread_id()!=_owner or method!=&"original_physics_pump" or _commits!=0:return false
	var adoption: bool=_reserved.adoption
	var scheduler_state: Dictionary=_bindings_owner.get_ref().actual_original_static_state().scheduler_state
	var adopted_row: Dictionary={}
	if adoption:
		if not scheduler_state.get("scope") is Dictionary or not scheduler_state.get("fields") is Dictionary:return false
		if priority!=scheduler_state.scope.get("physics_priority"):return false
		for child: Dictionary in _children:
			if child.node_id==_publication.scheduler_lookup.node_id:adopted_row=child;break
		if adopted_row.is_empty():return false
		var fields: Array[String]=["jobs","queue","service_count","cancelled_count","expansions_count","maximum_wait_frames","diagnostic_pump_calls","diagnostic_pump_usec","maximum_completion_latency_usec","_budget_category"]
		var state: Dictionary=scheduler_state.fields
		var expected: Array=fields.duplicate();expected.sort()
		var actual: Array=state.keys();actual.sort()
		if actual!=expected or not state.jobs is Dictionary or not state.queue is Array or not state.jobs.is_empty() or not state.queue.is_empty():return false
		for key: String in fields:
			if typeof(scheduler.get(key))!=typeof(state[key]):return false
		# No mutation precedes complete original-field and actual-membership checks.
		# Main capture rejected pending callbacks/search objects. Preserve counters,
		# the original category and the actual existing callback's qualification.
		for key: String in fields:scheduler.set(key,state[key])
		scope.physics_processing_enabled=scheduler_state.scope.physics_processing_enabled
		_row=adopted_row
	else:
		if priority!=100:return false
		# Node NOTIFICATION_READY enables its genuine _physics_process override.
		scope.physics_processing_enabled=_publication.birth_template.has_physics_callback
		var index: int=_publication.source_tree_root.normal_append_index
		# root.add_child appends a normal child before internal back children.
		for child: Dictionary in _children:
			if child.index>=index:child.index+=1
		_row={"node_id":handle.get_instance_id(),"parent_id":_publication.source_tree_root.node_id,"index":index,"script_path":_publication.birth_template.script_path,"name":&"HCMonsterPathBudget"}
		_children.append(_row)
	scope.inside_world=true;scope.physics_priority=priority
	_handle=handle;_scheduler=weakref(scheduler);_commits+=1
	_row["source_handle_id"]=handle.get_instance_id();_reserved={}
	return true
func original_source_tree_callback_order(id: int,method: StringName) -> Dictionary:
	if _handle==null or id!=_handle.get_instance_id() or method!=&"original_physics_pump" or _retired:return {"ok":false}
	return {"ok":true,"domain":"H","order":_row.index*2+1,"source_path":[_row.index,1],"entry":"scripts/monster_ai_package/path_scheduler.gd::_physics_process"}
func original_source_tree_root_ordinal(world: Dictionary) -> Dictionary:
	for child: Dictionary in _children:
		if child.node_id==world.get("world_runtime_id") and child.get("script_path")=="res://scripts/game_root.gd":return {"ok":true,"ordinal":child.index,"source_path":[child.index]}
	return {"ok":false,"reason":"actual_original_world_root_membership_not_captured"}
func original_persistent_scope_path(origin: Dictionary) -> Dictionary:
	var captured_path: Array=origin.get("source_path",[])
	if OS.get_thread_caller_id()!=_owner or captured_path.is_empty(): return {"ok":false}
	# Same root membership ledger: a newly born normal scheduler can shift an
	# internal-back root sibling. Rebase by its captured real identity, not rank.
	var id := 0
	for original: Dictionary in _publication.root_children:
		if original.node_id==origin.get("root_child_id") and original.index==captured_path[0]: id = original.node_id; break
	if id <= 0: return {"ok":false}
	for current: Dictionary in _children:
		if current.node_id == id:
			var path: Array = captured_path.duplicate()
			path[0] = current.index
			return {"ok":true,"source_path":path}
	return {"ok":false}
func original_persistent_callback_rows(domain: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	if domain!=&"H" or _scheduler==null or _scheduler.get_ref()==null or _retired or _final:return rows
	var order: Dictionary=original_source_tree_callback_order(_handle.get_instance_id(),&"original_physics_pump")
	if order.get("ok")!=true:return rows
	rows.append({"target":_scheduler,"scope":_scope,"domain":&"H","method":&"original_physics_pump","priority":_scope.physics_priority,"source_order":order.order,"source_path":order.source_path,"registration_order":_commits,"entry":order.entry})
	return rows
func dispatch_original_physics_without_world(name: String,frame: Dictionary) -> bool:
	if _host==null or frame!=_host.current_clock_frame() or frame.get("phase")!=name:return false
	if name!="H_GROUP":return true
	for row: Dictionary in original_persistent_callback_rows(&"H"):
		if row.scope.runtime_object_is_present() and row.scope.is_inside_world() and row.scope.can_process() and row.scope.physics_enabled():row.target.get_ref().call(row.method,float(frame.scaled_delta))
	return true
func admit_actual_original_source_tree_exit(receipt: Dictionary) -> bool:
	# Session close/clock stop is not physical SceneTree-root exit. Actual Main
	# root-exit or full persistent-owner handoff must supply its real receipt.
	if _host==null or receipt.get("source_tree_root_id")!=_publication.source_tree_root.node_id or receipt.get("actual_root_exit")!=true or receipt.get("actual_native_verified")!=true:return false
	if not _host.has_method("verify_original_persistent_tree_exit_receipt") or not _host.verify_original_persistent_tree_exit_receipt(receipt):return false
	_actual_tree_exit=receipt
	return true
func retire_original_source_tree_path_scheduler(handle: Object,scope: RefCounted,scheduler: RefCounted) -> bool:
	if _retired:return is_same(handle,_handle)
	if _actual_tree_exit.is_empty() or not is_same(handle,_handle) or not is_same(scope,_scope) or not is_same(scheduler,_scheduler.get_ref()):return false
	scheduler.retire()
	if not scope.exit_at_original_checkpoint():return false
	_retired=true
	return true
func free_original_source_tree_path_scheduler(handle: Object,scope: RefCounted,scheduler: RefCounted) -> bool:
	if not _retired or _final or not is_same(handle,_handle) or not is_same(scope,_scope) or not is_same(scheduler,_scheduler.get_ref()) or not scope.free_at_original_checkpoint():return false
	_children.erase(_row);_scheduler=null;_scope=null;_handle=null;_final=true
	return true
