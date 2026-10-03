extends Node

const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const CATEGORY := "feature_resources"

class Request extends RefCounted:
	signal completed(result: Dictionary)
	var plan: Dictionary
	var remaining: Dictionary = {}
	var resources: Dictionary = {}
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
var _applications: Dictionary = {}
var _apply_head := 0
var _apply_tail := 0
var _request_calls := 0
var _get_calls := 0
var _next_queue := 0
var _applying_request := 0
var _quantum_active := false
var _deferred_completions: Array = []

func _ready() -> void:
	set_process(false)

func prepare(catalog: Dictionary, enabled: Array) -> Dictionary:
	var plan := Lease.requirements(catalog, enabled)
	if not plan.success: return {"success":false, "errors":plan.errors, "lease":null}
	var declared := Registry.declarations()
	if not declared.success: return {"success":false, "errors":declared.errors, "lease":null}
	for path: String in plan.paths:
		if not declared.records.has(path): return {"success":false, "errors":["feature_resource_undeclared:" + path], "lease":null}
	if plan.paths.is_empty(): return {"success":true, "errors":[], "lease":null}
	_next_request += 1
	var id := _next_request
	var request := Request.new()
	request.plan = plan
	_requests[id] = request
	for path: String in plan.paths:
		request.remaining[path] = true
		if not _jobs.has(path):
			_jobs[path] = {"started":false, "clients":{}, "delivering":false,
				"resource":null, "failure":"", "mode":"", "joined":false, "retained":false, "type":declared.records[path].type}
			_queue(path)
		_jobs[path].clients[id] = true
	_activate()
	return await request.completed

func cancel_all() -> void:
	# Engine threaded requests cannot be cancelled. Their jobs remain owned
	# until status is terminal and any loaded resource is acquired and retired.
	for id: int in _requests.keys():
		if id == _applying_request: continue
		var result := {"success":false, "errors":["feature_resource_preparation_cancelled"], "lease":null}
		if _quantum_active: _deferred_completions.append({"id":id,"result":result})
		else: _complete(id,result)
	_activate()

func is_applying() -> bool:
	return _applying_request != 0

func apply_ready(callback: Callable) -> bool:
	if not callback.is_valid(): return false
	_next_request += 1
	var id := _next_request
	var request := Request.new()
	_requests[id] = request
	_applications[_apply_tail] = {"id":id, "callback":callback}
	_apply_tail += 1
	_activate()
	var result: Dictionary = await request.completed
	return bool(result.success)

func retire_resources(resources: Dictionary) -> void:
	if resources.is_empty(): return
	_retirements[_retire_tail] = resources.duplicate(false)
	_retire_tail += 1
	_activate()

func _activate() -> void:
	var pending := not _jobs.is_empty() or not _retirements.is_empty() or not _applications.is_empty()
	set_process(pending)
	Budget.mark_pending(CATEGORY, pending, true, false, self)

func _queue(path: String) -> void:
	_work[_tail] = path
	_tail += 1

func _process(_delta: float) -> void:
	Budget.mark_pending(CATEGORY, true, true, false, self)
	var token := Budget.begin(CATEGORY)
	if token == 0: return
	_quantum_active = true
	var finished: Array = []
	# Each nonempty class receives one opportunity in at most three granted
	# service quanta. Continuous loading cannot starve promotion or retirement.
	var queue := -1
	for offset in range(3):
		var candidate := (_next_queue + offset) % 3
		if (candidate == 0 and _head < _tail) or (candidate == 1 and _apply_head < _apply_tail) or (candidate == 2 and _retire_head < _retire_tail):
			queue = candidate
			_next_queue = (candidate + 1) % 3
			break
	if queue == 0:
		var path: String = _work[_head]
		_work.erase(_head)
		_head += 1
		_step(path, finished)
	elif queue == 1:
		var application: Dictionary = _applications[_apply_head]
		_applications.erase(_apply_head)
		_apply_head += 1
		if _requests.has(application.id):
			_applying_request = application.id
			var success: bool = application.callback.call() if application.callback.is_valid() else false
			_applying_request = 0
			finished.append({"id":application.id, "result":{"success":success, "errors":[], "lease":null}})
	elif queue == 2:
		var resources: Dictionary = _retirements[_retire_head]
		if not resources.is_empty(): resources.erase(resources.keys()[0])
		if resources.is_empty():
			_retirements.erase(_retire_head)
			_retire_head += 1
	Budget.end(token)
	_quantum_active = false
	# Completion may publish config and notify observers, always after the
	# optional preparation scope closes and never across an await.
	var cancelled := _deferred_completions
	_deferred_completions = []
	for item: Dictionary in cancelled: _complete(item.id,item.result)
	for item: Dictionary in finished: _complete(item.id, item.result)
	_activate()

func _step(path: String, finished: Array) -> void:
	if not _jobs.has(path): return
	var job: Dictionary = _jobs[path]
	if bool(job.delivering):
		_deliver_one(path, job, finished)
		return
	var resource: Resource = null
	var mode := ""
	var failure := ""
	if not bool(job.started):
		var first_client := -1
		for id: int in job.clients:
			first_client = id
			break
		if first_client < 0:
			_jobs.erase(path)
			return
		if not _requests.has(first_client):
			job.clients.erase(first_client)
			_queue(path)
			return
		resource = ResourceLoader.get_cached_ref(path)
		if resource != null:
			mode = "cache_hits"
		elif not ResourceLoader.exists(path, job.type):
			failure = "feature_resource_missing:" + path
		else:
			var status := ResourceLoader.load_threaded_get_status(path)
			# A matching engine task still requires this owner's own user token.
			# Merely observing another owner's status and calling get would spend
			# its retrieval right. ResourceLoader joins the existing task itself.
			var error := ResourceLoader.load_threaded_request(path, job.type, false)
			_request_calls += 1
			if error != OK: failure = "feature_resource_request_failed:" + path
			else:
				job.joined = status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
			job.started = true
			if failure.is_empty():
				_queue(path)
				return # Request and completed retrieval are separate quanta.
	if failure.is_empty() and resource == null:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			resource = ResourceLoader.load_threaded_get(path)
			_get_calls += 1
			mode = "threaded_completed"
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			# FAILED is terminal too; get cannot wait and releases our user token.
			ResourceLoader.load_threaded_get(path)
			_get_calls += 1
			failure = "feature_resource_load_failed:" + path
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			failure = "feature_resource_load_failed:" + path
		else:
			_queue(path)
			return
	if failure.is_empty() and not Registry.valid_resource(path, resource):
		failure = "feature_resource_type_or_shape:" + path
	job.resource = resource
	job.failure = failure
	job.mode = mode
	job.delivering = true
	_queue(path)

func _deliver_one(path: String, job: Dictionary, finished: Array) -> void:
	# The engine task is shared; its participants still receive independent
	# validation/leases in separate ordinary quanta rather than one frame burst.
	var next_id := -1
	for id: int in job.clients:
		next_id = id
		break
	if next_id >= 0:
		job.clients.erase(next_id)
		if _requests.has(next_id):
			var request: Request = _requests[next_id]
			if not String(job.failure).is_empty():
				finished.append({"id":next_id, "result":{"success":false, "errors":[job.failure], "lease":null}})
			else:
				request.resources[path] = job.resource
				request.remaining.erase(path)
				request.diagnostics[job.mode] += 1
				request.diagnostics.requested += 1 if job.started else 0
				request.diagnostics.joined_requests += 1 if job.joined else 0
				job.retained = true
				if request.remaining.is_empty():
					var lease := Lease.issue(request.plan, request.resources, self, request.diagnostics)
					finished.append({"id":next_id, "result":{"success":lease != null, "errors":[] if lease != null else ["feature_resource_lease_invalid"], "lease":lease}})
	if job.clients.is_empty():
		_jobs.erase(path)
		if job.resource != null and not bool(job.retained): retire_resources({path:job.resource})
	else:
		_queue(path)

func _complete(id: int, result: Dictionary) -> void:
	if not _requests.has(id): return
	var request: Request = _requests[id]
	_requests.erase(id)
	if not bool(result.success): retire_resources(request.resources)
	request.completed.emit(result)

func pending_count() -> int:
	return _jobs.size() + _retirements.size() + _applications.size()

func metrics() -> Dictionary:
	# Physical calls are service-wide. Per-lease participation diagnostics
	# describe shared jobs and must not be added across participating leases.
	return {"request_calls":_request_calls, "get_calls":_get_calls, "jobs":_jobs.size(), "applications":_applications.size(), "retirements":_retirements.size()}
