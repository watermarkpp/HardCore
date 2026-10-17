extends RefCounted

## One original SceneTree-root PathScheduler, shared searches/maps and callback
## lifetime. The actual source-tree ledger owns lookup/birth/exit qualification.
const Factory := preload("res://scripts/gameplay/enemy/enemy_owner_path_factory.gd")
const Scheduler := preload("res://scripts/gameplay/enemy/enemy_owner_path_scheduler.gd")
const Jobs := preload("res://scripts/gameplay/world/source_session_path_jobs.gd")
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _tree: RefCounted
var _bindings: Dictionary
var _configured := false
var _scheduler: RefCounted
var _scope: RefCounted
var _handle: Object
var search: RefCounted
var jobs: RefCounted

class SourceHandle:
	extends Object
	var _owner := OS.get_thread_caller_id()
	var _slot: WeakRef
	func owner_thread_id() -> int: return _owner
	func kind() -> StringName: return &"path_scheduler"

func owner_thread_id() -> int: return _owner
func configure_session(session: RefCounted, bindings: Dictionary, actual_tree_port: RefCounted) -> bool:
	if _configured or _owner == OS.get_main_thread_id() or session.owner_thread_id() != _owner or actual_tree_port.owner_thread_id() != _owner: return false
	for method: String in ["lookup_original_source_tree_path_scheduler", "birth_original_source_tree_path_scheduler", "commit_original_source_tree_path_scheduler", "retire_original_source_tree_path_scheduler", "free_original_source_tree_path_scheduler"]:
		if not actual_tree_port.has_method(method): return false
	for key: String in ["Terrain", "HCM30ContextTokenScript", "HCPPolyRuntime", "FrameBudget", "Engine", "Time"]:
		if not bindings.get(key) is RefCounted or bindings[key].owner_thread_id() != _owner: return false
	# These dependencies must themselves be the persistent Session instances.
	# Supplying the first world's weak-Core ports is rejected by Root admission.
	if not actual_tree_port.has_method("validate_original_session_path_bindings") or not actual_tree_port.validate_original_session_path_bindings(bindings): return false
	_session = weakref(session)
	_tree = actual_tree_port
	_bindings = bindings
	search = Factory.new()
	if not search.configure_owner({"Terrain": bindings.Terrain, "HCM30ContextTokenScript": bindings.HCM30ContextTokenScript, "Time": bindings.Time}): return false
	jobs = Jobs.new()
	if not _tree.adopt_original_shared_search_state(search.shared): return false
	_configured = true
	return true
func bind_world(world: RefCounted, original_world_job_access: RefCounted) -> bool:
	return _configured and jobs.bind_world(world, original_world_job_access)
func release_world(world: RefCounted) -> bool: return _configured and jobs.release_world(world)
func scheduler() -> RefCounted:
	if not _configured or OS.get_thread_caller_id() != _owner: return null
	# Original for_tree checks for an existing source tree child at each first
	# lookup. This lookup is S ledger state, never a fake parent0 world child.
	var found: Dictionary = _tree.lookup_original_source_tree_path_scheduler()
	if found.get("ok") != true: return null
	if _scheduler != null:
		return _scheduler if found.get("found") == true and found.get("handle") == _handle else null
	if found.get("found") == true and found.get("owner_domain") != &"prepared_Main":
		_session.get_ref().fault("existing_source_path_scheduler_handoff_missing", {})
		return null
	var born: Dictionary = _tree.birth_original_source_tree_path_scheduler()
	if born.get("ok") != true or not born.get("scope") is RefCounted or not born.get("source_tree_runtime_id") is int or born.source_tree_runtime_id <= 0: return null
	_scope = born.scope
	if _scope.owner_thread_id() != _owner or _scope.parent_scope_id != born.source_tree_runtime_id or _scope.inside_world: return null
	_handle = SourceHandle.new()
	_handle._slot = weakref(self)
	_scheduler = Scheduler.new()
	# Exact original statements: new(), name, priority100, root.add_child().
	if born.get("adoption") != true: _scope.physics_priority = 100
	if not _bindings.FrameBudget.actors.register_process_owner(_scope): return null
	if not _scheduler.configure_owner(_bindings, jobs, _handle, _scope): return null
	if not _tree.commit_original_source_tree_path_scheduler(_handle, _scope, _scheduler, &"original_physics_pump", _scope.physics_priority): return null
	return _scheduler
func retire_at_original_source_tree_exit() -> bool:
	if _scheduler == null: return true
	return _tree.retire_original_source_tree_path_scheduler(_handle, _scope, _scheduler)
func free_at_original_source_tree_checkpoint() -> bool:
	if _scheduler == null: return true
	if not _tree.free_original_source_tree_path_scheduler(_handle, _scope, _scheduler): return false
	_scheduler = null
	_handle.free()
	_handle = null
	_scope = null
	return true

func scheduler_present() -> bool: return _scheduler != null
func original_context_token() -> RefCounted: return _bindings.HCM30ContextTokenScript
func original_service_handle_id() -> int: return _handle.get_instance_id() if _handle != null else 0
