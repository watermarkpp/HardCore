extends RefCounted

const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
const SearchFactory := preload("res://scripts/gameplay/enemy/enemy_owner_path_factory.gd")
const JobAccess := preload("res://scripts/gameplay/enemy/enemy_owner_path_job_access.gd")
const Scheduler := preload("res://scripts/gameplay/enemy/enemy_owner_path_scheduler.gd")
const Driver := preload("res://scripts/gameplay/enemy/enemy_owner_polygon_pursuit.gd")
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _registry: RefCounted
var _actors: RefCounted
var _budget_actors: RefCounted
var _bindings: Dictionary
var _scheduler: RefCounted
var _session_slot: RefCounted
var _scheduler_id := 0
var _models: Dictionary = {}
var _scopes: Dictionary = {}
var search: RefCounted
var jobs: RefCounted
func owner_thread_id() -> int: return _owner

func configure_owner(world: RefCounted, registry: RefCounted, actors: RefCounted, budget_actors: RefCounted, bindings: Dictionary, session_slot: RefCounted) -> bool:
	if _world != null or OS.get_thread_caller_id() != _owner: return false
	_world = weakref(world)
	_registry = registry
	_actors = actors
	_budget_actors = budget_actors
	_bindings = bindings
	if session_slot == null or session_slot.owner_thread_id() != _owner: return false
	_session_slot = session_slot
	search = session_slot.search
	jobs = JobAccess.new()
	if not jobs.configure_owner(actors, registry): return false
	return session_slot.bind_world(world, jobs)

func scheduler() -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner)
	if _scheduler != null: return _scheduler
	_scheduler = _session_slot.scheduler()
	return _scheduler

func create_search() -> RefCounted: return search.create_search()

func create_polygon_pursuit(actor_view: Object) -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner)
	var handle_actor: Object = _actors.canonical(actor_view)
	var scope: RefCounted = _world.get_ref().new_original_service_scope(&"polygon_pursuit_driver", handle_actor.get_instance_id())
	if scope == null: return null
	var handle: Object = _registry.allocate_service(&"polygon_pursuit_driver", scope)
	if handle == null: return null
	var driver := Driver.new()
	var id := handle.get_instance_id()
	_models[id] = driver
	_scopes[id] = scope
	if not _registry.bind_service_model(handle, driver): return null
	var shared_scheduler := scheduler()
	if shared_scheduler == null: return null
	if not driver.configure_owner({"Runtime": _bindings.HCPPolyRuntime, "Search": search, "Scheduler": shared_scheduler, "Time": _bindings.Time}, _actors, handle, _registry): return null
	if not jobs.register_driver(handle, driver): return null
	if not _world.get_ref().enter_original_service_scope(id, scope, driver, &"", &""): return null
	driver.setup(actor_view)
	return driver

func retire_at_original_exit(id: int) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if not _models.has(id): return false
	var handle: Object = _registry.resolve_service(id)
	var model: RefCounted = _models[id]
	model.retire()
	if id != _scheduler_id: jobs.unregister_driver(handle, model)
	if not _scopes[id].exit_at_original_checkpoint(): return false
	return _registry.begin_service_retirement(id)

func free_at_original_checkpoint(id: int) -> bool:
	if not _scopes.has(id) or not _scopes[id].free_at_original_checkpoint(): return false
	if not _registry.final_free_service(id): return false
	_world.get_ref().forget_original_service_scope(id)
	_scopes.erase(id)
	_models.erase(id)
	if id == _scheduler_id:
		_scheduler_id = 0
		_scheduler = null
	return true
