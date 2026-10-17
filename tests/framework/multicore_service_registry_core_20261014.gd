extends RefCounted

## Real native S-owner fixture for the service identity/lifecycle protocol.
## Scope/clock inputs are explicit fixture observations, not a production
## WorldCore integration proof; original staged Driver/Scheduler methods run.
const Registry := preload("res://scripts/gameplay/foundation/service_registry.gd")
const ActorRegistry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const WorldContext := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Driver := preload("res://scripts/gameplay/enemy/enemy_owner_polygon_pursuit.gd")
const Scheduler := preload("res://scripts/gameplay/enemy/enemy_owner_path_scheduler.gd")
const JobAccess := preload("res://scripts/gameplay/enemy/enemy_owner_path_job_access.gd")
var _host_ref: WeakRef
var _owner := OS.get_thread_caller_id()
var _registry: RefCounted
var _actor_registry: RefCounted
var _context: RefCounted
var _provider: RefCounted
var _driver: RefCounted
var _scheduler: RefCounted
var _driver_scope: RefCounted
var _scheduler_scope: RefCounted
var _world_token: Object
var _checks: Array[Dictionary] = []
var _done := false
var _closed := false
var _boot: Dictionary

class Scope:
	extends RefCounted
	var state: Dictionary
	var exit_allowed := false
	var free_allowed := false
	func owner_thread_id() -> int: return OS.get_thread_caller_id()

class Provider:
	extends RefCounted
	var faults: Array[Dictionary] = []
	var calls: Array[String] = []
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func fault(code: String, details: Dictionary) -> void: faults.append({"code": code, "details": details})
	func service_scope_view(scope: RefCounted, _id: int, _kind: StringName) -> Dictionary: return scope.state
	func queue_service_retirement(scope: RefCounted, _id: int) -> bool:
		calls.append("queue")
		scope.state.queued_for_retirement = true
		return true
	func service_retirement_allowed(scope: RefCounted, _id: int, _model: RefCounted) -> bool: return scope.exit_allowed
	func service_final_free_allowed(scope: RefCounted, _id: int, _model: RefCounted) -> bool: return scope.free_allowed

class Inputs:
	extends RefCounted
	var budget_calls: Array[Array] = []
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func canonical(_model: Object) -> Object: return null
	func is_present(_model: Object) -> bool: return false
	func capture(_model: Object) -> RefCounted: return null
	func resolve(_link: RefCounted) -> Object: return null
	func mark_progress_pending(category: String, pending: bool, _a := true, _b := false, _scope: RefCounted = null, _physics := true) -> void:
		budget_calls.append([category, pending])
	func get_physics_frames() -> int: return 51
	func get_ticks_usec() -> int: return Time.get_ticks_usec()
	func get_ticks_msec() -> int: return Time.get_ticks_msec()

class SearchState:
	extends RefCounted
	var detached := 0
	func detach_shared_goal_field() -> void: detached += 1

func owner_thread_id() -> int: return _owner
func _check(value: bool, label: String) -> void: _checks.append({"pass": value, "label": label})

func _init(host: Object, boot: Dictionary) -> void:
	_host_ref = weakref(host)
	_boot = boot
	_world_token = Object.new()
	_actor_registry = ActorRegistry.new()
	_check(_actor_registry.configure_world({"contract_id": "hardcore.execution.world_context.v1", "world_runtime_id": _world_token.get_instance_id(), "world_epoch": 1, "runtime_map_id": 7, "profile_id": "service_fixture"}, ""), "existing ActorRegistry world authority configures on S")
	_context = WorldContext.new()
	_check(_context.configure_domain(_actor_registry), "existing WorldContext delegates same S registry")
	_provider = Provider.new()
	_registry = Registry.new()
	_check(_registry.configure_owner(_context, _provider, _provider), "service registry binds original domain context and explicit source scope")
	_driver_scope = Scope.new()
	_driver_scope.state = boot.driver_scope.duplicate(true)
	_scheduler_scope = Scope.new()
	_scheduler_scope.state = boot.scheduler_scope.duplicate(true)
	var driver_handle: Object = _registry.allocate_service(&"polygon_pursuit_driver", _driver_scope)
	var scheduler_handle: Object = _registry.allocate_service(&"path_scheduler", _scheduler_scope)
	_check(driver_handle != null and scheduler_handle != null and not driver_handle is RefCounted and not scheduler_handle is RefCounted, "distinct non-RefCounted service Object handles")
	if driver_handle == null or scheduler_handle == null:
		_done = true
		return
	_check(driver_handle.get_instance_id() > 0 and scheduler_handle.get_instance_id() > 0 and driver_handle.get_instance_id() != scheduler_handle.get_instance_id(), "positive full ObjectIDs do not alias each other")
	_check(_actor_registry.resolve_runtime_actor(driver_handle.get_instance_id()) == null, "service identity never enters ActorRegistry")
	var inputs := Inputs.new()
	var access := JobAccess.new()
	_check(access.configure_owner(inputs, _registry), "actual path job access binds canonical service registry")
	_scheduler = Scheduler.new()
	_check(_registry.bind_service_model(scheduler_handle, _scheduler), "scheduler model is bound after identity birth")
	var process_scope: RefCounted = _registry.process_scope_for_service(scheduler_handle.get_instance_id())
	_check(_scheduler.configure_owner({"Terrain": inputs, "FrameBudget": inputs, "Engine": inputs, "Time": inputs}, access, scheduler_handle, process_scope), "actual scheduler binds priority100 service and process scope")
	_check(_registry.validate_priority100_scheduler(scheduler_handle.get_instance_id()), "original priority100 assignment is validated after service birth")
	_driver = Driver.new()
	_check(_registry.bind_service_model(driver_handle, _driver), "driver model is bound after identity birth")
	_check(_driver.configure_owner({"Runtime": inputs, "Search": inputs, "Scheduler": _scheduler, "Time": inputs}, inputs, driver_handle, _registry), "actual driver uses independent canonical service identity")
	_check(access.register_driver(driver_handle, _driver), "driver registered before first scheduler submission")
	var driver_id: int = driver_handle.get_instance_id()
	var scheduler_id: int = scheduler_handle.get_instance_id()
	_check(_registry.resolve_service(driver_id) == driver_handle and access.runtime_id(_driver) == driver_id, "job key is service ObjectID rather than RefCounted model ID")
	var qualification: Dictionary = _registry.service_qualification(driver_id)
	_check(qualification.present and not qualification.queued_for_retirement, "streaming qualification observes source present and queued independently")
	_check(driver_id != _driver.get_instance_id(), "RefCounted driver ID is distinct and not selected")
	_driver.token = boot.driver_reset_before.token
	_driver.pending = boot.driver_reset_before.pending
	_driver.route = boot.driver_reset_before.route
	_driver.route_index = boot.driver_reset_before.route_index
	_driver.retry_msec = boot.driver_reset_before.retry_msec
	_driver.scheduler = _scheduler
	var accepted := SearchState.new()
	_scheduler.submit(_driver, _driver.token, accepted)
	_check(_scheduler.jobs.has(driver_id), "original submit accepts and retains original job before queue-retirement")
	_check(_registry.queue_service_retirement(driver_id), "queued boundary delegates actual source scope")
	_check(driver_handle.is_inside_world() and driver_handle.is_queued_for_retirement() and _scheduler.jobs.has(driver_id), "queued and inside remain independent; accepted task retained before exit")
	qualification = _registry.service_qualification(driver_id)
	_check(qualification.present and qualification.queued_for_retirement, "streaming queued observation remains present before original exit")
	_driver_scope.state.can_process = false
	_driver_scope.state.physics_processing_enabled = true
	_driver_scope.state.ordinary_p_enabled = true
	_driver_scope.state.raw_h_enabled = false
	_check(not driver_handle.can_process() and driver_handle.physics_enabled() and driver_handle.ordinary_p_enabled() and not driver_handle.raw_h_enabled(), "canProcess/P/H/raw flag independence")
	_driver.retire()
	_check(_driver.token == boot.driver_reset_after.token and _driver.pending == boot.driver_reset_after.pending and _driver.route == boot.driver_reset_after.route and _driver.route_index == boot.driver_reset_after.route_index and _driver.retry_msec == boot.driver_reset_after.retry_msec, "actual Driver.retire matches captured original _exit_tree/reset values")
	_check(not _scheduler.jobs.has(driver_id) and accepted.detached == 1, "original cancellation detaches accepted search exactly once")
	access.unregister_driver(driver_handle, _driver)
	_driver_scope.exit_allowed = true
	_driver_scope.state.inside_world = false
	_check(_registry.begin_service_retirement(driver_id), "driver reset/cancel/unregister precedes handle retirement")
	_check(_registry.resolve_service(driver_id) == null, "retiring service cannot resolve for new jobs")
	_driver_scope.free_allowed = true
	_check(_registry.final_free_service(driver_id), "manual driver Object final-free at allowed source position")
	_check(not is_instance_valid(driver_handle), "canonical driver ObjectID is invalid after final-free")
	_check(not _registry.service_qualification(driver_id).present, "final-free service returns canonical absence even if model is retained")
	var retained_task := SearchState.new()
	_scheduler.jobs[123] = {"token": 1, "search": retained_task}
	_scheduler.queue.append(123)
	_scheduler.retire()
	_check(inputs.budget_calls.back() == ["path:%d" % scheduler_id, false], "actual Scheduler.retire unbinds original budget category")
	_check(_scheduler.jobs.has(123) and _scheduler.queue == [123] and retained_task.detached == 0, "scheduler exit does not invent cancellation/flush of accepted tasks")
	_scheduler_scope.exit_allowed = true
	_scheduler_scope.state.inside_world = false
	_check(_registry.begin_service_retirement(scheduler_id) and _scheduler.jobs.has(123), "accepted scheduler task remains until source final-free")
	_check(not scheduler_handle.is_queued_for_retirement(), "direct destructive retirement does not invent queued-for-deletion state")
	_scheduler_scope.free_allowed = true
	_check(_registry.final_free_service(scheduler_id), "scheduler final-free uses explicit source permission without prolonging life")
	_check(not process_scope.runtime_object_is_present(), "retained Rc process view reports original Object lifetime ended")
	var before := inputs.budget_calls.size()
	_driver.reset()
	_check(inputs.budget_calls.size() == before, "original is_instance_valid scheduler branch skips dead canonical scheduler despite Rc reference")
	_check(_registry.remaining_service_count() == 0 and _registry.close_at_original_boundary(), "all manually owned service Objects retire without a bulk fallback")
	_closed = true
	_done = true

func on_phase(name: String, _frame: Dictionary) -> bool:
	if name == "PUBLISH":
		var host: Object = _host_ref.get_ref()
		return host.publish_snapshot({"done": _done, "owner": _owner, "checks": _checks}, [])
	return OS.get_thread_caller_id() == _owner

func on_inputs(_domain: String, _packets: Array) -> bool:
	return OS.get_thread_caller_id() == _owner

func close_session() -> bool:
	# Registry already closed at exact tested boundaries. Drop implementation
	# references only now; they did not control canonical lifetime above.
	if _driver != null: _driver.scheduler = null
	_driver = null
	_scheduler = null
	_registry = null
	_context = null
	_actor_registry = null
	_driver_scope = null
	_scheduler_scope = null
	_provider = null
	if is_instance_valid(_world_token): _world_token.free()
	_world_token = null
	return _closed and OS.get_thread_caller_id() == _owner
