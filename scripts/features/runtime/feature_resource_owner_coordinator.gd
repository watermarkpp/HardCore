extends RefCounted

var Budget: RefCounted
var _primitives: RefCounted
var _thread := OS.get_thread_caller_id()
var _process_scope: RefCounted
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const MainReference := preload("res://scripts/features/runtime/feature_resource_reference.gd")
const CATEGORY := "feature_resources"

class Request extends RefCounted:
	signal completed(result: Dictionary)
	var plan: Dictionary
	var kind := "module"
	var scene_epoch := 0
	var code_plan: RefCounted
	var scope: RefCounted
	var consumer: WeakRef
	var publisher: WeakRef
	var input_lease: RefCounted
	var export_verifier: RefCounted
	var image_file: RefCounted
	var image_hash: HashingContext
	var image_sha256 := ""
	var generation := -1
	var entry_id := ""
	var cursor := 0
	var remaining: Dictionary = {}
	var resources: Dictionary = {}
	var live_state: Dictionary = {}
	var diagnostics := {"requested":0, "cache_hits":0, "threaded_completed":0, "joined_requests":0}

var _next_request := 0
var _requests: Dictionary = {}
var _jobs: Dictionary = {}
var _work: Dictionary = {}
var _head := 0
var _tail := 0
var _retirements: Dictionary = {}
var _retire_head := 0
var _retire_tail := 0
var _threaded_claim_diagnostics := {
	"accepted": 0, "transferred": 0, "get": 0, "missing": 0, "pending": 0
}
var _applications: Dictionary = {}
var _apply_head := 0
var _apply_tail := 0
var _request_calls := 0
var _get_calls := 0
var _next_queue := 0
var _applying_request := 0
var _quantum_active := false
var _deferred_completions: Array = []
var _completion_retirement_ids: Array = [] # Synchronous attribution only; never held across a leaf wait.
var _original_idle_handoff_applied := false

func configure_original_idle_handoff(publication: Dictionary) -> bool:
	# This restores only a newly constructed S coordinator before owner binding.
	# Accepted old work must have settled on Main; no queue is cleared here.
	if OS.get_thread_caller_id() != _thread or _thread == OS.get_main_thread_id() or _original_idle_handoff_applied or _primitives != null or _process_scope != null: return false
	if not _requests.is_empty() or not _jobs.is_empty() or not _work.is_empty() or not _retirements.is_empty() or not _applications.is_empty() or not _deferred_completions.is_empty() or _quantum_active or _applying_request != 0 or _code_world_handoff_id != 0: return false
	if publication.size() != 2 or publication.get("contract_id") != "hardcore.feature.coordinator.idle_handoff.v1" or not publication.get("fields") is Dictionary: return false
	var required: Array[String] = ["_next_request","_head","_tail","_retire_head","_retire_tail","_apply_head","_apply_tail","_request_calls","_get_calls","_next_queue","_threaded_claim_diagnostics","_code_phase_metrics"]
	if publication.fields.size() != required.size(): return false
	for field: String in required:
		if not publication.fields.has(field): return false
		if field in ["_threaded_claim_diagnostics","_code_phase_metrics"]:
			if not publication.fields[field] is Dictionary: return false
		elif not publication.fields[field] is int or publication.fields[field] < 0: return false
	if publication.fields._head != publication.fields._tail or publication.fields._retire_head != publication.fields._retire_tail or publication.fields._apply_head != publication.fields._apply_tail: return false
	var restored: Dictionary = preload("res://scripts/gameplay/world/world_runtime_working_graph.gd").restore_runtime_roots(publication.fields)
	if restored.get("ok") != true: return false
	# Complete validation and runtime-container restoration precede all mutation.
	for field: String in required: set(field,restored.value[field])
	_original_idle_handoff_applied = true
	return true


func configure_owner(primitives: RefCounted, shared_budget: RefCounted, process_scope: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _thread or primitives == null or shared_budget == null: return false
	if primitives.owner_thread_id() != _thread or shared_budget.owner_thread_id() != _thread: return false
	_primitives = primitives
	Budget = shared_budget
	_process_scope = process_scope
	_primitives.bind_coordinator(self)
	_ready()
	return not primitives.failed()

func _set_process(enabled: bool) -> void:
	assert(OS.get_thread_caller_id() == _thread)
	if not _process_scope.set_process_processing_enabled(enabled):
		_primitives._fault("feature_resource_process_scope_write",{"enabled":enabled})
		return

func processing_enabled() -> bool:
	return _process_scope.process_enabled()
func owner_thread_id() -> int:
	return _thread
func is_inside_world() -> bool:
	return _process_scope.is_inside_world()
func is_queued_for_retirement() -> bool:
	return _process_scope.is_queued_for_retirement()
func process_enabled() -> bool:
	return _process_scope.process_enabled()
func physics_enabled() -> bool:
	return false

func is_processing() -> bool:
	return _process_scope.process_enabled()

func is_inside_tree() -> bool:
	return bool(_process_scope.is_inside_world())

func can_process() -> bool:
	return bool(_process_scope.can_process())

func is_physics_processing() -> bool:
	return false # Original Node has no _physics_process callback.

func _object_is_valid(value: Variant) -> bool:
	return _primitives.object_is_valid(value)

func _object_same(a: Variant, b: Variant) -> bool:
	return _primitives.object_same(a,b,self)

func _ready() -> void:
	_set_process(false)

func prepare(catalog: Dictionary, enabled: Array) -> Dictionary:
	if actual_original_live_feature_bound(): return await _await_actual_live_admission(admit_actual_original_main_command("prepare",[catalog,enabled],_actual_live_call_context()))
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var plan := Lease.requirements(catalog, enabled)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not plan.success: return {"success":false, "errors":plan.errors, "lease":null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var declared := Registry.declarations()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not declared.success: return {"success":false, "errors":declared.errors, "lease":null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	for path: String in plan.paths:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		if not declared.records.has(path): return {"success":false, "errors":["feature_resource_undeclared:" + path], "lease":null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if plan.paths.is_empty(): return {"success":true, "errors":[], "lease":null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_next_request += 1
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var id := _next_request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var request := Request.new()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.plan = plan
	# Scene-change immediate failure (S3): the request belongs to the scene
	# that started it; a later scene invalidates it before any promotion.
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var owner_scene: RefCounted = _primitives.tree().current_scene
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.scene_epoch = int(owner_scene.descriptor.object_id) if owner_scene != null else 0
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_requests[id] = request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	for path: String in plan.paths:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		request.remaining[path] = true
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		if not _jobs.has(path):
			if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
			_jobs[path] = {"started":false, "clients":{}, "delivering":false,
				"resource":null, "failure":"", "mode":"", "joined":false, "retained":false, "type":declared.records[path].type}
			if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
			_queue(path)
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		_jobs[path].clients[id] = true
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_activate()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return await request.completed

func cancel_all() -> void:
	if _primitives.failed(): return
	if actual_original_live_feature_bound():
		cancel_original_live_module_requests();return
	_retire_code_world_handoff()
	# Engine threaded requests cannot be cancelled. Their jobs remain owned
	# until status is terminal and any loaded resource is acquired and retired.
	if _primitives.failed(): return
	for id: int in _requests.keys():
		if _primitives.failed(): return
		if id == _applying_request: continue
		if _primitives.failed(): return
		var result := {"success":false, "errors":["feature_resource_preparation_cancelled"], "lease":null}
		if _primitives.failed(): return
		if _quantum_active: _deferred_completions.append({"id":id,"result":result})
		else: _complete(id,result)
	if _primitives.failed(): return
	_activate()

func is_applying() -> bool:
	if _primitives.failed(): return false
	return _applying_request != 0

func apply_ready(callback: Callable) -> bool:
	if _primitives.failed(): return false
	if not callback.is_valid(): return false
	if _primitives.failed(): return false
	_next_request += 1
	if _primitives.failed(): return false
	var id := _next_request
	if _primitives.failed(): return false
	var request := Request.new()
	if _primitives.failed(): return false
	_requests[id] = request
	if _primitives.failed(): return false
	_applications[_apply_tail] = {"id":id, "callback":callback}
	if _primitives.failed(): return false
	_apply_tail += 1
	if _primitives.failed(): return false
	_activate()
	if _primitives.failed(): return false
	var result: Dictionary = await request.completed
	if _primitives.failed(): return false
	return bool(result.success)

func retire_resources(resources: Dictionary) -> void:
	if _primitives.failed(): return
	if resources.is_empty(): return
	if _primitives.failed(): return
	_retirements[_retire_tail] = resources.duplicate(false)
	if not _completion_retirement_ids.is_empty(): _retirements[_retire_tail]["__actual_completion_ids__"]=_completion_retirement_ids.duplicate()
	if _primitives.failed(): return
	_retire_tail += 1
	if _primitives.failed(): return
	_activate()

## Adopt already-issued ResourceLoader user claims after their scene owner exits.
## This deliberately never calls load_threaded_request: the caller has already
## paid for the engine claim and this service only polls and later joins it.
func retire_threaded_resource_claims(path: String, claim_count: int) -> bool:
	if _primitives.failed(): return false
	if path.is_empty() or claim_count <= 0:
		if _primitives.failed(): return false
		return false
	if _primitives.failed(): return false
	if not _primitives.adopt_threaded_claims(path,claim_count): return false
	if _primitives.failed(): return false
	_threaded_claim_diagnostics.accepted += claim_count
	if _primitives.failed(): return false
	_threaded_claim_diagnostics.transferred += claim_count
	if _primitives.failed(): return false
	_retirements[_retire_tail] = {
		"__threaded_claim__": true, "path": path, "remaining": claim_count
	}
	if _primitives.failed(): return false
	_retire_tail += 1
	if _primitives.failed(): return false
	_activate()
	if _primitives.failed(): return false
	return true

func threaded_claim_diagnostics() -> Dictionary:
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var result := _threaded_claim_diagnostics.duplicate(true)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var pending := 0
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	for index in _retirements:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		var entry: Dictionary = _retirements[index]
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		if bool(entry.get("__threaded_claim__", false)):
			if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
			pending += int(entry.get("remaining", 0))
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	result.pending = pending
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return result

func _activate() -> void:
	if _primitives.failed(): return
	var pending := not _jobs.is_empty() or not _retirements.is_empty() or not _applications.is_empty() or not _issued_source_records.is_empty()
	if _primitives.failed(): return
	_set_process(pending)
	if _primitives.failed(): return
	Budget.mark_pending(CATEGORY, pending, true, false, _process_scope)

func _queue(path: String) -> void:
	if _primitives.failed(): return
	_work[_tail] = path
	if _primitives.failed(): return
	_tail += 1

func original_process(_delta: float) -> void:
	if _primitives.failed(): return
	if actual_original_live_feature_bound():
		if _live_service_active: return # Same head cannot reenter during completion notification.
		_live_service_active=true
		_original_live_feature_process()
		_live_service_active=false;return
	Budget.mark_pending(CATEGORY, true, true, false, _process_scope)
	if _primitives.failed(): return
	var token: Variant = Budget.begin(CATEGORY)
	if _primitives.failed(): return
	if token == 0: return
	if _primitives.failed(): return
	_quantum_active = true
	if _primitives.failed(): return
	var code_phase := ""
	if _primitives.failed(): return
	var code_began := Time.get_ticks_usec()
	if _primitives.failed(): return
	var finished: Array = []
	# Scene-change immediate failure: the first service quantum that observes a
	# different current scene fails every outstanding module preparation right
	# away. Code-publication/handoff requests keep their own cross-scene
	# retention contract and are deliberately untouched here.
	if _primitives.failed(): return
	var successor: RefCounted = _primitives.tree().current_scene
	if _primitives.failed(): return
	var scene_epoch := int(successor.descriptor.object_id) if successor != null else 0
	if _primitives.failed(): return
	for stale_id: int in _requests.keys():
		if _primitives.failed(): return
		var stale_request: Request = _requests[stale_id]
		if _primitives.failed(): return
		if stale_request.kind != "module" or stale_id == _applying_request: continue
		if _primitives.failed(): return
		if stale_request.scene_epoch != 0 and scene_epoch != stale_request.scene_epoch:
			if _primitives.failed(): return
			_deferred_completions.append({"id":stale_id, "result":{"success":false,
				"errors":["feature_resource_scene_changed"], "lease":null}})
	# Each nonempty class receives one opportunity in at most three granted
	# service quanta. Continuous loading cannot starve promotion or retirement.
	if _primitives.failed(): return
	var queue := -1
	if _primitives.failed(): return
	for offset in range(3):
		if _primitives.failed(): return
		var candidate := (_next_queue + offset) % 3
		if _primitives.failed(): return
		if (candidate == 0 and _head < _tail) or (candidate == 1 and _apply_head < _apply_tail) or (candidate == 2 and _retire_head < _retire_tail):
			if _primitives.failed(): return
			queue = candidate
			if _primitives.failed(): return
			_next_queue = (candidate + 1) % 3
			if _primitives.failed(): return
			break
	if _primitives.failed(): return
	if queue == 0:
		if _primitives.failed(): return
		var path: String = _work[_head]
		if _primitives.failed(): return
		_work.erase(_head)
		if _primitives.failed(): return
		_head += 1
		if _primitives.failed(): return
		if _jobs.has(path) and _jobs[path].get("kind") == "code_target":
			if _primitives.failed(): return
			code_phase = "code_target"
		if _primitives.failed(): return
		_step(path, finished)
	elif queue == 1:
		if _primitives.failed(): return
		var application: Dictionary = _applications[_apply_head]
		if _primitives.failed(): return
		_applications.erase(_apply_head)
		if _primitives.failed(): return
		_apply_head += 1
		if _primitives.failed(): return
		if application.get("kind") == "code_publication":
			if _primitives.failed(): return
			code_phase = "code_publication"
			if _primitives.failed(): return
			_step_code_publication(application.id, finished)
		elif application.get("kind") == "code_retention_handoff":
			if _primitives.failed(): return
			code_phase = "code_retention_handoff"
			if _primitives.failed(): return
			_step_code_world_handoff(application.id)
		elif application.get("kind") == "code_inputs":
			if _primitives.failed(): return
			code_phase = "code_inputs"
			if _primitives.failed(): return
			_step_code_inputs(application.id, finished)
		elif _requests.has(application.id):
			if _primitives.failed(): return
			_applying_request = application.id
			if _primitives.failed(): return
			var success: bool = application.callback.call() if application.callback.is_valid() else false
			if _primitives.failed(): return
			_applying_request = 0
			if _primitives.failed(): return
			finished.append({"id":application.id, "result":{"success":success, "errors":[], "lease":null}})
	elif queue == 2:
		if _primitives.failed(): return
		var retirement: Dictionary = _retirements[_retire_head]
		if _primitives.failed(): return
		if bool(retirement.get("__threaded_claim__", false)):
			if _primitives.failed(): return
			if _begin_original_issued_claim_retirement(retirement):
				_step_threaded_claim_retirement(retirement)
				_end_original_issued_claim_retirement(retirement)
		else:
			if _primitives.failed(): return
			if not retirement.is_empty(): retirement.erase(retirement.keys()[0])
			if _primitives.failed(): return
			if retirement.is_empty():
				if _primitives.failed(): return
				_retirements.erase(_retire_head)
				if _primitives.failed(): return
				_retire_head += 1
	if _primitives.failed(): return
	_record_code_quantum(code_phase, Time.get_ticks_usec() - code_began)
	if _primitives.failed(): return
	Budget.end(token)
	if _primitives.failed(): return
	_quantum_active = false
	# Completion may publish config and notify observers, always after the
	# optional preparation scope closes and never across an await.
	if _primitives.failed(): return
	var cancelled := _deferred_completions
	if _primitives.failed(): return
	_deferred_completions = []
	# Resolve every terminal owner before notifying any waiter. A cancelled
	# waiter's synchronous continuation can cancel again, but cannot relabel
	# another result which already crossed its commit/readiness boundary.
	if _primitives.failed(): return
	var deliveries: Array = []
	if _primitives.failed(): return
	for item: Dictionary in cancelled + finished:
		if _primitives.failed(): return
		var delivery := _take_completion(item.id,item.result)
		if _primitives.failed(): return
		if not delivery.is_empty(): deliveries.append(delivery)
	if _primitives.failed(): return
	for delivery: Dictionary in deliveries: delivery.request.completed.emit(delivery.result)
	if _primitives.failed(): return
	_activate()

func _step(path: String, finished: Array) -> void:
	if _primitives.failed(): return
	if not _jobs.has(path): return
	if _primitives.failed(): return
	var job: Dictionary = _jobs[path]
	if _primitives.failed(): return
	if job.get("kind") == "code_target":
		if _primitives.failed(): return
		_step_code_target(path, job, finished)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if bool(job.delivering):
		if _primitives.failed(): return
		_deliver_one(path, job, finished)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var resource: RefCounted = null
	if _primitives.failed(): return
	var mode := ""
	if _primitives.failed(): return
	var failure := ""
	if _primitives.failed(): return
	if not bool(job.started):
		if _primitives.failed(): return
		var first_client := -1
		if _primitives.failed(): return
		for id: int in job.clients:
			if _primitives.failed(): return
			first_client = id
			if _primitives.failed(): return
			break
		if _primitives.failed(): return
		if first_client < 0:
			if _primitives.failed(): return
			_jobs.erase(path)
			if _primitives.failed(): return
			return
		if _primitives.failed(): return
		if not _requests.has(first_client):
			if _primitives.failed(): return
			job.clients.erase(first_client)
			if _primitives.failed(): return
			_queue(path)
			if _primitives.failed(): return
			return
		if _primitives.failed(): return
		resource = _primitives.get_cached_ref(path)
		if _primitives.failed(): return
		if resource != null:
			if _primitives.failed(): return
			mode = "cache_hits"
		elif not _primitives.exists(path, job.type):
			if _primitives.failed(): return
			failure = "feature_resource_missing:" + path
		else:
			if _primitives.failed(): return
			var status: Variant = _primitives.load_threaded_get_status(path)
			# A matching engine task still requires this owner's own user token.
			# Merely observing another owner's status and calling get would spend
			# its retrieval right. ResourceLoader joins the existing task itself.
			if _primitives.failed(): return
			var error: Variant = _primitives.load_threaded_request(path, job.type, false)
			if _primitives.failed(): return
			_request_calls += 1
			if _primitives.failed(): return
			if error != OK: failure = "feature_resource_request_failed:" + path
			else:
				if _primitives.failed(): return
				job.joined = status != _primitives.THREAD_LOAD_INVALID_RESOURCE
			if _primitives.failed(): return
			job.started = true
			if _primitives.failed(): return
			if failure.is_empty():
				if _primitives.failed(): return
				_queue(path)
				if _primitives.failed(): return
				return # Request and completed retrieval are separate quanta.
	if _primitives.failed(): return
	if failure.is_empty() and resource == null:
		if _primitives.failed(): return
		var status: Variant = _primitives.load_threaded_get_status(path)
		if _primitives.failed(): return
		if status == _primitives.THREAD_LOAD_LOADED:
			if _primitives.failed(): return
			resource = _primitives.load_threaded_get(path)
			if _primitives.failed(): return
			_get_calls += 1
			if _primitives.failed(): return
			mode = "threaded_completed"
		elif status == _primitives.THREAD_LOAD_FAILED:
			# FAILED is terminal too; get cannot wait and releases our user token.
			if _primitives.failed(): return
			_primitives.load_threaded_get(path)
			if _primitives.failed(): return
			_get_calls += 1
			if _primitives.failed(): return
			failure = "feature_resource_load_failed:" + path
		elif status == _primitives.THREAD_LOAD_INVALID_RESOURCE:
			if _primitives.failed(): return
			failure = "feature_resource_load_failed:" + path
		else:
			if _primitives.failed(): return
			_queue(path)
			if _primitives.failed(): return
			return
	if _primitives.failed(): return
	if failure.is_empty() and not _primitives.valid_resource(path, resource):
		if _primitives.failed(): return
		failure = "feature_resource_type_or_shape:" + path
	if _primitives.failed(): return
	job.resource = resource
	if _primitives.failed(): return
	job.failure = failure
	if _primitives.failed(): return
	job.mode = mode
	if _primitives.failed(): return
	job.delivering = true
	if _primitives.failed(): return
	_queue(path)

func _deliver_one(path: String, job: Dictionary, finished: Array) -> void:
	# The engine task is shared; its participants still receive independent
	# validation/leases in separate ordinary quanta rather than one frame burst.
	if _primitives.failed(): return
	var next_id := -1
	if _primitives.failed(): return
	for id: int in job.clients:
		if _primitives.failed(): return
		next_id = id
		if _primitives.failed(): return
		break
	if _primitives.failed(): return
	if next_id >= 0:
		if _primitives.failed(): return
		job.clients.erase(next_id)
		if _primitives.failed(): return
		if _requests.has(next_id):
			if _primitives.failed(): return
			var request: Request = _requests[next_id]
			if _primitives.failed(): return
			if not String(job.failure).is_empty():
				if _primitives.failed(): return
				finished.append({"id":next_id, "result":{"success":false, "errors":[job.failure], "lease":null}})
			else:
				if _primitives.failed(): return
				request.resources[path] = job.resource
				if _primitives.failed(): return
				request.remaining.erase(path)
				if _primitives.failed(): return
				request.diagnostics[job.mode] += 1
				if _primitives.failed(): return
				request.diagnostics.requested += 1 if job.started else 0
				if _primitives.failed(): return
				request.diagnostics.joined_requests += 1 if job.joined else 0
				if _primitives.failed(): return
				job.retained = true
				if _primitives.failed(): return
				if request.remaining.is_empty():
					if _primitives.failed(): return
					var lease: Variant = _primitives.issue_resource_lease(request.plan, request.resources, self, request.diagnostics)
					if _primitives.failed(): return
					finished.append({"id":next_id, "result":{"success":lease != null, "errors":[] if lease != null else ["feature_resource_lease_invalid"], "lease":lease}})
	if _primitives.failed(): return
	if job.clients.is_empty():
		if _primitives.failed(): return
		_jobs.erase(path)
		if _primitives.failed(): return
		if job.resource != null and not bool(job.retained): retire_resources({path:job.resource})
	else:
		if _primitives.failed(): return
		_queue(path)

func _take_completion(id: int, result: Dictionary) -> Dictionary:
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not _requests.has(id): return {}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var request: Request = _requests[id]
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_requests.erase(id)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if request.image_file != null:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		request.image_file.close()
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		request.image_file = null
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.image_hash = null
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not bool(result.success): retire_resources(request.resources)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return {"request":request,"result":result}

func _complete(id: int, result: Dictionary) -> void:
	if _primitives.failed(): return
	var delivery := _take_completion(id,result)
	if _primitives.failed(): return
	if not delivery.is_empty(): delivery.request.completed.emit(delivery.result)

func pending_count() -> int:
	if _primitives.failed(): return ERR_UNAVAILABLE
	return _jobs.size() + _retirements.size() + _applications.size()

func metrics() -> Dictionary:
	# Physical calls are service-wide. Per-lease participation diagnostics
	# describe shared jobs and must not be added across participating leases.
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return {"request_calls":_request_calls, "get_calls":_get_calls, "jobs":_jobs.size(), "applications":_applications.size(), "retirements":_retirements.size(), "threaded_claims":threaded_claim_diagnostics()}

func _step_threaded_claim_retirement(retirement: Dictionary) -> void:
	if _primitives.failed(): return
	var path := str(retirement.get("path", ""))
	if _primitives.failed(): return
	var remaining: Variant = int(retirement.get("remaining", 0))
	if _primitives.failed(): return
	if path.is_empty() or remaining <= 0:
		if _primitives.failed(): return
		_retirements.erase(_retire_head)
		if _primitives.failed(): return
		_retire_head += 1
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var status: Variant = _primitives.load_threaded_get_status(path)
	if _primitives.failed(): return
	if status == _primitives.THREAD_LOAD_INVALID_RESOURCE:
		if _primitives.failed(): return
		_threaded_claim_diagnostics.missing += remaining
		if _primitives.failed(): return
		_retirements.erase(_retire_head)
		if _primitives.failed(): return
		_retire_head += 1
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if status == _primitives.THREAD_LOAD_IN_PROGRESS:
		# A pending owner is polled once and rotated, so normal retirement and
		# other adopted paths retain FIFO/fairness opportunities.
		if _primitives.failed(): return
		_retirements.erase(_retire_head)
		if _primitives.failed(): return
		_retire_head += 1
		if _primitives.failed(): return
		_retirement_requeue(retirement)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if status == _primitives.THREAD_LOAD_LOADED or status == _primitives.THREAD_LOAD_FAILED:
		# One terminal claim is consumed per granted quantum. FAILED is still
		# joined: the engine contract requires get() to release that user token.
		if _primitives.failed(): return
		_primitives.load_threaded_get(path)
		if _primitives.failed(): return
		_get_calls += 1
		if _primitives.failed(): return
		_threaded_claim_diagnostics.get += 1
		if _primitives.failed(): return
		remaining -= 1
		if _primitives.failed(): return
		if remaining <= 0:
			if _primitives.failed(): return
			_retirements.erase(_retire_head)
			if _primitives.failed(): return
			_retire_head += 1
		else:
			if _primitives.failed(): return
			retirement.remaining = remaining
			if _primitives.failed(): return
			_retirements.erase(_retire_head)
			if _primitives.failed(): return
			_retire_head += 1
			if _primitives.failed(): return
			_retirement_requeue(retirement)
		if _primitives.failed(): return
		return
	# Unknown status is conservatively pending; do not get a token we cannot
	# prove terminal, and rotate it behind the other retirement entries.
	if _primitives.failed(): return
	_retirements.erase(_retire_head)
	if _primitives.failed(): return
	_retire_head += 1
	if _primitives.failed(): return
	_retirement_requeue(retirement)

func _retirement_requeue(retirement: Dictionary) -> void:
	if _primitives.failed(): return
	_retirements[_retire_tail] = retirement
	if _primitives.failed(): return
	_retire_tail += 1


# All work stays in this existing owner/Budget/retirement service. No new cache.
const CodeGuard := preload("res://scripts/features/compilation/code_preparation_envelope_guard.gd")
const CodeAcquire := preload("res://scripts/features/runtime/code_input_acquisition_quantum.gd")
const CodeScope := preload("res://scripts/features/contracts/loading_preparation_scope.gd")
const MAX_CODE_REQUESTS := 16
const AndroidVerifier := preload("res://scripts/features/compilation/android_export_representation_verifier.gd")
const IMAGE_CHUNK_BYTES := 262144
const MAX_IMAGE_BYTES := 268435456
var _code_phase_metrics: Dictionary = {}

func code_phase_metrics() -> Dictionary:
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return _code_phase_metrics.duplicate(true)

func _record_code_quantum(phase: String, elapsed_usec: int) -> void:
	if _primitives.failed(): return
	if phase.is_empty():
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if not _code_phase_metrics.has(phase):
		if _primitives.failed(): return
		_code_phase_metrics[phase] = {"quanta": 0, "total_usec": 0, "worst_usec": 0}
	if _primitives.failed(): return
	var record: Dictionary = _code_phase_metrics[phase]
	if _primitives.failed(): return
	record.quanta += 1
	if _primitives.failed(): return
	record.total_usec += elapsed_usec
	if _primitives.failed(): return
	record.worst_usec = maxi(record.worst_usec, elapsed_usec)

func _queue_code_step(id: int, kind := "code_inputs") -> void:
	if _primitives.failed(): return
	_applications[_apply_tail] = {"id": id, "kind": kind}
	if _primitives.failed(): return
	_apply_tail += 1
	if _primitives.failed(): return
	_activate()

func prepare_code_publication(expected_sha256: String, expected_bytes: int, callback: Variant, scope: RefCounted, consumer: RefCounted, generation: int, publisher_sequence: int, export_contract: Dictionary = {}) -> Dictionary:
	if actual_original_live_feature_bound(): return await _await_actual_live_admission(admit_actual_original_main_command("prepare_code_publication",[expected_sha256,expected_bytes,callback,scope,consumer,generation,publisher_sequence,export_contract],_actual_live_call_context()))
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var publisher: RefCounted = _primitives.tree().root.get_node_or_null("ContentLayers")
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not _object_is_valid(publisher) or not _primitives.reference_has_method(publisher,"is_internal_code_publication_boundary_current") or not bool(publisher.is_internal_code_publication_boundary_current(publisher_sequence)) or callback.get_object() != publisher or callback.get_method() != "_publish_internal_code_catalogue" or scope == null or not _object_same(_primitives.object_script(scope), CodeScope) or not _object_is_valid(consumer) or not bool(scope.valid_for(consumer, generation)) or expected_sha256.length() != 64 or expected_bytes <= 0 or expected_bytes > MAX_IMAGE_BYTES or _requests.size() >= MAX_CODE_REQUESTS:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {"success": false, "errors": ["code_publication_owner_shape_or_loading_scope"], "lease": null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_next_request += 1
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var id := _next_request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var request := Request.new()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.kind = "code_publication"
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.scope = scope
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.consumer = weakref(consumer)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.publisher = weakref(publisher)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.generation = generation
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.plan = {"expected_sha256": expected_sha256, "expected_bytes": expected_bytes, "callback": callback, "publisher_sequence": publisher_sequence}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if OS.get_name() == "Android":
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		if not _primitives.reference_has_method(publisher,"code_preparation_export_contract") or not _primitives.reference_has_method(publisher,"code_preparation_export_seal_sha256") or publisher.code_preparation_export_contract() != export_contract or publisher.code_preparation_export_seal_sha256() != expected_sha256:
			if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
			return {"success": false, "errors": ["android_unregistered_export_contract"], "lease": null}
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		request.export_verifier = _primitives.begin_export_verification(export_contract, expected_sha256, true)
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		if request.export_verifier == null: return {"success": false, "errors": ["android_publication_contract_rejected"], "lease": null}
	elif OS.get_name() != "Windows" or not export_contract.is_empty():
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {"success": false, "errors": ["code_publication_platform_unknown"], "lease": null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.diagnostics["image_bytes"] = 0
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.diagnostics["image_quanta"] = 0
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_requests[id] = request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_queue_code_step(id, "code_publication")
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return await request.completed

func code_publication_image_current(scope: RefCounted, consumer: RefCounted, generation: int, expected_sha256: String) -> bool:
	if _primitives.failed(): return false
	if not _requests.has(_applying_request):
		if _primitives.failed(): return false
		return false
	if _primitives.failed(): return false
	var request: Request = _requests[_applying_request]
	if _primitives.failed(): return false
	return request.kind == "code_publication" and request.export_verifier == null and _object_same(request.scope, scope) and _object_same(request.consumer.get_ref(), consumer) and request.generation == generation and request.image_sha256 == expected_sha256 and request.plan.expected_sha256 == expected_sha256 and _code_owner_current(request)

func code_publication_export_current(scope: RefCounted, consumer: RefCounted, generation: int, seal_sha256: String) -> bool:
	if _primitives.failed(): return false
	if not _requests.has(_applying_request): return false
	if _primitives.failed(): return false
	var request: Request = _requests[_applying_request]
	if _primitives.failed(): return false
	return request.kind == "code_publication" and request.export_verifier != null and bool(request.export_verifier.is_verified()) and _object_same(request.scope, scope) and _object_same(request.consumer.get_ref(), consumer) and request.generation == generation and request.plan.expected_sha256 == seal_sha256 and _code_owner_current(request)

func _step_export_publication(id: int, request: Request, finished: Array) -> void:
	if _primitives.failed(): return
	var checked: Dictionary = request.export_verifier.step()
	if _primitives.failed(): return
	if not checked.success:
		if _primitives.failed(): return
		finished.append({"id": id, "result": {"success": false, "errors": checked.errors, "lease": null}})
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if not checked.done:
		if _primitives.failed(): return
		_queue_code_step(id, "code_publication")
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	request.diagnostics["runtime_native_image_sha"] = "MISSING"
	if _primitives.failed(): return
	request.diagnostics["build_verified_native_sha"] = request.publisher.get_ref().code_preparation_export_contract().build_verified_native_sha
	if _primitives.failed(): return
	request.diagnostics["native_token_device_acceptance"] = "NOT_RUN"
	if _primitives.failed(): return
	_applying_request = id
	if _primitives.failed(): return
	var callback: Variant = request.plan.callback
	if _primitives.failed(): return
	var success: bool = _primitives.invoke_callback(callback) if _primitives.callback_is_valid(callback) else false
	if _primitives.failed(): return
	_applying_request = 0
	if _primitives.failed(): return
	success = success and _code_owner_current(request)
	if _primitives.failed(): return
	finished.append({"id": id, "result": {"success": success, "errors": [] if success else ["android_publication_callback_or_cover_failed"], "lease": null, "diagnostics": request.diagnostics.duplicate(true)}})

func _step_code_publication(id: int, finished: Array) -> void:
	if _primitives.failed(): return
	if not _requests.has(id):
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var request: Request = _requests[id]
	if _primitives.failed(): return
	var publisher: RefCounted = request.publisher.get_ref() if request.publisher != null else null
	if _primitives.failed(): return
	if not _code_owner_current(request) or not _object_is_valid(publisher) or not _object_same(_primitives.tree().root.get_node_or_null("ContentLayers"), publisher) or not bool(publisher.is_internal_code_publication_boundary_current(request.plan.publisher_sequence)):
		if _primitives.failed(): return
		finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_owner_expired"], "lease": null}})
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if request.export_verifier != null:
		if _primitives.failed(): return
		_step_export_publication(id, request, finished)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if request.image_file == null:
		if _primitives.failed(): return
		request.image_file = _primitives.open_image(OS.get_executable_path(), FileAccess.READ)
		if _primitives.failed(): return
		request.image_hash = HashingContext.new()
		if _primitives.failed(): return
		if request.image_file == null or request.image_file.get_length() != request.plan.expected_bytes or request.image_hash.start(HashingContext.HASH_SHA256) != OK:
			if _primitives.failed(): return
			finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_native_image_size_or_hash_context"], "lease": null}})
			if _primitives.failed(): return
			return
	if _primitives.failed(): return
	var remaining: Variant = request.image_file.get_length() - request.image_file.get_position()
	if _primitives.failed(): return
	if remaining > 0:
		if _primitives.failed(): return
		var bytes: PackedByteArray = request.image_file.get_buffer(mini(IMAGE_CHUNK_BYTES, remaining))
		if _primitives.failed(): return
		if bytes.size() != mini(IMAGE_CHUNK_BYTES, remaining) or request.image_hash.update(bytes) != OK:
			if _primitives.failed(): return
			finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_native_image_read_failed"], "lease": null}})
			if _primitives.failed(): return
			return
		if _primitives.failed(): return
		request.diagnostics.image_bytes += bytes.size()
		if _primitives.failed(): return
		request.diagnostics.image_quanta += 1
		if _primitives.failed(): return
		_queue_code_step(id, "code_publication")
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	request.image_sha256 = request.image_hash.finish().hex_encode()
	if _primitives.failed(): return
	request.image_hash = null
	if _primitives.failed(): return
	request.image_file.close()
	if _primitives.failed(): return
	request.image_file = null
	if _primitives.failed(): return
	if request.image_sha256 != request.plan.expected_sha256 or not _code_owner_current(request):
		if _primitives.failed(): return
		finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_native_image_or_cover_changed"], "lease": null}})
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	_applying_request = id
	if _primitives.failed(): return
	var callback: Variant = request.plan.callback
	if _primitives.failed(): return
	var success: bool = _primitives.invoke_callback(callback) if _primitives.callback_is_valid(callback) else false
	if _primitives.failed(): return
	_applying_request = 0
	if _primitives.failed(): return
	success = success and _code_owner_current(request)
	if _primitives.failed(): return
	finished.append({"id": id, "result": {"success": success, "errors": [] if success else ["code_publication_callback_or_cover_failed"], "lease": null, "diagnostics": request.diagnostics.duplicate(true)}})

func prepare_code_inputs(payload: Dictionary, entry_id: String, publisher: RefCounted, scope: RefCounted, consumer: RefCounted, generation: int) -> Dictionary:
	if actual_original_live_feature_bound(): return await _await_actual_live_admission(admit_actual_original_main_command("prepare_code_inputs",[payload,entry_id,publisher,scope,consumer,generation],_actual_live_call_context()))
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not _object_is_valid(consumer) or not _object_is_valid(publisher) or scope == null or not _object_same(_primitives.object_script(scope), CodeScope) or not bool(scope.valid_for(consumer, generation)) or _requests.size() >= MAX_CODE_REQUESTS:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {"success": false, "errors": ["code_preparation_owner_or_capacity"], "lease": null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_next_request += 1
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var id := _next_request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var request := Request.new()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.kind = "code_inputs"
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.plan = payload
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.entry_id = entry_id
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.publisher = weakref(publisher)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.scope = scope
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.consumer = weakref(consumer)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.generation = generation
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.diagnostics["verification_usec"] = 0
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.diagnostics["admission_usec"] = 0
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.diagnostics["inputs"] = []
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_requests[id] = request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_queue_code_step(id)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return await request.completed

func _code_owner_current(request: Request) -> bool:
	if _primitives.failed(): return false
	var consumer: RefCounted = request.consumer.get_ref() if request.consumer != null else null
	if _primitives.failed(): return false
	return _object_is_valid(consumer) and request.scope != null and bool(request.scope.valid_for(consumer, request.generation))

func _step_code_inputs(id: int, finished: Array) -> void:
	if _primitives.failed(): return
	if not _requests.has(id):
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var request: Request = _requests[id]
	if _primitives.failed(): return
	if not _code_owner_current(request):
		if _primitives.failed(): return
		finished.append({"id": id, "result": {"success": false, "errors": ["code_preparation_owner_expired"], "lease": null}})
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var consumer: RefCounted = request.consumer.get_ref()
	if _primitives.failed(): return
	if request.code_plan == null:
		if _primitives.failed(): return
		var began := Time.get_ticks_usec()
		if _primitives.failed(): return
		var publisher: RefCounted = request.publisher.get_ref()
		if _primitives.failed(): return
		var checked: Dictionary = _primitives.begin_code_verification(request.plan, request.entry_id, publisher, consumer)
		if _primitives.failed(): return
		request.diagnostics.verification_usec += Time.get_ticks_usec() - began
		if _primitives.failed(): return
		if not checked.success:
			if _primitives.failed(): return
			finished.append({"id": id, "result": {"success": false, "errors": checked.errors, "lease": null}})
			if _primitives.failed(): return
			return
		if _primitives.failed(): return
		request.code_plan = checked.plan
		if _primitives.failed(): return
		_queue_code_step(id)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if not bool(request.code_plan.is_verified()):
		if _primitives.failed(): return
		var began := Time.get_ticks_usec()
		if _primitives.failed(): return
		var checked: Dictionary = request.code_plan.verify_next_source()
		if _primitives.failed(): return
		request.diagnostics.verification_usec += Time.get_ticks_usec() - began
		if _primitives.failed(): return
		if not checked.success:
			if _primitives.failed(): return
			finished.append({"id": id, "result": {"success": false, "errors": checked.errors, "lease": null}})
		else:
			if _primitives.failed(): return
			_queue_code_step(id)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var paths: Array = request.code_plan.paths()
	if _primitives.failed(): return
	if request.cursor < paths.size():
		if _primitives.failed(): return
		var path: String = paths[request.cursor]
		if _primitives.failed(): return
		request.cursor += 1
		if _primitives.failed(): return
		var acquired: Dictionary = _primitives.acquire_shader(request.code_plan, request.scope, consumer, request.generation, path, _jobs.get(path, {}))
		# Failure may already own a Resource. Original _take_completion submits
		# request.resources to this same retirement queue; never drop it here.
		if _primitives.failed(): return
		if acquired.resource != null:
			if _primitives.failed(): return
			request.resources[path] = acquired.resource
		if _primitives.failed(): return
		var diagnostic := acquired.duplicate(false)
		if _primitives.failed(): return
		diagnostic.erase("resource")
		if _primitives.failed(): return
		diagnostic["path"] = path
		if _primitives.failed(): return
		request.diagnostics.inputs.append(diagnostic)
		if _primitives.failed(): return
		if not acquired.success:
			if _primitives.failed(): return
			finished.append({"id": id, "result": {"success": false, "errors": acquired.errors, "lease": null}})
		else:
			if _primitives.failed(): return
			_queue_code_step(id)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var lease: RefCounted = _primitives.issue_code_inputs(request.code_plan, request.resources, self, request.diagnostics)
	if _primitives.failed(): return
	finished.append({"id": id, "result": {"success": lease != null, "errors": [] if lease != null else ["code_input_lease_invalid"], "lease": lease,
		"plan": request.code_plan, "scope": request.scope, "entry_id": request.entry_id, "generation": request.generation, "diagnostics": request.diagnostics.duplicate(true)}})

func request_code_script(prepared: Dictionary, consumer: RefCounted, generation: int) -> Dictionary:
	if actual_original_live_feature_bound(): return await _await_actual_live_admission(admit_actual_original_main_command("request_code_script",[prepared,consumer,generation],_actual_live_call_context()))
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var plan_value: Variant = prepared.get("plan")
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var lease_value: Variant = prepared.get("lease")
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var scope_value: Variant = prepared.get("scope")
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not plan_value is RefCounted or not lease_value is RefCounted or not scope_value is RefCounted:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {"success": false, "errors": ["code_target_prepared_value_shape"], "resource": null, "lease": null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var plan: RefCounted = plan_value
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var lease: RefCounted = lease_value
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var scope: RefCounted = scope_value
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not _object_same(_primitives.object_script(plan), CodeGuard) or not _object_same(_primitives.object_script(lease), Lease) or not _object_same(_primitives.object_script(scope), CodeScope):
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {"success": false, "errors": ["code_target_prepared_contract_identity"], "resource": null, "lease": null}
	# File/source and lease verification happens in _step_code_target's charged
	# quantum; this public entry performs only shape/owner admission.
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not bool(prepared.get("success", false)) or not _object_is_valid(consumer) or generation != prepared.get("generation") or not bool(scope.valid_for(consumer, generation)) or _requests.size() >= MAX_CODE_REQUESTS:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {"success": false, "errors": ["code_target_preparation_or_owner_invalid"], "resource": null, "lease": null}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var path: String = plan.target_path()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_next_request += 1
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var id := _next_request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var request := Request.new()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.kind = "code_target"
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.code_plan = plan
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.scope = scope
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.consumer = weakref(consumer)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.generation = generation
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.input_lease = lease
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_requests[id] = request
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if _jobs.has(path):
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		if _jobs[path].get("kind") != "code_target" or _jobs[path].get("plan_signature") != plan.signature():
			if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
			_requests.erase(id)
			if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
			return {"success": false, "errors": ["code_target_job_mode_conflict"], "resource": null, "lease": null}
	else:
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		_jobs[path] = {"kind": "code_target", "started": false, "clients": {}, "input_leases": {}, "delivering": false, "resource": null, "failure": "", "mode": "", "retained": false, "plan_signature": plan.signature()}
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		_queue(path)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_jobs[path].clients[id] = true
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_jobs[path].input_leases[id] = lease
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_activate()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return await request.completed

func _step_code_target(path: String, job: Dictionary, finished: Array) -> void:
	# Cancellation cannot retire input leases until the physical get is done.
	if _primitives.failed(): return
	for id: int in job.clients.keys():
		if _primitives.failed(): return
		if _requests.has(id) and not _code_owner_current(_requests[id]):
			if _primitives.failed(): return
			finished.append({"id": id, "result": {"success": false, "errors": ["code_target_owner_expired"], "resource": null, "lease": null}})
			if _primitives.failed(): return
			job.clients.erase(id)
	if _primitives.failed(): return
	var resource: RefCounted = job.resource
	if _primitives.failed(): return
	if not bool(job.started) and not bool(job.delivering):
		if _primitives.failed(): return
		var next_id := -1
		if _primitives.failed(): return
		for id: int in job.clients:
			if _primitives.failed(): return
			if _requests.has(id):
				if _primitives.failed(): return
				next_id = id
				if _primitives.failed(): return
				break
		if _primitives.failed(): return
		if next_id < 0:
			if _primitives.failed(): return
			_jobs.erase(path)
			if _primitives.failed(): return
			job.input_leases.clear()
			if _primitives.failed(): return
			return
		if _primitives.failed(): return
		var request: Request = _requests[next_id]
		if _primitives.failed(): return
		var began := Time.get_ticks_usec()
		if _primitives.failed(): return
		var current: Dictionary = request.code_plan.revalidate_admission_sources()
		if _primitives.failed(): return
		if not current.success or not _code_owner_current(request) or not bool(request.input_lease.valid_for_code(request.code_plan)):
			if _primitives.failed(): return
			request.diagnostics["admission_usec"] = Time.get_ticks_usec() - began
			if _primitives.failed(): return
			job.failure = "code_target_source_or_owner_changed"
			if _primitives.failed(): return
			job.delivering = true
		else:
			if _primitives.failed(): return
			request.diagnostics["admission_usec"] = Time.get_ticks_usec() - began
			if _primitives.failed(): return
			resource = _primitives.get_cached_ref(path)
			if _primitives.failed(): return
			if resource != null:
				if _primitives.failed(): return
				job.mode = "cache_hits"
				if _primitives.failed(): return
				job.resource = resource
				if _primitives.failed(): return
				job.delivering = true
			elif _primitives.load_threaded_get_status(path) != _primitives.THREAD_LOAD_INVALID_RESOURCE:
				if _primitives.failed(): return
				job.failure = "code_target_external_native_job_unproved"
				if _primitives.failed(): return
				job.delivering = true
			else:
				# No await/callback between fresh bounded source admission and the
				# real request. Same _jobs owner owns this one accepted user token.
				if _primitives.failed(): return
				var error: Variant = _primitives.load_threaded_request(path, "Script", false)
				if _primitives.failed(): return
				_request_calls += 1
				if _primitives.failed(): return
				if error == OK:
					if _primitives.failed(): return
					job.started = true
				else:
					if _primitives.failed(): return
					job.failure = "code_target_request_failed:" + path
					if _primitives.failed(): return
					job.delivering = true
		if _primitives.failed(): return
		_queue(path)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	if not bool(job.delivering):
		if _primitives.failed(): return
		var status: Variant = _primitives.load_threaded_get_status(path)
		if _primitives.failed(): return
		if status == _primitives.THREAD_LOAD_LOADED:
			if _primitives.failed(): return
			job.resource = _primitives.load_threaded_get(path)
			if _primitives.failed(): return
			_get_calls += 1
			if _primitives.failed(): return
			job.mode = "threaded_completed"
			if _primitives.failed(): return
			job.delivering = true
		elif status == _primitives.THREAD_LOAD_FAILED:
			if _primitives.failed(): return
			_primitives.load_threaded_get(path)
			if _primitives.failed(): return
			_get_calls += 1
			if _primitives.failed(): return
			job.failure = "code_target_load_failed:" + path
			if _primitives.failed(): return
			job.delivering = true
		elif status == _primitives.THREAD_LOAD_INVALID_RESOURCE:
			if _primitives.failed(): return
			job.failure = "code_target_invalid_without_phantom_get:" + path
			if _primitives.failed(): return
			job.delivering = true
		if _primitives.failed(): return
		_queue(path)
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var next_id := -1
	if _primitives.failed(): return
	for id: int in job.clients:
		if _primitives.failed(): return
		next_id = id
		if _primitives.failed(): return
		break
	if _primitives.failed(): return
	if next_id >= 0:
		if _primitives.failed(): return
		job.clients.erase(next_id)
		if _primitives.failed(): return
		if _requests.has(next_id):
			if _primitives.failed(): return
			var request: Request = _requests[next_id]
			if _primitives.failed(): return
			var target: RefCounted = job.resource
			if _primitives.failed(): return
			var success: bool = str(job.failure).is_empty() and bool(request.code_plan.valid_target(target)) and _code_owner_current(request) and bool(request.input_lease.valid_for_code(request.code_plan))
			if _primitives.failed(): return
			if success:
				if _primitives.failed(): return
				success = request.input_lease.attach_loaded_code_resource(request.code_plan, target, request.consumer.get_ref(), self)
			if _primitives.failed(): return
			if success:
				if _primitives.failed(): return
				job.retained = true
			if _primitives.failed(): return
			finished.append({"id": next_id, "result": {"success": success, "errors": [] if success else [str(job.failure) if not str(job.failure).is_empty() else "code_target_owner_or_type_invalid"],
				"resource": target if success else null, "lease": request.input_lease if success else null, "diagnostics": request.diagnostics.duplicate(true)}})
	if _primitives.failed(): return
	if job.clients.is_empty():
		if _primitives.failed(): return
		_jobs.erase(path)
		if _primitives.failed(): return
		job.input_leases.clear()
		if _primitives.failed(): return
		if job.resource != null and not bool(job.retained):
			if _primitives.failed(): return
			retire_resources({path: job.resource})
	else:
		if _primitives.failed(): return
		_queue(path)

func cancel_code_owner(consumer: RefCounted, generation: int) -> void:
	if actual_original_live_feature_bound():
		for request: Request in _requests.values():
			if request.kind in ["code_publication","code_inputs","code_target"] and request.generation == generation and request.consumer != null and is_same(request.consumer.get_ref(),consumer): _mark_actual_live_completion(request,{"success":false,"errors":["code_owner_cancelled"],"lease":null,"resource":null},true)
		_activate(); return
	if _primitives.failed(): return
	for id: int in _requests.keys():
		if _primitives.failed(): return
		var request: Request = _requests[id]
		if _primitives.failed(): return
		if request.kind not in ["code_publication", "code_inputs", "code_target"] or request.generation != generation or request.consumer == null or not _object_same(request.consumer.get_ref(), consumer):
			if _primitives.failed(): return
			continue
		if _primitives.failed(): return
		request.scope.cancel()
		if _primitives.failed(): return
		var result := {"success": false, "errors": ["code_owner_cancelled"], "lease": null, "resource": null}
		if _primitives.failed(): return
		if _quantum_active:
			if _primitives.failed(): return
			_deferred_completions.append({"id": id, "result": result})
		else:
			if _primitives.failed(): return
			_complete(id, result)
	if _primitives.failed(): return
	_activate()

func retire_code_result(result: Dictionary) -> void:
	if _primitives.failed(): return
	if actual_original_live_feature_bound():
		_retire_actual_live_code_result(result)
		return
	var resource: Variant = result.get("resource")
	if _primitives.failed(): return
	var lease: Variant = result.get("lease")
	if _primitives.failed(): return
	if _primitives.is_native_type(resource,"Resource") and not (lease is RefCounted and _object_same(_primitives.object_script(lease), Lease) and _object_same(_primitives.retained_code_resource(lease), resource)):
		if _primitives.failed(): return
		retire_resources({resource.resource_path: resource})
	if _primitives.failed(): return
	result.clear() # original lease PREDELETE submits Shader + retained Script refs.

func _retire_actual_live_code_result(result: Dictionary) -> void:
	# Original LIVE retirement body, shared by the genuine Main command and
	# original Source Root exit. Tokens already carry their issued identity;
	# inspecting a physical Script here would park LIVE on a forbidden query.
	var lease: Variant = result.get("lease")
	var resource: Variant = result.get("resource")
	if resource != null and not (lease is Lease and is_same(lease._domain_code_resource,resource)):
		retire_resources({"actual_code_result":resource})
	result.clear() # Existing domain PREDELETE retains the actual cleanup debt.

func _exit_tree() -> void:
	if _primitives.failed(): return
	_retire_code_world_handoff()
	# Engine requests cannot be cancelled. Final shutdown may join IN_PROGRESS;
	# ordinary scene work keeps its existing timeout and optional Budget quanta.
	if _primitives.failed(): return
	for path: String in _jobs.keys():
		if _primitives.failed(): return
		var job: Dictionary = _jobs[path]
		if _primitives.failed(): return
		if bool(job.get("started", false)) and not bool(job.get("delivering", false)):
			if _primitives.failed(): return
			var status: Variant = _primitives.load_threaded_get_status(path)
			if _primitives.failed(): return
			if status in [_primitives.THREAD_LOAD_IN_PROGRESS, _primitives.THREAD_LOAD_LOADED, _primitives.THREAD_LOAD_FAILED]:
				if _primitives.failed(): return
				_primitives.load_threaded_get(path)
				if _primitives.failed(): return
				_get_calls += 1
	# Adopted claims are service-owned too. At global service shutdown the
	# existing join contract applies; ordinary scene retirement never reaches
	# this path and therefore never blocks on an IN_PROGRESS claim.
	if _primitives.failed(): return
	for index in _retirements:
		if _primitives.failed(): return
		var retirement: Dictionary = _retirements[index]
		if _primitives.failed(): return
		if not bool(retirement.get("__threaded_claim__", false)):
			if _primitives.failed(): return
			continue
		if _primitives.failed(): return
		var claim_path := str(retirement.get("path", ""))
		if _primitives.failed(): return
		var remaining: Variant = int(retirement.get("remaining", 0))
		if _primitives.failed(): return
		var claim_status: Variant = _primitives.load_threaded_get_status(claim_path)
		if _primitives.failed(): return
		if claim_status in [_primitives.THREAD_LOAD_IN_PROGRESS, _primitives.THREAD_LOAD_LOADED, _primitives.THREAD_LOAD_FAILED]:
			if _primitives.failed(): return
			for _claim in range(remaining):
				if _primitives.failed(): return
				_primitives.load_threaded_get(claim_path)
				if _primitives.failed(): return
				_get_calls += 1
				if _primitives.failed(): return
				_threaded_claim_diagnostics.get += 1
		elif claim_status == _primitives.THREAD_LOAD_INVALID_RESOURCE:
			if _primitives.failed(): return
			_threaded_claim_diagnostics.missing += remaining
	if _primitives.failed(): return
	_jobs.clear()
	if _primitives.failed(): return
	_requests.clear()
	if _primitives.failed(): return
	_retirements.clear()
	if _primitives.failed(): return
	_applications.clear()


func code_result_retention_current(result: Dictionary, consumer: RefCounted) -> bool:
	if _primitives.failed(): return false
	var lease: Variant = result.get("lease")
	if _primitives.failed(): return false
	var resource: Variant = result.get("resource")
	if _primitives.failed(): return false
	return bool(result.get("success", false)) and lease is RefCounted and _object_same(_primitives.object_script(lease), Lease) and _primitives.is_native_type(resource,"Script") and bool(lease.loaded_code_retention_current(resource, consumer, self))

func transfer_code_result_retention(result: Dictionary, previous: RefCounted, next_consumer: RefCounted) -> bool:
	if _primitives.failed(): return false
	if not code_result_retention_current(result, previous) or not _object_is_valid(next_consumer) or not next_consumer.is_inside_tree():
		if _primitives.failed(): return false
		return false
	if _primitives.failed(): return false
	var previous_script: RefCounted = _primitives.cast(_primitives.object_script(previous),"Script")
	if _primitives.failed(): return false
	var next_script: RefCounted = _primitives.cast(_primitives.object_script(next_consumer),"Script")
	if _primitives.failed(): return false
	if previous_script == null or next_script == null or previous_script.resource_path != "res://scripts/startup_loading.gd" or next_script.resource_path != "res://scripts/character_select.gd":
		if _primitives.failed(): return false
		return false
	if _primitives.failed(): return false
	return bool(result.lease.transfer_loaded_code_retention(result.resource, previous, next_consumer, self))

# One outstanding scene handoff lives in the existing request ledger. It is
# not a cache and owns no native request. The next actual current scene closes
# an unclaimed handoff; only the prepared PackedScene's Script may claim.
var _code_world_handoff_id := 0

func _stage_code_world_handoff(result: Dictionary, consumer: RefCounted, scene: RefCounted) -> int:
	if _primitives.failed(): return ERR_UNAVAILABLE
	if _code_world_handoff_id != 0 or _requests.size() >= MAX_CODE_REQUESTS or not code_result_retention_current(result, consumer) or not _object_same(_primitives.tree().current_scene, consumer) or scene == null or scene.resource_path != "res://scenes/main.tscn" or not _object_same(_primitives.get_cached_ref(scene.resource_path), scene):
		if _primitives.failed(): return ERR_UNAVAILABLE
		return 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	var consumer_script: RefCounted = _primitives.cast(_primitives.object_script(consumer),"Script")
	if _primitives.failed(): return ERR_UNAVAILABLE
	var publisher: RefCounted = _primitives.tree().root.get_node_or_null("ContentLayers")
	if _primitives.failed(): return ERR_UNAVAILABLE
	if consumer_script == null or consumer_script.resource_path != "res://scripts/character_select.gd" or not _object_is_valid(publisher) or not _object_same(publisher._feature_resources(), self):
		if _primitives.failed(): return ERR_UNAVAILABLE
		return 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	var generation: int = consumer.get("_launch_code_generation")
	if _primitives.failed(): return ERR_UNAVAILABLE
	var overlay: RefCounted = _primitives.cast(consumer.get("launch_loading_overlay"),"Control")
	if _primitives.failed(): return ERR_UNAVAILABLE
	var overlay_script: RefCounted
	if _primitives.failed(): return ERR_UNAVAILABLE
	if _object_is_valid(overlay):
		if _primitives.failed(): return ERR_UNAVAILABLE
		overlay_script = _primitives.cast(_primitives.object_script(overlay),"Script")
	if _primitives.failed(): return ERR_UNAVAILABLE
	if overlay_script == null or overlay_script.resource_path != "res://scripts/loading_transition_overlay.gd" or not _object_same(overlay.get_parent(), consumer) or not consumer.is_code_preparation_generation_current(generation) or not consumer.is_code_preparation_loading_phase_current(generation) or overlay.code_preparation_cover_receipt().is_empty():
		if _primitives.failed(): return ERR_UNAVAILABLE
		return 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	var state: RefCounted = scene.get_state()
	if _primitives.failed(): return ERR_UNAVAILABLE
	if state.get_node_count() != 1 or state.get_node_property_count(0) > 64:
		if _primitives.failed(): return ERR_UNAVAILABLE
		return 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	var world_script: RefCounted
	if _primitives.failed(): return ERR_UNAVAILABLE
	for index in range(state.get_node_property_count(0)):
		if _primitives.failed(): return ERR_UNAVAILABLE
		if state.get_node_property_name(0, index) == &"script":
			if _primitives.failed(): return ERR_UNAVAILABLE
			world_script = _primitives.cast(state.get_node_property_value(0, index),"Script")
	if _primitives.failed(): return ERR_UNAVAILABLE
	if world_script == null or world_script.resource_path != "res://scripts/game_root.gd" or not _object_same(_primitives.get_cached_ref(world_script.resource_path), world_script):
		if _primitives.failed(): return ERR_UNAVAILABLE
		return 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	if not bool(result.lease.transfer_loaded_code_retention(result.resource, consumer, publisher, self)):
		if _primitives.failed(): return ERR_UNAVAILABLE
		return 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	_next_request += 1
	if _primitives.failed(): return ERR_UNAVAILABLE
	var id := _next_request
	if _primitives.failed(): return ERR_UNAVAILABLE
	var request := Request.new()
	if _primitives.failed(): return ERR_UNAVAILABLE
	request.kind = "code_retention_handoff"
	if _primitives.failed(): return ERR_UNAVAILABLE
	request.consumer = weakref(consumer)
	if _primitives.failed(): return ERR_UNAVAILABLE
	request.publisher = weakref(publisher)
	if _primitives.failed(): return ERR_UNAVAILABLE
	request.input_lease = result.lease
	if _primitives.failed(): return ERR_UNAVAILABLE
	request.plan = {"result": result.duplicate(false), "world_script": world_script}
	if _primitives.failed(): return ERR_UNAVAILABLE
	_requests[id] = request
	if _primitives.failed(): return ERR_UNAVAILABLE
	_code_world_handoff_id = id
	if _primitives.failed(): return ERR_UNAVAILABLE
	_queue_code_step(id, "code_retention_handoff")
	if _primitives.failed(): return ERR_UNAVAILABLE
	_activate()
	if _primitives.failed(): return ERR_UNAVAILABLE
	return id

func change_scene_with_code_retention(result: Dictionary, consumer: RefCounted, scene: RefCounted) -> int:
	# Reservation, original SceneTree call and error cleanup are atomic: no
	# caller can exit/reenter between staging and submitting its replacement.
	if _primitives.failed(): return ERR_UNAVAILABLE
	var id := _stage_code_world_handoff(result, consumer, scene)
	if _primitives.failed(): return ERR_UNAVAILABLE
	if id == 0:
		if _primitives.failed(): return ERR_UNAVAILABLE
		return ERR_UNAVAILABLE
	if _primitives.failed(): return ERR_UNAVAILABLE
	var error: int = _primitives.tree().change_scene_to_packed(scene)
	if _primitives.failed(): return ERR_UNAVAILABLE
	if error != OK:
		if _primitives.failed(): return ERR_UNAVAILABLE
		var request: Request = _requests[id]
		if _primitives.failed(): return ERR_UNAVAILABLE
		var publisher: RefCounted = request.publisher.get_ref()
		if _primitives.failed(): return ERR_UNAVAILABLE
		var held: Dictionary = request.plan.result
		if _primitives.failed(): return ERR_UNAVAILABLE
		if code_result_retention_current(held, publisher) and bool(held.lease.transfer_loaded_code_retention(held.resource, publisher, consumer, self)):
			if _primitives.failed(): return ERR_UNAVAILABLE
			_requests.erase(id)
			if _primitives.failed(): return ERR_UNAVAILABLE
			_code_world_handoff_id = 0
			if _primitives.failed(): return ERR_UNAVAILABLE
			request.plan.clear()
			if _primitives.failed(): return ERR_UNAVAILABLE
			request.input_lease = null # original Hall dictionary still owns its lease.
		else:
			if _primitives.failed(): return ERR_UNAVAILABLE
			_retire_code_world_handoff()
	if _primitives.failed(): return ERR_UNAVAILABLE
	return error

func claim_code_world_handoff(consumer: RefCounted) -> Dictionary:
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if _code_world_handoff_id == 0 or not _requests.has(_code_world_handoff_id) or not _object_is_valid(consumer) or not consumer.is_inside_tree() or consumer.original_main_is_queued_for_deletion() or not _object_same(_primitives.tree().current_scene, consumer) or not _object_same(consumer.get_parent(), _primitives.tree().root) or consumer.scene_file_path != "res://scenes/main.tscn":
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var request: Request = _requests[_code_world_handoff_id]
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var publisher: RefCounted = request.publisher.get_ref()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var held: Dictionary = request.plan.result
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	if not _object_same(_primitives.object_script(consumer), request.plan.world_script) or not code_result_retention_current(held, publisher) or not bool(held.lease.transfer_loaded_code_retention(held.resource, publisher, consumer, self)):
		if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
		return {}
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	var result: Dictionary = held.duplicate(false)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_requests.erase(_code_world_handoff_id)
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	_code_world_handoff_id = 0
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.plan.clear()
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	request.input_lease = null
	if _primitives.failed(): return {"success":false,"errors":["feature_resource_owner_fault"],"lease":null}
	return result

func _retire_code_world_handoff() -> void:
	if _primitives.failed(): return
	if _code_world_handoff_id == 0 or not _requests.has(_code_world_handoff_id):
		if _primitives.failed(): return
		_code_world_handoff_id = 0
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var request: Request = _requests[_code_world_handoff_id]
	if _primitives.failed(): return
	_requests.erase(_code_world_handoff_id)
	if _primitives.failed(): return
	_code_world_handoff_id = 0
	if _primitives.failed(): return
	retire_code_result(request.plan.result)
	if _primitives.failed(): return
	request.plan.clear()
	if _primitives.failed(): return
	request.input_lease = null

func _step_code_world_handoff(id: int) -> void:
	if _primitives.failed(): return
	if id != _code_world_handoff_id or not _requests.has(id):
		if _primitives.failed(): return
		return
	if _primitives.failed(): return
	var request: Request = _requests[id]
	if _primitives.failed(): return
	var publisher: RefCounted = request.publisher.get_ref()
	if _primitives.failed(): return
	if not code_result_retention_current(request.plan.result, publisher):
		if _primitives.failed(): return
		_retire_code_world_handoff()
	else:
		if _primitives.failed(): return
		var current_scene: RefCounted = _primitives.tree().current_scene
		if _primitives.failed(): return
		var previous: RefCounted = request.consumer.get_ref()
		# SceneTree removes the old scene immediately and adds the replacement at
		# its existing frame boundary. Null is an in-progress replacement, not an
		# invented failure timeout. New GameRoot claims synchronously in _ready.
		if _primitives.failed(): return
		if _object_is_valid(current_scene) and not _object_same(current_scene, previous):
			if _primitives.failed(): return
			_retire_code_world_handoff()
		else:
			if _primitives.failed(): return
			_queue_code_step(id, "code_retention_handoff")

func pending_code_count() -> int:
	if _primitives.failed(): return ERR_UNAVAILABLE
	var count := 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	for request: Request in _requests.values():
		if _primitives.failed(): return ERR_UNAVAILABLE
		count += 1 if request.kind in ["code_publication", "code_inputs", "code_target", "code_retention_handoff"] else 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	for job: Dictionary in _jobs.values():
		if _primitives.failed(): return ERR_UNAVAILABLE
		count += 1 if job.get("kind") == "code_target" else 0
	if _primitives.failed(): return ERR_UNAVAILABLE
	return count

## Appended to the unique Source Feature coordinator. These maps associate
## evidence with the original FIFO entries; they never schedule/poll/get work.
var _issued_source_host: Object
var _issued_source_session_id := 0
var _issued_bridge_generation := 0
var _issued_source_records: Dictionary={}
var _issued_accepting: Dictionary={}
var _issued_active_retirement: Dictionary={}
func configure_original_issued_claim_bridge(host: Object, session: RefCounted) -> bool:
	if host==null or _issued_source_host!=null or OS.get_thread_caller_id()!=owner_thread_id(): return false
	if session==null or session.owner_thread_id()!=owner_thread_id() or not is_same(Budget,session.original_frame_budget()) or not is_same(_primitives.get("_budget"),Budget) or not is_same(session.feature_resource_session().coordinator,self): return false
	for method: String in ["accept_claim_transfer","bind_original_source_feature_claim_owner"]:
		if not host.has_method(method): return false
	if not host.bind_original_source_feature_claim_owner(self,get_script().get_source_code().sha256_text()): return false
	_issued_source_session_id=int(session.lifetime_evidence().session_id)
	_issued_bridge_generation=int(host.capabilities().bridge_generation)
	_issued_source_host=host;return _primitives.configure_original_issued_claim_owner(self)
func accept_original_issued_claim_offer(identity: Dictionary) -> Dictionary:
	if _issued_source_host==null or OS.get_thread_caller_id()!=owner_thread_id(): return {"status":"INVALID"}
	# Native validates OFFERED provenance and pre-reserves association/ACK
	# capacity before calling the registered S admission callback below.
	var actual: Dictionary=_issued_source_host.accept_claim_transfer(identity)
	if actual.get("state") in ["ACCEPTED","ORIGIN_RELEASED","TERMINAL"]:
		var key: String=IssuedClaimIdentity.key(identity)
		if not _issued_source_records.has(key): return actual if actual.get("state")=="TERMINAL" else {"status":"INVALID"}
		_issued_source_records[key].sealed=true
	return actual
func admit_original_issued_claim_responsibility(identity: Dictionary, evidence: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=owner_thread_id() or not _issued_accepting.is_empty() or _primitives.failed() or evidence.get("identity")!=identity or int(evidence.get("claim_count",0))<=0 or evidence.get("owner_descriptor",{}).get("owner_session_id")!=_issued_source_session_id or identity.get("bridge_generation")!=_issued_bridge_generation: return {"success":false,"insertion":"NONE"}
	var key: String=IssuedClaimIdentity.key(identity)
	if _issued_source_records.has(key): return capture_original_issued_claim_queue_state(identity)
	# If an earlier callback inserted before ACK interruption, its exact
	# metadata is proof; path/count coincidence from an older entry is not.
	for location: int in _retirements:
		var existing: Dictionary=_retirements[location]
		if existing.get("__original_issued_claim__",{}).get("identity")==identity:
			var meta: Dictionary=existing.__original_issued_claim__
			if var_to_bytes(meta.evidence)!=var_to_bytes(evidence): return {"success":false,"insertion":"UNKNOWN"}
			_issued_source_records[key]=meta
			return capture_original_issued_claim_queue_state(identity)
	_issued_accepting={"identity":identity,"evidence":evidence}
	var original_entry: int=_retire_tail
	var accepted: bool=retire_threaded_resource_claims(evidence.path,evidence.claim_count)
	_issued_accepting={}
	if not accepted:
		# Original failed-method side effects cannot be guessed away. Native
		# retains debt/fault if an exact insertion cannot be classified.
		return {"success":false,"insertion":"UNKNOWN" if _retirements.has(original_entry) else "NONE"}
	if not _retirements.has(original_entry) or _retirements[original_entry].get("path")!=evidence.path or _retirements[original_entry].get("remaining")!=evidence.claim_count or _retire_tail!=original_entry+1: return {"success":false,"insertion":"UNKNOWN"}
	var meta: Dictionary={"identity":identity,"evidence":evidence,"original_entry_id":original_entry,"claim_count":evidence.claim_count,"sealed":false}
	_retirements[original_entry]["__original_issued_claim__"]=meta
	_issued_source_records[key]=meta
	return capture_original_issued_claim_queue_state(identity)
func original_issued_claim_adoption_gate(path: String, count: int) -> bool:
	# Only inside Native's current S acceptance callback; this is an admission
	# proof gate, not a prior ADOPTED state or a reverse Main physical call.
	return not _issued_accepting.is_empty() and _issued_accepting.evidence.path==path and _issued_accepting.evidence.claim_count==count
func capture_original_issued_claim_queue_state(identity: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=owner_thread_id(): return {"success":false,"insertion":"UNKNOWN"}
	var key: String=IssuedClaimIdentity.key(identity)
	if not _issued_source_records.has(key): return {"success":false,"insertion":"NONE"}
	var meta: Dictionary=_issued_source_records[key]
	for location: int in _retirements:
		var actual: Dictionary=_retirements[location]
		if actual.get("__original_issued_claim__",{}).get("identity")!=identity: continue
		if actual.__original_issued_claim__!=meta or actual.get("__threaded_claim__")!=true or actual.path!=meta.evidence.path or actual.remaining<=0 or actual.remaining>meta.claim_count: return {"success":false,"insertion":"UNKNOWN"}
		return {"success":true,"insertion":"EXACT","identity":identity,"original_entry_id":meta.original_entry_id,"current_queue_location":location,"path":actual.path,"claim_count":meta.claim_count,"remaining_count":actual.remaining,"owner_session_id":meta.evidence.owner_descriptor.owner_session_id,"actual_source_owner_id":get_instance_id()}
	return {"success":true,"insertion":"REMOVED","identity":identity,"original_entry_id":meta.original_entry_id,"current_queue_location":-1,"path":meta.evidence.path,"claim_count":meta.claim_count,"remaining_count":0,"owner_session_id":meta.evidence.owner_descriptor.owner_session_id,"actual_source_owner_id":get_instance_id()}
func _begin_original_issued_claim_retirement(retirement: Dictionary) -> bool:
	var meta: Dictionary=retirement.get("__original_issued_claim__",{})
	if meta.is_empty(): return true
	if not meta.sealed:
		var sealed: Dictionary=accept_original_issued_claim_offer(meta.identity)
		if sealed.get("state") not in ["ACCEPTED","ORIGIN_RELEASED","TERMINAL"]:
			# Pending ACK is a pending original retirement visit. Rotate using
			# the same original FIFO operation; do not add a poll or extra pump.
			_retirements.erase(_retire_head);_retire_head+=1;_retirement_requeue(retirement)
			return false
	_issued_active_retirement=retirement
	return true
func capture_original_issued_claim_leaf_context() -> Dictionary:
	if _issued_active_retirement.is_empty(): return {}
	var meta: Dictionary=_issued_active_retirement.__original_issued_claim__
	return {"identity":meta.identity,"original_entry_id":meta.original_entry_id,"original_first_claim_ordinal":meta.claim_count-_issued_active_retirement.remaining,"remaining_count":_issued_active_retirement.remaining,"path":_issued_active_retirement.path,"owner_session_id":meta.evidence.owner_descriptor.owner_session_id,"actual_source_owner_id":get_instance_id()}
func _end_original_issued_claim_retirement(retirement: Dictionary) -> void:
	_issued_active_retirement={}
	var meta: Dictionary=retirement.get("__original_issued_claim__",{})
	if meta.is_empty(): return
	# Existing three-API acceptance is idempotent. For accepted entries Native
	# folds actual physical reply and this exact queue-removal observation into
	# maybeRetire; no independent ACK/get/status chain is created.
	var actual: Dictionary=accept_original_issued_claim_offer(meta.identity)
	if actual.get("state")=="TERMINAL": _issued_source_records.erase(IssuedClaimIdentity.key(meta.identity))

const IssuedClaimIdentity := preload("res://scripts/features/runtime/issued_claim_identity.gd")


# LIVE continuation metadata attaches to the ORIGINAL Coordinator/FIFOs. The
# original _retire_head/_apply_head remain the only scheduling cursors.
var _live_feature_owner: WeakRef
var _live_source_session: WeakRef
var _live_cleanup_context: Dictionary = {}
var _live_missing: Dictionary = {}
var _live_callback_manifest: Dictionary = {}
var _live_service_active := false
func actual_original_live_feature_bound() -> bool:
	return OS.get_thread_caller_id()==_thread and _live_feature_owner!=null and _live_feature_owner.get_ref()!=null and _live_source_session!=null and _live_source_session.get_ref()!=null
func configure_original_live_feature_owner(provider: RefCounted, session: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=_thread or _live_feature_owner!=null or provider==null or provider.owner_thread_id()!=_thread or session==null or session.owner_thread_id()!=_thread or not is_same(session.feature_resource_session().coordinator,self) or not is_same(session.original_frame_budget(),Budget) or not is_same(session.feature_resource_process_scope(),_process_scope): return {"success":false,"status":"INVALID","error":"actual_original_Feature_owner_binding"}
	# Nonempty module/code preparation still requires its original scene capture,
	# verification and publication CPS. Do not migrate a live scalar stack.
	if _quantum_active or not _jobs.is_empty() or not _work.is_empty() or _code_world_handoff_id!=0 or not _requests.is_empty() or not _applications.is_empty(): return {"success":false,"status":"MISSING","error":"actual_original_resource_or_code_job_CPS"}
	var manifest: Dictionary=session.actual_original_feature_callback_manifest()
	if manifest.get("captured")!=true or not manifest.get("scope_id") is int or manifest.scope_id<=0 or not manifest.get("lazy_birth_entry") is String or manifest.lazy_birth_entry.is_empty(): return {"success":false,"status":"INVALID","error":"actual_original_feature_callback_manifest"}
	var process_order: Dictionary=session.original_persistent_callback_order(get_instance_id(),&"original_process")
	if process_order.get("ok")!=true or not process_order.get("entry") is String or process_order.entry.is_empty(): return {"success":false,"status":"INVALID","error":"actual_original_Feature_process_entry"}
	_live_callback_manifest=manifest.duplicate(true); _live_callback_manifest.actual_process_entry=process_order.entry; _live_callback_manifest.make_read_only()
	_live_feature_owner=weakref(provider);_live_source_session=weakref(session)
	return {"success":true}
func abandon_unaccepted_original_live_feature_owner(provider: RefCounted) -> bool:
	if _live_feature_owner==null or not is_same(_live_feature_owner.get_ref(),provider) or not _live_cleanup_context.is_empty(): return false
	_live_feature_owner=null;_live_source_session=null;_live_callback_manifest={};return true
func _original_live_missing(error: String) -> void:
	_live_missing={"status":"MISSING","error":error,"original_retire_head":_retire_head,"original_apply_head":_apply_head}
func actual_original_live_feature_missing() -> Dictionary: return _live_missing.duplicate(true)
func _append_original_live_cleanup(operation: String, arguments: Array) -> bool:
	# This stable original FIFO entry accepts RESPONSIBILITY only. No physical
	# result or Native acceptance is claimed here; P will submit it later.
	_retirements[_retire_tail]={"__original_live_cleanup__":true,"operation":operation,"arguments":arguments.duplicate(true),"identity":{},"caller":{},"applied":false,"consumed":false}
	if not _completion_retirement_ids.is_empty(): _retirements[_retire_tail].__actual_completion_ids__=_completion_retirement_ids.duplicate()
	_retire_tail+=1;_activate();return true
func accept_original_live_reference_cleanup(descriptor: Dictionary) -> bool:
	if not actual_original_live_feature_bound() or not _primitives.accept_actual_original_reference_cleanup(descriptor): return false
	return _append_original_live_cleanup("release_reference",[descriptor])
func accept_original_live_retention_cleanup(publication_id: int, retention_id: int) -> bool:
	if not actual_original_live_feature_bound() or not _primitives.accept_actual_original_retention_cleanup(publication_id,retention_id): return false
	return _append_original_live_cleanup("release_retention",[publication_id,retention_id])
func actual_original_live_module_cancellation_supported() -> bool:
	return actual_original_live_feature_bound() and _code_world_handoff_id == 0
func cancel_original_live_module_requests() -> void:
	if not actual_original_live_module_cancellation_supported():
		_original_live_missing("actual_code_cancellation_and_resource_job_CPS");return
	for id: int in _requests.keys():
		if id==_applying_request: continue
		var result: Dictionary={"success":false,"errors":["feature_resource_preparation_cancelled"],"lease":null}
		if not _requests[id].live_state.is_empty(): _mark_actual_live_completion(_requests[id],result,true)
		elif _quantum_active: _deferred_completions.append({"id":id,"result":result})
		else: _complete(id,result)
	_activate()
func actual_original_live_feature_drained() -> bool:
	return actual_original_live_feature_bound() and _requests.is_empty() and _jobs.is_empty() and _work.is_empty() and _applications.is_empty() and _retirements.is_empty() and _deferred_completions.is_empty() and _code_world_handoff_id==0 and _issued_source_records.is_empty() and _live_cleanup_context.is_empty() and not _quantum_active and not _live_service_active and _primitives.actual_original_live_receipt_debt_free()
func _actual_original_live_P_site() -> Dictionary:
	var site: Dictionary=_primitives.current_original_source_site()
	if not actual_original_live_feature_bound() or _primitives.failed() or site.is_empty() or str(site.get("domain",""))!="P" or int(site.get("clock_epoch",-1))!=int(_live_source_session.get_ref().actual_original_clock_frame().get("epoch",-2)): return {}
	var frame: Dictionary=_live_source_session.get_ref().actual_original_clock_frame()
	if frame.get("closing_session")==true:
		if site.entry_id!="GameRoot.accepted_close_cleanup" or not _live_feature_owner.get_ref().actual_original_closing_feature_service_active(): return {}
	elif _live_source_session.get_ref().is_faulted() or site.entry_id!=_live_callback_manifest.actual_process_entry or not _process_scope.runtime_object_is_present() or not _process_scope.is_inside_world() or _process_scope.is_queued_for_retirement() or not _process_scope.can_process() or not _process_scope.process_enabled(): return {}
	return site
func capture_actual_original_live_feature_scope(caller: Dictionary) -> Dictionary:
	var site: Dictionary=_actual_original_live_P_site()
	if _live_cleanup_context.get("kind") in ["job","application","completion"]:
		if site.is_empty() or not _actual_live_cursor_matches(_live_cleanup_context.get("leaf",{}),caller): return {"success":false}
		var cleanup: bool = _live_cleanup_context.kind == "completion" or bool(_live_cleanup_context.leaf.get("cleanup",false))
		return {"success":true,"site":site,"caller":caller.duplicate(true),"actual_coordinator_id":get_instance_id(),"cleanup":cleanup,"lane":2 if cleanup else 0,"priority":2 if cleanup else 0}
	if site.is_empty() or _live_cleanup_context.is_empty() or _live_cleanup_context.get("caller")!=caller or _live_cleanup_context.get("original_entry_id")!=_retire_head or not _retirements.has(_retire_head): return {"success":false}
	var row: Dictionary=_retirements[_retire_head]
	var lane: int = 2
	if row.get("__threaded_claim__",false):
		var leaf: Dictionary = _live_cleanup_context.get("leaf",{})
		if leaf.is_empty() or not leaf.identity.is_empty() or not _original_live_claim_leaf_is_current(row,leaf,caller): return {"success":false}
		if leaf.operation == "status" and _live_source_session.get_ref().actual_original_clock_frame().get("closing_session") != true: lane = 0
	elif not row.get("__original_live_cleanup__",false) or row.caller!=caller or not _live_cleanup_context.get("leaf",{}).get("identity",{}).is_empty(): return {"success":false}
	return {"success":true,"site":site,"caller":caller.duplicate(true),"actual_coordinator_id":get_instance_id(),"cleanup":true,"lane":lane,"priority":lane}
func commit_original_live_feature_leaf_in_scope(caller: Dictionary, identity: Dictionary, reply: Dictionary) -> Dictionary:
	var site: Dictionary=_actual_original_live_P_site()
	if _live_cleanup_context.get("kind") in ["job","application","completion"]:
		return _commit_actual_live_job_leaf(site,caller,identity,reply)
	if site.is_empty() or not _live_service_active or not _quantum_active or int(Budget.snapshot().open_scopes)!=1 or _live_cleanup_context.get("caller")!=caller or _live_cleanup_context.get("original_entry_id")!=_retire_head or not _retirements.has(_retire_head): return {"success":false,"status":"INVALID","error":"actual_original_cleanup_scope"}
	var stack: Variant=Budget.get("_stack")
	if not stack is Array or stack.size()!=1 or stack[0].get("token")!=_live_cleanup_context.get("budget_token") or stack[0].get("category")!=CATEGORY: return {"success":false,"status":"INVALID","error":"actual_original_cleanup_budget_token"}
	var row: Dictionary=_retirements[_retire_head]
	if row.get("__threaded_claim__",false): return _commit_original_live_claim_leaf(row,_live_cleanup_context.get("leaf",{}),caller,identity,reply)
	if row.caller!=caller or _live_cleanup_context.get("leaf",{}).get("identity")!=identity or caller.get("actual_source_owner_id")!=get_instance_id() or caller.get("actual_process_scope_id")!=_process_scope.get_instance_id() or caller.get("original_scope_id")!=_live_callback_manifest.scope_id or caller.get("original_entry_id")!=_retire_head or not reply.get("request") is Dictionary or reply.request.get("op")!="feature."+row.operation or reply.request.get("args")!=row.arguments or reply.get("executed")!=true or reply.get("result")!=true: return {"success":false,"status":"INVALID","error":"actual_original_cleanup_identity_or_result"}
	var actual_frame: Dictionary=_live_source_session.get_ref().actual_original_clock_frame()
	if site.entry_id!=caller.original_source_entry and actual_frame.get("closing_session")!=true: return {"success":false,"status":"INVALID","error":"actual_original_P_entry_changed"}
	if row.applied: return {"success":true}
	var previous_attribution: Array=_completion_retirement_ids
	_completion_retirement_ids=row.get("__actual_completion_ids__",[])
	var imported: Dictionary=_primitives.import_actual_original_live_cleanup_side_facts(reply)
	_completion_retirement_ids=previous_attribution
	if imported.get("success")!=true:
		_original_live_missing(str(imported.get("error","actual_cleanup_side_facts")))
		return {"status":"PENDING","error":_live_missing.error}
	row.applied=true
	_live_cleanup_context.leaf.applied=true; _live_cleanup_context.leaf.side_facts_imported=true
	return {"success":true}
func _original_live_feature_process() -> void:
	if _actual_original_live_P_site().is_empty() or int(Budget.snapshot().open_scopes)!=0:
		_original_live_missing("actual_original_P_without_open_scalar_scope");return
	Budget.mark_pending(CATEGORY,true,true,false,_process_scope)
	var queue: int=-1
	for offset: int in range(3):
		var candidate: int=(_next_queue+offset)%3
		if (candidate==0 and _head<_tail) or (candidate==1 and _apply_head<_apply_tail) or (candidate==2 and _retire_head<_retire_tail):
			queue=candidate;_next_queue=(candidate+1)%3;break
	if queue==0: _actual_live_job_quantum()
	elif queue==1: _original_live_application_quantum()
	elif queue==2: _original_live_retirement_quantum()
	elif queue==-1: _service_one_original_issued_terminal()
	_activate()
func _original_live_application_quantum() -> void:
	var application: Dictionary=_applications[_apply_head]
	if application.has("kind"):
		_actual_live_application_quantum(application); return
	if not application.get("callback") is Callable:
		_original_live_missing("actual_original_local_application_callback");return
	var token: int=Budget.begin(CATEGORY)
	if token==0: return
	_quantum_active=true;_applications.erase(_apply_head);_apply_head+=1
	var finished: Array=[]
	if _requests.has(application.id):
		_applying_request=application.id
		var success: bool=application.callback.call() if application.callback.is_valid() else false
		_applying_request=0;finished.append({"id":application.id,"result":{"success":success,"errors":[],"lease":null}})
	Budget.end(token);_quantum_active=false
	_deliver_original_live_completions(finished)
func _deliver_original_live_completions(finished: Array) -> void:
	if _primitives.failed(): return
	var deliveries: Array=[]
	var cancelled: Array=_deferred_completions;_deferred_completions=[]
	for item: Dictionary in cancelled+finished:
		if _requests.has(item.id) and not _requests[item.id].live_state.is_empty(): _mark_actual_live_completion(_requests[item.id],item.result)
		else:
			var delivery: Dictionary=_take_completion(item.id,item.result)
			if not delivery.is_empty(): deliveries.append(delivery)
	for delivery: Dictionary in deliveries: delivery.request.completed.emit(delivery.result)
func _original_live_retirement_quantum() -> void:
	var row: Dictionary=_retirements[_retire_head]
	if bool(row.get("__threaded_claim__",false)):
		_original_live_threaded_claim_quantum(row);return
	if not bool(row.get("__original_live_cleanup__",false)):
		var local_token: int=Budget.begin(CATEGORY)
		if local_token==0: return
		# Original one-resource retirement. Last Source proxy PREDELETE appends its
		# exact descriptor to this SAME retirement FIFO, never a second queue.
		_quantum_active=true
		var previous_attribution: Array=_completion_retirement_ids
		_completion_retirement_ids=row.get("__actual_completion_ids__",[])
		var keys: Array=row.keys(); keys.erase("__actual_completion_ids__")
		if not keys.is_empty(): row.erase(keys[0]); keys.remove_at(0)
		if keys.is_empty(): _retirements.erase(_retire_head);_retire_head+=1
		_completion_retirement_ids=previous_attribution
		Budget.end(local_token);_quantum_active=false;return
	if not row.has("__live_leaf__"):
		var site: Dictionary = _actual_original_live_P_site()
		row.caller = {"contract_id":"hardcore.feature.original_cleanup_cursor.v1","actual_source_owner_id":get_instance_id(),"actual_process_scope_id":_process_scope.get_instance_id(),"original_scope_id":_live_callback_manifest.scope_id,"original_entry_id":_retire_head,"original_source_entry":site.entry_id,"original_responsibility_key":"retirement:%d"%_retire_head}
		row.__live_leaf__ = _new_original_live_leaf(row.operation,row.arguments,row.caller)
	var leaf: Dictionary = row.__live_leaf__
	var actual: Dictionary = advance_original_live_leaf(leaf)
	row.identity = leaf.identity; row.applied = leaf.applied; row.consumed = leaf.consumed
	if actual.get("status") == "VALUE":
		if not _primitives.complete_actual_original_live_cleanup(row.operation,row.arguments): _primitives._fault("actual_cleanup_receipt_metadata_retirement",row)
		else: _retirements.erase(_retire_head); _retire_head += 1
	elif actual.get("status") not in ["PENDING","BUSY","BACKPRESSURE"]: _original_live_missing("actual_cleanup_leaf:"+str(actual))
	_deliver_original_live_completions([])

# A leaf retains only the accepted transport association. The original row,
# queue cursor and business suffix remain this Coordinator's sole authority.
func advance_original_live_leaf(leaf: Dictionary, issued_row: Dictionary = {}) -> Dictionary:
	if leaf.get("retired",false): return {"status":"VALUE","reply":leaf.reply}
	var provider: RefCounted = _live_feature_owner.get_ref()
	if leaf.identity.is_empty():
		_live_cleanup_context = _actual_live_leaf_context(leaf)
		if not issued_row.is_empty(): _issued_active_retirement = issued_row
		var admitted: Dictionary = provider.submit_original_cleanup(leaf.caller,leaf.operation,leaf.arguments,leaf.dependencies)
		_issued_active_retirement = {}; _live_cleanup_context = {}
		if admitted.get("status") == "PENDING":
			leaf.identity = admitted.request.identity.duplicate(true)
			leaf.request = admitted.request.duplicate(true)
		elif admitted.get("status") not in ["BUSY","BACKPRESSURE"]: return {"status":"INVALID","error":"actual_original_leaf_admission","actual":admitted}
		return {"status":"PENDING"}
	var session: RefCounted = _live_source_session.get_ref()
	var owns_commit: bool = not session.actual_original_resource_commit_phase_active()
	if owns_commit and not session.begin_resource_commit_phase(int(session.original_source_session_clock().get_process_frames())): return {"status":"PENDING"}
	var settled: Dictionary = provider.settle_original_cleanup(leaf.identity)
	var result: Dictionary = {"status":"PENDING"}
	if settled.get("status") == "SETTLED":
		var token: int = Budget.begin(CATEGORY,true)
		if token != 0:
			_quantum_active = true
			_live_cleanup_context = _actual_live_leaf_context(leaf); _live_cleanup_context.budget_token = token
			var applied: Dictionary = provider.apply_original_cleanup(leaf.identity)
			_live_cleanup_context = {}; Budget.end(token); _quantum_active = false
			if applied.get("status") == "SETTLED":
				if not leaf.consumed:
					var consumed: Dictionary = provider.consume_original_cleanup(leaf.identity)
					if consumed.get("status") == "READY":
						leaf.reply = consumed.reply; leaf.consumed = true
					else: result = consumed
				if leaf.consumed and provider.retire_original_cleanup(leaf.identity):
					leaf.retired=true; result = {"status":"VALUE","reply":leaf.reply}
			elif applied.get("status") not in ["PENDING","BUSY"]: result = applied
	elif settled.get("status") not in ["PENDING","BUSY"]: result = settled
	if owns_commit and not session.finish_resource_commit_phase():
		session.fault("actual_Feature_leaf_commit_phase_close",{})
		return {"status":"INVALID"}
	return result

func _new_original_live_leaf(operation: String, arguments: Array, caller: Dictionary, dependencies: Array = []) -> Dictionary:
	return {"operation":operation,"arguments":arguments,"caller":caller,"dependencies":dependencies,"identity":{},"request":{},"side_facts_imported":false,"result_imported":false,"applied":false,"consumed":false,"reply":{}}

func _original_live_claim_leaf_is_current(row: Dictionary, leaf: Dictionary, caller: Dictionary) -> bool:
	if not row.get("__threaded_claim__",false) or not row.has("__original_issued_claim__") or not row.has("__live_claim_cps__") or not is_same(row.__live_claim_cps__.leaf,leaf): return false
	var meta: Dictionary = row.__original_issued_claim__
	return leaf.caller == caller and caller.get("contract_id") == "hardcore.feature.original_threaded_claim_cursor.v1" and caller.get("actual_source_owner_id") == get_instance_id() and caller.get("actual_process_scope_id") == _process_scope.get_instance_id() and caller.get("original_scope_id") == _live_callback_manifest.scope_id and caller.get("original_entry_id") == meta.original_entry_id and caller.get("issued_identity") == meta.identity and caller.get("first_claim_ordinal") == meta.claim_count-row.remaining and caller.get("remaining_count") == row.remaining and caller.get("operation") == leaf.operation

func _commit_original_live_claim_leaf(row: Dictionary, leaf: Dictionary, caller: Dictionary, identity: Dictionary, reply: Dictionary) -> Dictionary:
	if not _original_live_claim_leaf_is_current(row,leaf,caller) or leaf.identity != identity or reply.get("request") != leaf.request or reply.get("executed") != true: return {"success":false,"status":"INVALID","error":"actual_original_claim_cursor_or_reply"}
	var operation: String = leaf.operation
	var facts: Variant = reply.get("issued_claim_facts",[])
	if not facts is Array: return {"success":false,"status":"INVALID"}
	var terminal_count: int = 1 if operation == "get" else (int(row.remaining) if reply.get("result") == 0 else 0)
	if operation == "status":
		var observations: Variant = reply.get("native_observations")
		if not reply.get("result") is int or reply.result not in [0,1,2,3] or not observations is Array or observations.size() != 1 or not observations[0] is Dictionary or observations[0].get("ok") != true or observations[0].get("status") != reply.result or observations[0].get("bridge_generation") != _issued_bridge_generation: return {"success":false,"status":"INVALID","error":"actual_original_claim_status_observation"}
	elif operation != "get": return {"success":false,"status":"INVALID"}
	if facts.size() != (1 if terminal_count > 0 else 0): return {"success":false,"status":"INVALID","error":"actual_original_claim_terminal_fact_count"}
	if terminal_count > 0:
		var fact: Variant = facts[0]
		if not fact is Dictionary or fact.size() != 10 or fact.get("contract_id") != "hardcore.feature.issued_claim.physical_terminal.v1" or fact.get("identity") != caller.issued_identity or fact.get("original_first_claim_ordinal") != caller.first_claim_ordinal or fact.get("claim_count") != terminal_count or fact.get("kind") != ("GET" if operation == "get" else "INVALID_RESOURCE") or fact.get("path") != row.path or fact.get("operation_identity") != identity or fact.get("source_site") != reply.request.site: return {"success":false,"status":"INVALID","error":"actual_original_claim_exact_terminal_fact"}
	if not leaf.side_facts_imported:
		var imported: Dictionary = _primitives.import_actual_original_live_cleanup_side_facts(reply)
		if imported.get("success") != true: return imported
		leaf.side_facts_imported = true
	if operation == "get" and not leaf.result_imported:
		if not _primitives.consume_actual_live_discarded_resource(reply.get("result")): return {"success":false,"status":"INVALID","error":"actual_original_discarded_get_reference"}
		leaf.result_imported = true
	leaf.applied = true
	return {"success":true}

func _original_live_threaded_claim_quantum(row: Dictionary) -> void:
	if not row.has("__original_issued_claim__"):
		_original_live_missing("actual_nonissued_claim_origin_required"); return
	if not row.has("__live_claim_cps__"): row.__live_claim_cps__ = {"stage":"STATUS","leaf":{},"status_identity":{},"status_observation":{}}
	var cps: Dictionary = row.__live_claim_cps__
	for _attempt: int in range(2):
		if cps.leaf.is_empty():
			if not _begin_original_issued_claim_retirement(row): return
			_issued_active_retirement = {}
			var site: Dictionary = _actual_original_live_P_site()
			var meta: Dictionary = row.__original_issued_claim__
			var operation: String = "get" if cps.stage == "GET" else "status"
			var caller: Dictionary = {"contract_id":"hardcore.feature.original_threaded_claim_cursor.v1","actual_source_owner_id":get_instance_id(),"actual_process_scope_id":_process_scope.get_instance_id(),"original_scope_id":_live_callback_manifest.scope_id,"original_entry_id":meta.original_entry_id,"submitted_queue_location":_retire_head,"original_source_entry":site.entry_id,"original_responsibility_key":"issued:"+IssuedClaimIdentity.key(meta.identity),"issued_identity":meta.identity,"first_claim_ordinal":meta.claim_count-row.remaining,"remaining_count":row.remaining,"operation":operation}
			var dependencies: Array = [{"identity":cps.status_identity,"after":"s_committed"}] if operation == "get" else []
			cps.leaf = _new_original_live_leaf(operation,[row.path],caller,dependencies)
		var actual: Dictionary = advance_original_live_leaf(cps.leaf,row)
		if actual.get("status") != "VALUE":
			if actual.get("status") not in ["PENDING","BUSY","BACKPRESSURE"]: _original_live_missing("actual_original_claim_leaf:"+str(actual))
			else:
				# Transport waiting retains this exact ticket while using the same
				# original FIFO rotation; it never issues another status.
				_retirements.erase(_retire_head); _retire_head += 1; _retirement_requeue(row)
			return
		var operation: String = cps.leaf.operation
		var reply: Dictionary = actual.reply
		var token: int = Budget.begin(CATEGORY,true)
		if token == 0: return
		_quantum_active = true
		if operation == "status" and reply.result in [2,3]:
			cps.status_identity = reply.request.identity.duplicate(true)
			cps.status_observation = reply.native_observations[0].duplicate(true)
			cps.stage = "GET"; cps.leaf = {}
			Budget.end(token); _quantum_active = false
			continue # At most the second attempt may submit this necessary get.
		if operation == "get":
			_get_calls += 1; _threaded_claim_diagnostics.get += 1; row.remaining -= 1
		elif reply.result == 0:
			_threaded_claim_diagnostics.missing += row.remaining; row.remaining = 0
		_retirements.erase(_retire_head); _retire_head += 1
		if row.remaining > 0:
			cps.stage = "STATUS"; cps.leaf = {}; cps.status_identity = {}; cps.status_observation = {}
			_retirement_requeue(row)
		_end_original_issued_claim_retirement(row)
		Budget.end(token); _quantum_active = false
		return

func capture_original_issued_claim_live_leaf(identity: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != _thread: return {}
	for row: Dictionary in _retirements.values():
		if row.get("__original_issued_claim__",{}).get("identity") == identity:
			var leaf: Dictionary = row.get("__live_claim_cps__",{}).get("leaf",{})
			return leaf.get("request",{}).get("identity",{}).duplicate(true)
	return {}

# LIVE PCs belong to the original Request/job/application rows. The transport
# helper owns only a leaf ticket; neither a job nor its business suffix is replayed.
func _actual_live_call_context() -> Dictionary:
	var session: RefCounted = _live_source_session.get_ref() if _live_source_session != null else null
	return session.actual_original_feature_call_context() if session != null and session.has_method("actual_original_feature_call_context") else {}
func _await_actual_live_admission(admitted: Dictionary) -> Dictionary:
	if admitted.get("status") == "ACCEPTED": return await admitted.request.completed
	return admitted.get("result",{"success":false,"errors":[str(admitted.get("error","actual_Main_caller_context_required"))],"lease":null})
func _actual_command_context_valid(context: Dictionary) -> bool:
	if context.size()!=6 or context.get("contract_id")!="hardcore.feature.actual_Main_call.v1" or context.get("owner_session_id")!=_live_source_session.get_ref().original_budget_session_id(): return false
	for field: String in ["command_id","actual_main_process_frame","loan_id"]:
		if not context.get(field) is int or context[field] < (0 if field=="actual_main_process_frame" else 1): return false
	return context.get("scene") == null or context.scene is MainReference
func admit_actual_original_main_command(method: String, arguments: Array, actual_context: Dictionary) -> Dictionary:
	if not actual_original_live_feature_bound() or _primitives.failed() or not _actual_command_context_valid(actual_context): return {"status":"MISSING","error":"actual_original_Main_command_context"}
	var closing: bool = _live_source_session.get_ref().actual_original_clock_frame().get("closing_session",false)
	if method == "retire_resources" and arguments.size()==1 and arguments[0] is Dictionary:
		retire_resources(arguments[0]); return {"status":"VALUE","result":null}
	if method == "cancel_all" and arguments.is_empty(): cancel_original_live_module_requests(); return {"status":"VALUE","result":null}
	if method == "cancel_code_owner" and arguments.size()==2 and arguments[0] is RefCounted and arguments[1] is int:
		cancel_code_owner(arguments[0],arguments[1]); return {"status":"VALUE","result":null}
	if method == "retire_code_result" and arguments.size()==1 and arguments[0] is Dictionary:
		_retire_actual_live_code_result(arguments[0])
		return {"status":"VALUE","result":null}
	if closing: return {"status":"INVALID","error":"closing_Feature_new_preparation_forbidden"}
	var request: Request = Request.new()
	request.live_state={"pc":"","leaf":{},"context":actual_context.duplicate(false),"completion":{},"completion_queued":false,"cancel_scope":false,"release_wait":[]}
	if method == "prepare" and arguments.size()==2 and arguments[0] is Dictionary and arguments[1] is Array:
		var plan: Dictionary=Lease.requirements(arguments[0],arguments[1]); var declared: Dictionary=Registry.declarations()
		if not plan.get("success",false): return {"status":"VALUE","result":{"success":false,"errors":plan.get("errors",[]),"lease":null}}
		if not declared.get("success",false): return {"status":"VALUE","result":{"success":false,"errors":declared.get("errors",[]),"lease":null}}
		for path: String in plan.paths:
			if not declared.records.has(path): return {"status":"VALUE","result":{"success":false,"errors":["feature_resource_undeclared:"+path],"lease":null}}
		if plan.paths.is_empty(): return {"status":"VALUE","result":{"success":true,"errors":[],"lease":null}}
		if not actual_context.scene is MainReference: return {"status":"MISSING","error":"actual_original_prepare_scene_checkpoint"}
		request.plan=plan; request.scene_epoch=int(actual_context.scene.descriptor.object_id)
		_next_request+=1; var id: int=_next_request; request.live_state.id=id; _requests[id]=request
		for path: String in plan.paths:
			request.remaining[path]=true
			if not _jobs.has(path):
				_jobs[path]={"started":false,"clients":{},"delivering":false,"resource":null,"failure":"","mode":"","joined":false,"retained":false,"type":declared.records[path].type,"__live_cps__":{"pc":"CACHE","leaf":{},"request_identity":{},"status_identity":{},"original_id":id}}
				_queue(path)
			elif _jobs[path].get("kind") == "code_target":
				_mark_actual_live_completion(request,{"success":false,"errors":["feature_resource_job_mode_conflict"],"lease":null}); return {"status":"ACCEPTED","request":request}
			_jobs[path].clients[id]=true
		_activate(); return {"status":"ACCEPTED","request":request}
	if _requests.size()>=MAX_CODE_REQUESTS: return {"status":"VALUE","result":{"success":false,"errors":["code_preparation_owner_or_capacity"],"lease":null}}
	if method == "prepare_code_publication" and arguments.size()==8:
		if not arguments[0] is String or not arguments[1] is int or not arguments[2] is RefCounted or not arguments[3] is RefCounted or not arguments[4] is RefCounted or not arguments[5] is int or not arguments[6] is int or not arguments[7] is Dictionary: return {"status":"INVALID","error":"actual_code_publication_arguments"}
		request.kind="code_publication"; request.scope=arguments[3]; request.consumer=weakref(arguments[4]); request.generation=arguments[5]
		request.plan={"expected_sha256":arguments[0],"expected_bytes":arguments[1],"callback":arguments[2],"publisher_sequence":arguments[6],"export_contract":arguments[7]}
		request.live_state.pc="PUBLICATION_ADMIT"; request.diagnostics.merge({"image_bytes":0,"image_quanta":0})
	elif method == "prepare_code_inputs" and arguments.size()==6:
		if not arguments[0] is Dictionary or not arguments[1] is String or not arguments[2] is RefCounted or not arguments[3] is RefCounted or not arguments[4] is RefCounted or not arguments[5] is int: return {"status":"INVALID","error":"actual_code_inputs_arguments"}
		request.kind="code_inputs"; request.plan=arguments[0]; request.entry_id=arguments[1]; request.publisher=weakref(arguments[2]); request.scope=arguments[3]; request.consumer=weakref(arguments[4]); request.generation=arguments[5]
		request.live_state.pc="INPUTS_ADMIT"; request.diagnostics.merge({"verification_usec":0,"admission_usec":0,"inputs":[]})
	elif method == "request_code_script" and arguments.size()==3:
		var prepared: Variant=arguments[0]
		if not prepared is Dictionary or prepared.get("success")!=true or not prepared.get("plan") is RefCounted or not prepared.get("lease") is RefCounted or not prepared.get("scope") is RefCounted or not arguments[1] is RefCounted or not arguments[2] is int or prepared.get("generation")!=arguments[2]: return {"status":"VALUE","result":{"success":false,"errors":["code_target_prepared_value_shape"],"lease":null,"resource":null}}
		request.kind="code_target"; request.code_plan=prepared.plan; request.scope=prepared.scope; request.input_lease=prepared.lease; request.consumer=weakref(arguments[1]); request.generation=arguments[2]
		request.live_state.pc="TARGET_PATH"
	else: return {"status":"INVALID","error":"actual_original_command_method_or_arity"}
	_next_request+=1; request.live_state.id=_next_request; _requests[_next_request]=request
	_queue_code_step(_next_request,request.kind); _activate()
	return {"status":"ACCEPTED","request":request}

func _actual_live_leaf_context(leaf: Dictionary) -> Dictionary:
	return {"caller":leaf.caller,"original_entry_id":_retire_head,"leaf":leaf,"kind":leaf.get("original_owner_kind","retirement")}
func _actual_live_cursor_matches(leaf: Dictionary, caller: Dictionary) -> bool:
	if leaf.is_empty() or leaf.caller != caller or caller.get("actual_source_owner_id")!=get_instance_id() or caller.get("actual_process_scope_id")!=_process_scope.get_instance_id() or caller.get("original_scope_id")!=_live_callback_manifest.scope_id: return false
	if leaf.original_owner_kind == "job":
		var path: String=leaf.original_owner_path
		return _head<_tail and _work[_head]==path and _jobs.has(path) and is_same(_jobs[path].__live_cps__.leaf,leaf) and _jobs[path].__live_cps__.original_id==caller.original_entry_id and _jobs[path].__live_cps__.pc==caller.original_pc
	var id: int=leaf.original_owner_id
	return _apply_head<_apply_tail and _applications[_apply_head].id==id and _requests.has(id) and is_same(_requests[id].live_state.leaf,leaf) and _requests[id].live_state.pc==caller.original_pc
func _commit_actual_live_job_leaf(site: Dictionary, caller: Dictionary, identity: Dictionary, reply: Dictionary) -> Dictionary:
	var leaf: Dictionary=_live_cleanup_context.get("leaf",{})
	if site.is_empty() or not _live_service_active or not _quantum_active or not _actual_live_cursor_matches(leaf,caller) or leaf.identity!=identity or leaf.request!=reply.get("request") or reply.get("executed")!=true: return {"success":false,"status":"INVALID","error":"actual_original_job_cursor_or_reply"}
	var stack: Variant=Budget.get("_stack")
	if not stack is Array or stack.size()!=1 or stack[0].token!=_live_cleanup_context.get("budget_token") or stack[0].category!=CATEGORY: return {"success":false,"status":"INVALID","error":"actual_original_job_budget_token"}
	if leaf.applied: return {"success":true}
	var previous_applying: int=_applying_request
	if leaf.operation=="code_publication_apply": _applying_request=leaf.original_owner_id
	var imported: Dictionary=_primitives.import_actual_original_job_leaf(leaf.operation,leaf.arguments,reply)
	_applying_request=previous_applying
	if imported.get("success")!=true: return imported
	leaf.value=_primitives.decode_original_source_value(reply.get("result")); leaf.applied=true
	return {"success":true}
func _make_actual_live_job_leaf(state: Dictionary, operation: String, arguments: Array, kind: String, id: int, path: String="", dependencies: Array=[], cleanup: bool=false) -> void:
	var site: Dictionary=_actual_original_live_P_site()
	var caller: Dictionary={"contract_id":"hardcore.feature.original_job_cursor.v1","actual_source_owner_id":get_instance_id(),"actual_process_scope_id":_process_scope.get_instance_id(),"original_scope_id":_live_callback_manifest.scope_id,"original_entry_id":state.original_id if kind=="job" else id,"original_pc":state.pc,"original_source_entry":site.entry_id,"original_responsibility_key":"%s:%s:%d:%s"%[kind,path,id,state.pc]}
	state.leaf=_new_original_live_leaf(operation,_primitives.encode_original_source_value(arguments),caller,dependencies)
	state.leaf.merge({"original_owner_kind":kind,"original_owner_id":id,"original_owner_path":path,"cleanup":cleanup})
func _rotate_actual_live_work(path: String) -> void:
	_work.erase(_head); _head+=1
	if _jobs.has(path): _queue(path)
func _rotate_actual_live_application(application: Dictionary) -> void:
	_applications.erase(_apply_head); _apply_head+=1
	if _requests.has(application.id): _applications[_apply_tail]=application; _apply_tail+=1

func _actual_live_job_quantum() -> void:
	var path: String=_work[_head]
	if not _jobs.has(path): _work.erase(_head); _head+=1; return
	var job: Dictionary=_jobs[path]
	for _attempt: int in range(2):
		var state: Dictionary=job.__live_cps__
		if state.leaf.is_empty():
			var epoch: int=int(_actual_original_live_P_site().clock_epoch)
			if not state.get("owner_checked",false) and state.pc not in ["SCENE","TARGET_CHECK"] and not job.clients.is_empty():
				state.resume_pc=state.pc; state.check_epoch=epoch
				state.pc="TARGET_CHECK" if job.get("kind")=="code_target" else "SCENE"
				state.check_ids=job.clients.keys(); state.check_cursor=0
			var cleanup: bool=job.clients.is_empty() or _live_source_session.get_ref().actual_original_clock_frame().get("closing_session",false)
			var token: int=Budget.begin(CATEGORY,cleanup)
			if token==0: return
			_quantum_active=true
			_prepare_actual_live_job_instruction(path,job)
			Budget.end(token); _quantum_active=false
			if not _jobs.has(path) or state.leaf.is_empty(): break
		var actual: Dictionary=advance_original_live_leaf(state.leaf)
		if actual.get("status")!="VALUE":
			if actual.get("status") not in ["PENDING","BUSY","BACKPRESSURE"]: _original_live_missing("actual_job_leaf:"+str(actual))
			break
		var applied_token: int=Budget.begin(CATEGORY,true)
		if applied_token==0: break
		_quantum_active=true; _accept_actual_live_job_value(path,job,state.leaf.value,state.leaf.reply); state.leaf={}
		Budget.end(applied_token); _quantum_active=false
		if not _jobs.has(path): break
	_rotate_actual_live_work(path)
func _prepare_actual_live_job_instruction(path: String, job: Dictionary) -> void:
	var state: Dictionary=job.__live_cps__
	for id: int in job.clients.keys():
		if not _requests.has(id) or not _requests[id].live_state.completion.is_empty():
			if not state.has("completion_ids"): state.completion_ids=[]
			if id not in state.completion_ids: state.completion_ids.append(id)
			job.clients.erase(id)
	if job.clients.is_empty() and not job.started:
		_dispose_actual_live_job(path,job); return
	if state.pc=="DELIVER":
		_deliver_actual_live_job_client(path,job); return
	var operation: String; var args: Array; var dependencies: Array=[]
	match state.pc:
		"SCENE": operation="object_get"; args=[_primitives.tree(),"current_scene"]
		"TARGET_CHECK":
			while state.check_cursor<state.check_ids.size() and not job.clients.has(state.check_ids[state.check_cursor]): state.check_cursor+=1
			if state.check_cursor>=state.check_ids.size(): state.pc=state.resume_pc; state.owner_checked=true; return
			var checked: Request=_requests[state.check_ids[state.check_cursor]]
			operation="code_scope_check"; args=[checked.scope,checked.consumer.get_ref(),checked.generation]
		"CACHE": operation="get_cached_ref"; args=[path]
		"EXISTS": operation="exists"; args=[path,job.type]
		"PRE_STATUS": operation="status"; args=[path]
		"REQUEST": operation="request"; args=[path,job.type,false]
		"STATUS":
			operation="status"; args=[path]; dependencies=[{"identity":state.request_identity,"after":"s_committed"}]
		"GET":
			operation="get"; args=[path]; dependencies=[{"identity":state.request_identity,"after":"s_committed"},{"identity":state.status_identity,"after":"s_committed"}]
		"VALIDATE": operation="valid_resource"; args=[path,job.resource]
		"TARGET_ADMIT":
			var first: int=job.clients.keys()[0]; var request: Request=_requests[first]
			operation="code_target_admission"; args=[request.code_plan,request.scope,request.consumer.get_ref(),request.generation,request.input_lease,path]
		_: _original_live_missing("actual_job_pc:"+state.pc); return
	_make_actual_live_job_leaf(state,operation,args,"job",state.original_id,path,dependencies,job.clients.is_empty() and job.started)
func _accept_actual_live_job_value(path: String, job: Dictionary, value: Variant, reply: Dictionary) -> void:
	var state: Dictionary=job.__live_cps__
	if state.pc not in ["SCENE","TARGET_CHECK"]: state.owner_checked=false
	match state.pc:
		"SCENE":
			var scene_epoch: int=int(value.descriptor.object_id) if value is MainReference else 0
			for request: Request in _requests.values():
				if request.kind=="module" and request.scene_epoch!=0 and request.scene_epoch!=scene_epoch: _mark_actual_live_completion(request,{"success":false,"errors":["feature_resource_scene_changed"],"lease":null})
			state.pc=state.resume_pc; state.owner_checked=true
		"TARGET_CHECK":
			var checked_id: int=state.check_ids[state.check_cursor]
			if value!=true and _requests.has(checked_id): _mark_actual_live_completion(_requests[checked_id],{"success":false,"errors":["code_target_owner_expired"],"lease":null,"resource":null}); job.clients.erase(checked_id)
			state.check_cursor+=1
		"CACHE":
			if value!=null: job.resource=value; job.mode="cache_hits"; state.pc="VALIDATE"
			else: state.pc="EXISTS"
		"EXISTS":
			if value==true: state.pc="PRE_STATUS"
			else: job.failure="feature_resource_missing:"+path; state.pc="DELIVER"
		"PRE_STATUS": job.joined=value!=0; state.pc="REQUEST"
		"REQUEST":
			_request_calls+=1
			if value==OK: job.started=true; state.request_identity=reply.request.identity.duplicate(true); state.pc="STATUS"
			else: job.failure="feature_resource_request_failed:"+path; state.pc="DELIVER"
		"STATUS":
			if value in [2,3]: state.status_identity=reply.request.identity.duplicate(true); state.terminal_status=value; state.pc="GET"
			elif value==0: job.failure="feature_resource_load_failed:"+path; state.pc="DELIVER"
		"GET":
			_get_calls+=1
			if state.terminal_status==3: job.resource=value; job.mode="threaded_completed"; state.pc="DELIVER" if job.get("kind")=="code_target" else "VALIDATE"
			else:
				if value!=null: retire_resources({path:value})
				job.failure="feature_resource_load_failed:"+path; state.pc="DELIVER"
		"VALIDATE":
			if value!=true: job.failure="feature_resource_type_or_shape:"+path
			state.pc="DELIVER"
		"TARGET_ADMIT":
			if not value is Dictionary: _original_live_missing("actual_target_admission_shape"); return
			job.resource=value.get("resource"); job.mode=value.get("mode",""); job.started=value.get("started",false)
			job.admission_usec=value.get("admission_usec",0)
			if not value.get("success",false): job.failure=value.get("error","code_target_source_or_owner_changed"); state.pc="DELIVER"
			elif job.started: _request_calls+=1; state.request_identity=reply.request.identity.duplicate(true); state.pc="STATUS"
			else: state.pc="DELIVER"
func _deliver_actual_live_job_client(path: String, job: Dictionary) -> void:
	if job.clients.is_empty():
		_dispose_actual_live_job(path,job); return
	var id: int=job.clients.keys()[0]; job.clients.erase(id)
	if _requests.has(id):
		var request: Request=_requests[id]
		if not str(job.failure).is_empty(): _mark_actual_live_completion(request,{"success":false,"errors":[job.failure],"lease":null,"resource":null})
		elif request.kind=="code_target":
			request.diagnostics.admission_usec=job.get("admission_usec",0)
			request.live_state.target=job.resource; request.live_state.pc="TARGET_DELIVER"; request.live_state.waiting_job=false; job.retained=true; _queue_code_step(id,"code_target")
		else:
			request.resources[path]=job.resource; request.remaining.erase(path); job.retained=true
			request.diagnostics[job.mode]+=1; request.diagnostics.requested+=1 if job.started else 0; request.diagnostics.joined_requests+=1 if job.joined else 0
			if request.remaining.is_empty(): request.live_state.pc="MODULE_ISSUE"; _queue_code_step(id,"module_issue")
	if job.clients.is_empty():
		_dispose_actual_live_job(path,job)

func _dispose_actual_live_job(path: String, job: Dictionary) -> void:
	var previous: Array=_completion_retirement_ids
	_completion_retirement_ids=job.__live_cps__.get("completion_ids",[])
	if job.resource!=null and not job.retained: retire_resources({path:job.resource})
	_jobs.erase(path)
	_completion_retirement_ids=previous

func _actual_live_application_quantum(application: Dictionary) -> void:
	var id: int=application.id
	if not _requests.has(id): _applications.erase(_apply_head); _apply_head+=1; return
	var request: Request=_requests[id]
	if application.kind=="__live_completion__":
		_actual_live_completion_quantum(request)
		if _requests.has(id): _rotate_actual_live_application(application)
		else: _applications.erase(_apply_head); _apply_head+=1
		return
	if not request.live_state.completion.is_empty():
		# The accepted old leaf still owns its original PC. It must be obtained
		# before cleanup can discard the real result or close its file.
		if request.live_state.leaf.is_empty(): _applications.erase(_apply_head); _apply_head+=1; return
	for _attempt: int in range(2):
		if request.live_state.leaf.is_empty():
			var state: Dictionary=request.live_state
			var epoch: int=int(_actual_original_live_P_site().clock_epoch)
			if request.kind in ["code_inputs","code_target"] and not state.get("owner_checked",false) and state.pc not in ["OWNER_CHECK","INPUTS_ADMIT","TARGET_DELIVER"]:
				state.resume_pc=state.pc; state.pc="OWNER_CHECK"; state.check_epoch=epoch
			var token: int=Budget.begin(CATEGORY)
			if token==0: return
			_quantum_active=true; _prepare_actual_live_application_instruction(request)
			Budget.end(token); _quantum_active=false
			if request.live_state.leaf.is_empty(): break
		var actual: Dictionary=advance_original_live_leaf(request.live_state.leaf)
		if actual.get("status")!="VALUE":
			if actual.get("status") not in ["PENDING","BUSY","BACKPRESSURE"]: _original_live_missing("actual_application_leaf:"+str(actual))
			break
		var applied_token: int=Budget.begin(CATEGORY,true)
		if applied_token==0: break
		_quantum_active=true; _accept_actual_live_application_value(request,request.live_state.leaf.value,request.live_state.leaf.reply); request.live_state.leaf={}
		Budget.end(applied_token); _quantum_active=false
		# The job now owns the next business step. Do not admit a second
		# application leaf while it may advance this same Request to delivery.
		if not request.live_state.completion.is_empty() or request.live_state.get("waiting_job",false): break
	if request.live_state.leaf.is_empty() and (not request.live_state.completion.is_empty() or request.live_state.get("waiting_job",false)): _applications.erase(_apply_head); _apply_head+=1
	else: _rotate_actual_live_application(application)

func _prepare_actual_live_application_instruction(request: Request) -> void:
	var state: Dictionary=request.live_state; var id: int=state.id
	var operation: String; var args: Array
	var consumer: RefCounted=request.consumer.get_ref() if request.consumer!=null else null
	match state.pc:
		"OWNER_CHECK": operation="code_scope_check"; args=[request.scope,consumer,request.generation]
		"MODULE_ISSUE": operation="issue_resource_lease"; args=[request.plan,request.resources,self,request.diagnostics]
		"MODULE_RETAIN": operation="retain_publication"; args=[state.issued.resource_publication]
		"MODULE_PATH":
			if request.cursor>=request.plan.paths.size():
				var lease: RefCounted=_primitives.construct_actual_original_module_lease(request.plan,state.issued,state.retention,request.diagnostics)
				_mark_actual_live_completion(request,{"success":lease!=null,"errors":[] if lease!=null else ["feature_resource_lease_invalid"],"lease":lease,"resource_publication":state.issued.resource_publication,"diagnostics":request.diagnostics.duplicate(true)}); return
			operation="retention_supports_path"; args=[state.issued.resource_publication.publication_id,state.retention,request.plan.paths[request.cursor]]
		"INPUTS_ADMIT": operation="code_inputs_admit"; args=[request.plan,request.entry_id,request.publisher.get_ref(),request.scope,consumer,request.generation]
		"INPUTS_VERIFIED": operation="object_call"; args=[request.code_plan,"is_verified",[]]
		"INPUTS_VERIFY": operation="object_call"; args=[request.code_plan,"verify_next_source",[]]
		"INPUTS_PATHS": operation="object_call"; args=[request.code_plan,"paths",[]]
		"INPUTS_OWNER": operation="code_scope_check"; args=[request.scope,consumer,request.generation]
		"INPUTS_ACQUIRE":
			var path: String=state.paths[request.cursor]
			operation="acquire_shader"; args=[request.code_plan,request.scope,consumer,request.generation,path,_jobs.get(path,{})]
		"INPUTS_ISSUE": operation="issue_code_inputs"; args=[request.code_plan,request.resources,self,request.diagnostics]
		"INPUTS_LEASE_VALID": operation="object_call"; args=[state.main_lease,"valid_for_code",[request.code_plan]]
		"INPUTS_SIGNATURE": operation="object_call"; args=[request.code_plan,"signature",[]]
		"TARGET_PATH": operation="object_call"; args=[request.code_plan,"target_path",[]]
		"TARGET_SIGNATURE": operation="object_call"; args=[request.code_plan,"signature",[]]
		"TARGET_DELIVER": operation="code_target_deliver"; args=[request.code_plan,request.scope,consumer,request.generation,request.input_lease,state.target]
		"PUBLICATION_ADMIT": operation="code_publication_admit"; args=[request.plan.expected_sha256,request.plan.expected_bytes,request.plan.callback,request.scope,consumer,request.generation,request.plan.publisher_sequence,request.plan.export_contract]
		"PUBLICATION_OWNER": operation="code_publication_owner"; args=[request.publisher.get_ref(),request.scope,consumer,request.generation,request.plan.publisher_sequence]
		"PUBLICATION_OPEN": operation="open_image"; args=[OS.get_executable_path(),FileAccess.READ]
		"PUBLICATION_CHUNK": operation="code_image_chunk"; args=[request.image_file,request.plan.expected_bytes,IMAGE_CHUNK_BYTES]
		"PUBLICATION_CLOSE": operation="code_image_close"; args=[request.image_file]
		"PUBLICATION_EXPORT": operation="object_call"; args=[request.export_verifier,"step",[]]
		"PUBLICATION_APPLY":
			_applying_request=id
			var fact: Dictionary={"request_id":id,"kind":request.kind,"scope":request.scope,"consumer":consumer,"generation":request.generation,"image_sha256":request.image_sha256,"expected_sha256":request.plan.expected_sha256,"export_verifier":request.export_verifier}
			operation="code_publication_apply"; args=[request.plan.callback,fact,request.publisher.get_ref(),request.plan.publisher_sequence]
			_applying_request=0
		_: _original_live_missing("actual_application_pc:"+state.pc); return
	_make_actual_live_job_leaf(state,operation,args,"application",id)

func _accept_actual_live_application_value(request: Request, value: Variant, reply: Dictionary) -> void:
	var state: Dictionary=request.live_state; var id: int=state.id
	if state.pc!="OWNER_CHECK": state.owner_checked=false
	match state.pc:
		"OWNER_CHECK":
			if value!=true: _mark_actual_live_completion(request,{"success":false,"errors":["code_preparation_owner_expired"],"lease":null,"resource":null})
			else: state.pc=state.resume_pc; state.owner_checked=true
		"MODULE_ISSUE":
			if not value is Dictionary or value.get("main_lease")==null: _mark_actual_live_completion(request,{"success":false,"errors":["feature_resource_lease_invalid"],"lease":null}); return
			state.issued=value; state.pc="MODULE_RETAIN"
		"MODULE_RETAIN":
			if not value is Dictionary or value.get("success")!=true: _mark_actual_live_completion(request,{"success":false,"errors":["feature_resource_retention_invalid"],"lease":null}); return
			state.retention=value.retention_id; state.pc="MODULE_PATH"
		"MODULE_PATH":
			if value!=true: _mark_actual_live_completion(request,{"success":false,"errors":["feature_resource_retention_path_invalid"],"lease":null}); return
			request.cursor+=1
		"INPUTS_ADMIT":
			request.diagnostics.verification_usec+=int(reply.finished_usec)-int(reply.started_usec)
			if not value is Dictionary or value.get("success")!=true: _mark_actual_live_completion(request,{"success":false,"errors":value.get("errors",["code_preparation_failed"]) if value is Dictionary else ["code_preparation_failed"],"lease":null}); return
			request.code_plan=value.plan; state.pc="INPUTS_VERIFIED"
		"INPUTS_VERIFIED": state.pc="INPUTS_PATHS" if value==true else "INPUTS_VERIFY"
		"INPUTS_VERIFY":
			request.diagnostics.verification_usec+=int(reply.finished_usec)-int(reply.started_usec)
			if not value is Dictionary or value.get("success")!=true: _mark_actual_live_completion(request,{"success":false,"errors":value.get("errors",[]) if value is Dictionary else ["code_verify_failed"],"lease":null})
			else: state.pc="INPUTS_VERIFIED"
		"INPUTS_PATHS": state.paths=value; state.pc="INPUTS_OWNER"
		"INPUTS_OWNER":
			if value!=true: _mark_actual_live_completion(request,{"success":false,"errors":["code_preparation_owner_expired"],"lease":null})
			else: state.pc="INPUTS_ACQUIRE" if request.cursor<state.paths.size() else "INPUTS_ISSUE"
		"INPUTS_ACQUIRE":
			var path: String=state.paths[request.cursor]
			if value.get("resource")!=null: request.resources[path]=value.resource
			var diagnostic: Dictionary=value.duplicate(false); diagnostic.erase("resource"); diagnostic.path=path; request.diagnostics.inputs.append(diagnostic)
			if value.get("success")!=true: _mark_actual_live_completion(request,{"success":false,"errors":value.get("errors",[]),"lease":null})
			else: request.cursor+=1; state.pc="INPUTS_OWNER"
		"INPUTS_ISSUE":
			if value==null: _mark_actual_live_completion(request,{"success":false,"errors":["code_input_lease_invalid"],"lease":null})
			else: state.main_lease=value; state.pc="INPUTS_LEASE_VALID"
		"INPUTS_LEASE_VALID":
			if value!=true: _mark_actual_live_completion(request,{"success":false,"errors":["code_input_lease_invalid"],"lease":null})
			else: state.pc="INPUTS_SIGNATURE"
		"INPUTS_SIGNATURE":
			var lease: RefCounted=Lease.issue_code_inputs_domain_preaccepted(request.code_plan,state.main_lease,value,request.diagnostics)
			_mark_actual_live_completion(request,{"success":lease!=null,"errors":[] if lease!=null else ["code_input_lease_invalid"],"lease":lease,"plan":request.code_plan,"scope":request.scope,"entry_id":request.entry_id,"generation":request.generation,"diagnostics":request.diagnostics.duplicate(true)})
		"TARGET_PATH":
			state.path=value; state.pc="TARGET_SIGNATURE"
		"TARGET_SIGNATURE":
			var path: String=state.path
			if _jobs.has(path) and (_jobs[path].get("kind")!="code_target" or _jobs[path].plan_signature!=value): _mark_actual_live_completion(request,{"success":false,"errors":["code_target_job_mode_conflict"],"lease":null,"resource":null}); return
			if not _jobs.has(path):
				_jobs[path]={"kind":"code_target","started":false,"clients":{},"input_leases":{},"resource":null,"failure":"","mode":"","retained":false,"joined":false,"plan_signature":value,"__live_cps__":{"pc":"TARGET_ADMIT","leaf":{},"request_identity":{},"status_identity":{},"original_id":id}}
				_queue(path)
			_jobs[path].clients[id]=true; _jobs[path].input_leases[id]=request.input_lease; state.waiting_job=true
		"TARGET_DELIVER":
			if value==true and request.input_lease is Lease: request.input_lease._domain_code_resource=state.target
			_mark_actual_live_completion(request,{"success":value==true,"errors":[] if value==true else ["code_target_owner_or_type_invalid"],"resource":state.target if value==true else null,"lease":request.input_lease if value==true else null,"diagnostics":request.diagnostics.duplicate(true)})
		"PUBLICATION_ADMIT":
			if not value.get("success",false): _mark_actual_live_completion(request,{"success":false,"errors":value.get("errors",[]),"lease":null}); return
			request.publisher=weakref(value.publisher); request.export_verifier=value.export_verifier; state.pc="PUBLICATION_OWNER"
		"PUBLICATION_OWNER":
			if value!=true: _mark_actual_live_completion(request,{"success":false,"errors":["code_publication_owner_expired"],"lease":null})
			else: state.pc="PUBLICATION_EXPORT" if request.export_verifier!=null else ("PUBLICATION_OPEN" if request.image_file==null else "PUBLICATION_CHUNK")
		"PUBLICATION_OPEN":
			request.image_file=value; request.image_hash=HashingContext.new()
			if value==null or request.image_hash.start(HashingContext.HASH_SHA256)!=OK: _mark_actual_live_completion(request,{"success":false,"errors":["code_publication_native_image_size_or_hash_context"],"lease":null})
			else: state.pc="PUBLICATION_OWNER"
		"PUBLICATION_CHUNK":
			if not value.get("success",false): _mark_actual_live_completion(request,{"success":false,"errors":["code_publication_native_image_read_failed"],"lease":null}); return
			if value.done:
				request.image_sha256=request.image_hash.finish().hex_encode(); request.image_hash=null; state.pc="PUBLICATION_CLOSE"
			elif request.image_hash.update(value.bytes)!=OK: _mark_actual_live_completion(request,{"success":false,"errors":["code_publication_native_image_read_failed"],"lease":null})
			else: request.diagnostics.image_bytes+=value.bytes.size(); request.diagnostics.image_quanta+=1; state.pc="PUBLICATION_OWNER"
		"PUBLICATION_CLOSE":
			if request.image_file is MainReference: state.release_wait.append(request.image_file.descriptor)
			request.image_file=null
			if value!=true or request.image_sha256!=request.plan.expected_sha256: _mark_actual_live_completion(request,{"success":false,"errors":["code_publication_native_image_or_cover_changed"],"lease":null})
			else: state.pc="PUBLICATION_APPLY"
		"PUBLICATION_EXPORT":
			if not value.get("success",false): _mark_actual_live_completion(request,{"success":false,"errors":value.get("errors",[]),"lease":null})
			elif not value.get("done",false): state.pc="PUBLICATION_OWNER"
			else: request.diagnostics.native_token_device_acceptance="NOT_RUN"; state.pc="PUBLICATION_APPLY"
		"PUBLICATION_APPLY": _mark_actual_live_completion(request,{"success":value==true,"errors":[] if value==true else ["code_publication_callback_or_cover_failed"],"lease":null,"diagnostics":request.diagnostics.duplicate(true)})

func _mark_actual_live_completion(request: Request, result: Dictionary, cancel_scope: bool=false) -> void:
	var state: Dictionary=request.live_state
	if state.is_empty():
		_deferred_completions.append({"id":_applying_request,"result":result}); return
	if not state.completion.is_empty(): return
	state.completion=result; state.cancel_scope=cancel_scope and request.scope!=null
	if not state.completion_queued:
		state.completion_queued=true; _queue_code_step(state.id,"__live_completion__")
	_activate()
func _actual_live_completion_quantum(request: Request) -> void:
	var state: Dictionary=request.live_state
	# An accepted job/application leaf must finish at its original PC before
	# cleanup can repurpose the Request cursor or lose an acquired result.
	if not state.leaf.is_empty() and state.leaf.get("original_owner_kind")!="completion": return
	for job: Dictionary in _jobs.values():
		if state.id in job.__live_cps__.get("completion_ids",[]) and job.clients.is_empty(): return
		if job.clients.has(state.id) or job.get("input_leases",{}).has(state.id):
			if not job.__live_cps__.has("completion_ids"): job.__live_cps__.completion_ids=[]
			if state.id not in job.__live_cps__.completion_ids: job.__live_cps__.completion_ids.append(state.id)
			job.clients.erase(state.id)
			if not job.__live_cps__.leaf.is_empty() or (job.get("started",false) and job.__live_cps__.pc not in ["DELIVER"]): return
			job.get("input_leases",{}).erase(state.id)
	if not state.has("completion_started"):
		state.completion_started=true; state.pc="COMPLETE_CANCEL" if state.cancel_scope else "COMPLETE_CLOSE"
	if state.leaf.is_empty():
		var token: int=Budget.begin(CATEGORY,true)
		if token==0: return
		_quantum_active=true
		if state.pc=="COMPLETE_CANCEL": _make_actual_live_job_leaf(state,"code_scope_cancel",[request.scope],"completion",state.id,"",[],true)
		elif state.pc=="COMPLETE_CLOSE" and request.image_file!=null: _make_actual_live_job_leaf(state,"code_image_close",[request.image_file],"completion",state.id,"",[],true)
		else:
			if not state.has("resources_dropped"):
				state.resources_dropped=true; request.image_hash=null
				var previous_attribution: Array=_completion_retirement_ids
				_completion_retirement_ids=[state.id]
				var held: Array=state.release_wait
				for resource: Variant in request.resources.values():
					if resource is RefCounted and resource.has_method("is_valid"): held.append(resource.descriptor)
				if state.completion.get("success")!=true:
					if state.get("retention",0)>0 and state.get("issued",{}).has("resource_publication"):
						if not _live_feature_owner.get_ref().release_original_feature_retention(state.issued.resource_publication.publication_id,state.retention):
							state.cleanup_failed=true; _original_live_missing("actual_failed_retention_cleanup_not_accepted")
					if state.get("target") is RefCounted: held.append(state.target.descriptor); state.erase("target")
					if state.get("main_lease") is RefCounted: held.append(state.main_lease.descriptor); state.erase("main_lease")
					if state.get("issued",{}).get("main_lease") is RefCounted: held.append(state.issued.main_lease.descriptor); state.erase("issued")
					request.input_lease=null
				request.resources.clear(); state.release_wait=held
				_completion_retirement_ids=previous_attribution
			var pending: bool=state.get("cleanup_failed",false) or _has_actual_live_completion_debt(state.id)
			for descriptor: Dictionary in state.release_wait:
				if _primitives.actual_original_reference_release_pending(descriptor): pending=true
			if not pending:
				var result: Dictionary=state.completion
				_requests.erase(state.id)
				Budget.end(token); _quantum_active=false
				request.completed.emit(result); return
		Budget.end(token); _quantum_active=false
	if state.leaf.is_empty(): return
	var actual: Dictionary=advance_original_live_leaf(state.leaf)
	if actual.get("status")=="VALUE":
		if state.leaf.value!=true: _original_live_missing("actual_completion_cleanup_failed"); return
		if state.pc=="COMPLETE_CANCEL": state.pc="COMPLETE_CLOSE"
		else:
			if request.image_file is MainReference: state.release_wait.append(request.image_file.descriptor)
			request.image_file=null; state.pc="COMPLETE_DROP"
		state.leaf={}
	elif actual.get("status") not in ["PENDING","BUSY","BACKPRESSURE"]: _original_live_missing("actual_completion_leaf:"+str(actual))

func _has_actual_live_completion_debt(id: int) -> bool:
	for row: Dictionary in _retirements.values():
		if id in row.get("__actual_completion_ids__",[]): return true
	return false

var _issued_terminal_cursor := 0
func _service_one_original_issued_terminal() -> void:
	if _issued_source_records.is_empty(): return
	var keys: Array = _issued_source_records.keys()
	_issued_terminal_cursor %= keys.size()
	var meta: Dictionary = _issued_source_records[keys[_issued_terminal_cursor]]
	_issued_terminal_cursor += 1
	var queue: Dictionary = capture_original_issued_claim_queue_state(meta.identity)
	if queue.get("insertion") != "REMOVED": return
	var actual: Dictionary = accept_original_issued_claim_offer(meta.identity)
	if actual.get("state") == "TERMINAL": _issued_source_records.erase(IssuedClaimIdentity.key(meta.identity))
