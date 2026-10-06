extends Node

const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
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
	var image_file: FileAccess
	var image_hash: HashingContext
	var image_sha256 := ""
	var generation := -1
	var entry_id := ""
	var cursor := 0
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
	# Scene-change immediate failure (S3): the request belongs to the scene
	# that started it; a later scene invalidates it before any promotion.
	var owner_scene: Node = get_tree().current_scene
	request.scene_epoch = owner_scene.get_instance_id() if owner_scene != null else 0
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
	_retire_code_world_handoff()
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
	var code_phase := ""
	var code_began := Time.get_ticks_usec()
	var finished: Array = []
	# Scene-change immediate failure: the first service quantum that observes a
	# different current scene fails every outstanding module preparation right
	# away. Code-publication/handoff requests keep their own cross-scene
	# retention contract and are deliberately untouched here.
	var successor: Node = get_tree().current_scene
	var scene_epoch := successor.get_instance_id() if successor != null else 0
	for stale_id: int in _requests.keys():
		var stale_request: Request = _requests[stale_id]
		if stale_request.kind != "module" or stale_id == _applying_request: continue
		if stale_request.scene_epoch != 0 and scene_epoch != stale_request.scene_epoch:
			_deferred_completions.append({"id":stale_id, "result":{"success":false,
				"errors":["feature_resource_scene_changed"], "lease":null}})
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
		if _jobs.has(path) and _jobs[path].get("kind") == "code_target":
			code_phase = "code_target"
		_step(path, finished)
	elif queue == 1:
		var application: Dictionary = _applications[_apply_head]
		_applications.erase(_apply_head)
		_apply_head += 1
		if application.get("kind") == "code_publication":
			code_phase = "code_publication"
			_step_code_publication(application.id, finished)
		elif application.get("kind") == "code_retention_handoff":
			code_phase = "code_retention_handoff"
			_step_code_world_handoff(application.id)
		elif application.get("kind") == "code_inputs":
			code_phase = "code_inputs"
			_step_code_inputs(application.id, finished)
		elif _requests.has(application.id):
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
	_record_code_quantum(code_phase, Time.get_ticks_usec() - code_began)
	Budget.end(token)
	_quantum_active = false
	# Completion may publish config and notify observers, always after the
	# optional preparation scope closes and never across an await.
	var cancelled := _deferred_completions
	_deferred_completions = []
	# Resolve every terminal owner before notifying any waiter. A cancelled
	# waiter's synchronous continuation can cancel again, but cannot relabel
	# another result which already crossed its commit/readiness boundary.
	var deliveries: Array = []
	for item: Dictionary in cancelled + finished:
		var delivery := _take_completion(item.id,item.result)
		if not delivery.is_empty(): deliveries.append(delivery)
	for delivery: Dictionary in deliveries: delivery.request.completed.emit(delivery.result)
	_activate()

func _step(path: String, finished: Array) -> void:
	if not _jobs.has(path): return
	var job: Dictionary = _jobs[path]
	if job.get("kind") == "code_target":
		_step_code_target(path, job, finished)
		return
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

func _take_completion(id: int, result: Dictionary) -> Dictionary:
	if not _requests.has(id): return {}
	var request: Request = _requests[id]
	_requests.erase(id)
	if request.image_file != null:
		request.image_file.close()
		request.image_file = null
	request.image_hash = null
	if not bool(result.success): retire_resources(request.resources)
	return {"request":request,"result":result}

func _complete(id: int, result: Dictionary) -> void:
	var delivery := _take_completion(id,result)
	if not delivery.is_empty(): delivery.request.completed.emit(delivery.result)

func pending_count() -> int:
	return _jobs.size() + _retirements.size() + _applications.size()

func metrics() -> Dictionary:
	# Physical calls are service-wide. Per-lease participation diagnostics
	# describe shared jobs and must not be added across participating leases.
	return {"request_calls":_request_calls, "get_calls":_get_calls, "jobs":_jobs.size(), "applications":_applications.size(), "retirements":_retirements.size()}


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
	return _code_phase_metrics.duplicate(true)

func _record_code_quantum(phase: String, elapsed_usec: int) -> void:
	if phase.is_empty():
		return
	if not _code_phase_metrics.has(phase):
		_code_phase_metrics[phase] = {"quanta": 0, "total_usec": 0, "worst_usec": 0}
	var record: Dictionary = _code_phase_metrics[phase]
	record.quanta += 1
	record.total_usec += elapsed_usec
	record.worst_usec = maxi(record.worst_usec, elapsed_usec)

func _queue_code_step(id: int, kind := "code_inputs") -> void:
	_applications[_apply_tail] = {"id": id, "kind": kind}
	_apply_tail += 1
	_activate()

func prepare_code_publication(expected_sha256: String, expected_bytes: int, callback: Callable, scope: RefCounted, consumer: Node, generation: int, publisher_sequence: int, export_contract: Dictionary = {}) -> Dictionary:
	var publisher: Node = get_tree().root.get_node_or_null("ContentLayers")
	if not is_instance_valid(publisher) or not publisher.has_method("is_internal_code_publication_boundary_current") or not bool(publisher.is_internal_code_publication_boundary_current(publisher_sequence)) or callback.get_object() != publisher or callback.get_method() != "_publish_internal_code_catalogue" or scope == null or not is_same(scope.get_script(), CodeScope) or not is_instance_valid(consumer) or not bool(scope.valid_for(consumer, generation)) or expected_sha256.length() != 64 or expected_bytes <= 0 or expected_bytes > MAX_IMAGE_BYTES or _requests.size() >= MAX_CODE_REQUESTS:
		return {"success": false, "errors": ["code_publication_owner_shape_or_loading_scope"], "lease": null}
	_next_request += 1
	var id := _next_request
	var request := Request.new()
	request.kind = "code_publication"
	request.scope = scope
	request.consumer = weakref(consumer)
	request.publisher = weakref(publisher)
	request.generation = generation
	request.plan = {"expected_sha256": expected_sha256, "expected_bytes": expected_bytes, "callback": callback, "publisher_sequence": publisher_sequence}
	if OS.get_name() == "Android":
		if not publisher.has_method("code_preparation_export_contract") or not publisher.has_method("code_preparation_export_seal_sha256") or publisher.code_preparation_export_contract() != export_contract or publisher.code_preparation_export_seal_sha256() != expected_sha256:
			return {"success": false, "errors": ["android_unregistered_export_contract"], "lease": null}
		request.export_verifier = AndroidVerifier.begin(export_contract, expected_sha256, true)
		if request.export_verifier == null: return {"success": false, "errors": ["android_publication_contract_rejected"], "lease": null}
	elif OS.get_name() != "Windows" or not export_contract.is_empty():
		return {"success": false, "errors": ["code_publication_platform_unknown"], "lease": null}
	request.diagnostics["image_bytes"] = 0
	request.diagnostics["image_quanta"] = 0
	_requests[id] = request
	_queue_code_step(id, "code_publication")
	return await request.completed

func code_publication_image_current(scope: RefCounted, consumer: Node, generation: int, expected_sha256: String) -> bool:
	if not _requests.has(_applying_request):
		return false
	var request: Request = _requests[_applying_request]
	return request.kind == "code_publication" and request.export_verifier == null and is_same(request.scope, scope) and is_same(request.consumer.get_ref(), consumer) and request.generation == generation and request.image_sha256 == expected_sha256 and request.plan.expected_sha256 == expected_sha256 and _code_owner_current(request)

func code_publication_export_current(scope: RefCounted, consumer: Node, generation: int, seal_sha256: String) -> bool:
	if not _requests.has(_applying_request): return false
	var request: Request = _requests[_applying_request]
	return request.kind == "code_publication" and request.export_verifier != null and bool(request.export_verifier.is_verified()) and is_same(request.scope, scope) and is_same(request.consumer.get_ref(), consumer) and request.generation == generation and request.plan.expected_sha256 == seal_sha256 and _code_owner_current(request)

func _step_export_publication(id: int, request: Request, finished: Array) -> void:
	var checked: Dictionary = request.export_verifier.step()
	if not checked.success:
		finished.append({"id": id, "result": {"success": false, "errors": checked.errors, "lease": null}})
		return
	if not checked.done:
		_queue_code_step(id, "code_publication")
		return
	request.diagnostics["runtime_native_image_sha"] = "MISSING"
	request.diagnostics["build_verified_native_sha"] = request.publisher.get_ref().code_preparation_export_contract().build_verified_native_sha
	request.diagnostics["native_token_device_acceptance"] = "NOT_RUN"
	_applying_request = id
	var callback: Callable = request.plan.callback
	var success: bool = callback.call() if callback.is_valid() else false
	_applying_request = 0
	success = success and _code_owner_current(request)
	finished.append({"id": id, "result": {"success": success, "errors": [] if success else ["android_publication_callback_or_cover_failed"], "lease": null, "diagnostics": request.diagnostics.duplicate(true)}})

func _step_code_publication(id: int, finished: Array) -> void:
	if not _requests.has(id):
		return
	var request: Request = _requests[id]
	var publisher: Node = request.publisher.get_ref() if request.publisher != null else null
	if not _code_owner_current(request) or not is_instance_valid(publisher) or not is_same(get_tree().root.get_node_or_null("ContentLayers"), publisher) or not bool(publisher.is_internal_code_publication_boundary_current(request.plan.publisher_sequence)):
		finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_owner_expired"], "lease": null}})
		return
	if request.export_verifier != null:
		_step_export_publication(id, request, finished)
		return
	if request.image_file == null:
		request.image_file = FileAccess.open(OS.get_executable_path(), FileAccess.READ)
		request.image_hash = HashingContext.new()
		if request.image_file == null or request.image_file.get_length() != request.plan.expected_bytes or request.image_hash.start(HashingContext.HASH_SHA256) != OK:
			finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_native_image_size_or_hash_context"], "lease": null}})
			return
	var remaining := request.image_file.get_length() - request.image_file.get_position()
	if remaining > 0:
		var bytes: PackedByteArray = request.image_file.get_buffer(mini(IMAGE_CHUNK_BYTES, remaining))
		if bytes.size() != mini(IMAGE_CHUNK_BYTES, remaining) or request.image_hash.update(bytes) != OK:
			finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_native_image_read_failed"], "lease": null}})
			return
		request.diagnostics.image_bytes += bytes.size()
		request.diagnostics.image_quanta += 1
		_queue_code_step(id, "code_publication")
		return
	request.image_sha256 = request.image_hash.finish().hex_encode()
	request.image_hash = null
	request.image_file.close()
	request.image_file = null
	if request.image_sha256 != request.plan.expected_sha256 or not _code_owner_current(request):
		finished.append({"id": id, "result": {"success": false, "errors": ["code_publication_native_image_or_cover_changed"], "lease": null}})
		return
	_applying_request = id
	var callback: Callable = request.plan.callback
	var success: bool = callback.call() if callback.is_valid() else false
	_applying_request = 0
	success = success and _code_owner_current(request)
	finished.append({"id": id, "result": {"success": success, "errors": [] if success else ["code_publication_callback_or_cover_failed"], "lease": null, "diagnostics": request.diagnostics.duplicate(true)}})

func prepare_code_inputs(payload: Dictionary, entry_id: String, publisher: Node, scope: RefCounted, consumer: Node, generation: int) -> Dictionary:
	if not is_instance_valid(consumer) or not is_instance_valid(publisher) or scope == null or not is_same(scope.get_script(), CodeScope) or not bool(scope.valid_for(consumer, generation)) or _requests.size() >= MAX_CODE_REQUESTS:
		return {"success": false, "errors": ["code_preparation_owner_or_capacity"], "lease": null}
	_next_request += 1
	var id := _next_request
	var request := Request.new()
	request.kind = "code_inputs"
	request.plan = payload
	request.entry_id = entry_id
	request.publisher = weakref(publisher)
	request.scope = scope
	request.consumer = weakref(consumer)
	request.generation = generation
	request.diagnostics["verification_usec"] = 0
	request.diagnostics["admission_usec"] = 0
	request.diagnostics["inputs"] = []
	_requests[id] = request
	_queue_code_step(id)
	return await request.completed

func _code_owner_current(request: Request) -> bool:
	var consumer: Node = request.consumer.get_ref() if request.consumer != null else null
	return is_instance_valid(consumer) and request.scope != null and bool(request.scope.valid_for(consumer, request.generation))

func _step_code_inputs(id: int, finished: Array) -> void:
	if not _requests.has(id):
		return
	var request: Request = _requests[id]
	if not _code_owner_current(request):
		finished.append({"id": id, "result": {"success": false, "errors": ["code_preparation_owner_expired"], "lease": null}})
		return
	var consumer: Node = request.consumer.get_ref()
	if request.code_plan == null:
		var began := Time.get_ticks_usec()
		var publisher: Node = request.publisher.get_ref()
		var checked: Dictionary = CodeGuard.begin_verification(request.plan, request.entry_id, publisher, consumer)
		request.diagnostics.verification_usec += Time.get_ticks_usec() - began
		if not checked.success:
			finished.append({"id": id, "result": {"success": false, "errors": checked.errors, "lease": null}})
			return
		request.code_plan = checked.plan
		_queue_code_step(id)
		return
	if not bool(request.code_plan.is_verified()):
		var began := Time.get_ticks_usec()
		var checked: Dictionary = request.code_plan.verify_next_source()
		request.diagnostics.verification_usec += Time.get_ticks_usec() - began
		if not checked.success:
			finished.append({"id": id, "result": {"success": false, "errors": checked.errors, "lease": null}})
		else:
			_queue_code_step(id)
		return
	var paths: Array = request.code_plan.paths()
	if request.cursor < paths.size():
		var path: String = paths[request.cursor]
		request.cursor += 1
		var acquired: Dictionary = CodeAcquire.acquire_shader(request.code_plan, request.scope, consumer, request.generation, path, _jobs.get(path, {}))
		# Failure may already own a Resource. Original _take_completion submits
		# request.resources to this same retirement queue; never drop it here.
		if acquired.resource != null:
			request.resources[path] = acquired.resource
		var diagnostic := acquired.duplicate(false)
		diagnostic.erase("resource")
		diagnostic["path"] = path
		request.diagnostics.inputs.append(diagnostic)
		if not acquired.success:
			finished.append({"id": id, "result": {"success": false, "errors": acquired.errors, "lease": null}})
		else:
			_queue_code_step(id)
		return
	var lease: RefCounted = Lease.issue_code_inputs(request.code_plan, request.resources, self, request.diagnostics)
	finished.append({"id": id, "result": {"success": lease != null, "errors": [] if lease != null else ["code_input_lease_invalid"], "lease": lease,
		"plan": request.code_plan, "scope": request.scope, "entry_id": request.entry_id, "generation": request.generation, "diagnostics": request.diagnostics.duplicate(true)}})

func request_code_script(prepared: Dictionary, consumer: Node, generation: int) -> Dictionary:
	var plan_value: Variant = prepared.get("plan")
	var lease_value: Variant = prepared.get("lease")
	var scope_value: Variant = prepared.get("scope")
	if not plan_value is RefCounted or not lease_value is RefCounted or not scope_value is RefCounted:
		return {"success": false, "errors": ["code_target_prepared_value_shape"], "resource": null, "lease": null}
	var plan: RefCounted = plan_value
	var lease: RefCounted = lease_value
	var scope: RefCounted = scope_value
	if not is_same(plan.get_script(), CodeGuard) or not is_same(lease.get_script(), Lease) or not is_same(scope.get_script(), CodeScope):
		return {"success": false, "errors": ["code_target_prepared_contract_identity"], "resource": null, "lease": null}
	# File/source and lease verification happens in _step_code_target's charged
	# quantum; this public entry performs only shape/owner admission.
	if not bool(prepared.get("success", false)) or not is_instance_valid(consumer) or generation != prepared.get("generation") or not bool(scope.valid_for(consumer, generation)) or _requests.size() >= MAX_CODE_REQUESTS:
		return {"success": false, "errors": ["code_target_preparation_or_owner_invalid"], "resource": null, "lease": null}
	var path: String = plan.target_path()
	_next_request += 1
	var id := _next_request
	var request := Request.new()
	request.kind = "code_target"
	request.code_plan = plan
	request.scope = scope
	request.consumer = weakref(consumer)
	request.generation = generation
	request.input_lease = lease
	_requests[id] = request
	if _jobs.has(path):
		if _jobs[path].get("kind") != "code_target" or _jobs[path].get("plan_signature") != plan.signature():
			_requests.erase(id)
			return {"success": false, "errors": ["code_target_job_mode_conflict"], "resource": null, "lease": null}
	else:
		_jobs[path] = {"kind": "code_target", "started": false, "clients": {}, "input_leases": {}, "delivering": false, "resource": null, "failure": "", "mode": "", "retained": false, "plan_signature": plan.signature()}
		_queue(path)
	_jobs[path].clients[id] = true
	_jobs[path].input_leases[id] = lease
	_activate()
	return await request.completed

func _step_code_target(path: String, job: Dictionary, finished: Array) -> void:
	# Cancellation cannot retire input leases until the physical get is done.
	for id: int in job.clients.keys():
		if _requests.has(id) and not _code_owner_current(_requests[id]):
			finished.append({"id": id, "result": {"success": false, "errors": ["code_target_owner_expired"], "resource": null, "lease": null}})
			job.clients.erase(id)
	var resource: Resource = job.resource
	if not bool(job.started) and not bool(job.delivering):
		var next_id := -1
		for id: int in job.clients:
			if _requests.has(id):
				next_id = id
				break
		if next_id < 0:
			_jobs.erase(path)
			job.input_leases.clear()
			return
		var request: Request = _requests[next_id]
		var began := Time.get_ticks_usec()
		var current: Dictionary = request.code_plan.revalidate_admission_sources()
		if not current.success or not _code_owner_current(request) or not bool(request.input_lease.valid_for_code(request.code_plan)):
			request.diagnostics["admission_usec"] = Time.get_ticks_usec() - began
			job.failure = "code_target_source_or_owner_changed"
			job.delivering = true
		else:
			request.diagnostics["admission_usec"] = Time.get_ticks_usec() - began
			resource = ResourceLoader.get_cached_ref(path)
			if resource != null:
				job.mode = "cache_hits"
				job.resource = resource
				job.delivering = true
			elif ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				job.failure = "code_target_external_native_job_unproved"
				job.delivering = true
			else:
				# No await/callback between fresh bounded source admission and the
				# real request. Same _jobs owner owns this one accepted user token.
				var error := ResourceLoader.load_threaded_request(path, "Script", false)
				_request_calls += 1
				if error == OK:
					job.started = true
				else:
					job.failure = "code_target_request_failed:" + path
					job.delivering = true
		_queue(path)
		return
	if not bool(job.delivering):
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			job.resource = ResourceLoader.load_threaded_get(path)
			_get_calls += 1
			job.mode = "threaded_completed"
			job.delivering = true
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(path)
			_get_calls += 1
			job.failure = "code_target_load_failed:" + path
			job.delivering = true
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			job.failure = "code_target_invalid_without_phantom_get:" + path
			job.delivering = true
		_queue(path)
		return
	var next_id := -1
	for id: int in job.clients:
		next_id = id
		break
	if next_id >= 0:
		job.clients.erase(next_id)
		if _requests.has(next_id):
			var request: Request = _requests[next_id]
			var target: Resource = job.resource
			var success: bool = str(job.failure).is_empty() and bool(request.code_plan.valid_target(target)) and _code_owner_current(request) and bool(request.input_lease.valid_for_code(request.code_plan))
			if success:
				success = request.input_lease.attach_loaded_code_resource(request.code_plan, target, request.consumer.get_ref(), self)
			if success:
				job.retained = true
			finished.append({"id": next_id, "result": {"success": success, "errors": [] if success else [str(job.failure) if not str(job.failure).is_empty() else "code_target_owner_or_type_invalid"],
				"resource": target if success else null, "lease": request.input_lease if success else null, "diagnostics": request.diagnostics.duplicate(true)}})
	if job.clients.is_empty():
		_jobs.erase(path)
		job.input_leases.clear()
		if job.resource != null and not bool(job.retained):
			retire_resources({path: job.resource})
	else:
		_queue(path)

func cancel_code_owner(consumer: Node, generation: int) -> void:
	for id: int in _requests.keys():
		var request: Request = _requests[id]
		if request.kind not in ["code_publication", "code_inputs", "code_target"] or request.generation != generation or request.consumer == null or not is_same(request.consumer.get_ref(), consumer):
			continue
		request.scope.cancel()
		var result := {"success": false, "errors": ["code_owner_cancelled"], "lease": null, "resource": null}
		if _quantum_active:
			_deferred_completions.append({"id": id, "result": result})
		else:
			_complete(id, result)
	_activate()

func retire_code_result(result: Dictionary) -> void:
	var resource: Variant = result.get("resource")
	var lease: Variant = result.get("lease")
	if resource is Resource and not (lease is RefCounted and is_same(lease.get_script(), Lease) and is_same(lease._retained_code_resource, resource)):
		retire_resources({resource.resource_path: resource})
	result.clear() # original lease PREDELETE submits Shader + retained Script refs.

func _exit_tree() -> void:
	_retire_code_world_handoff()
	# Engine requests cannot be cancelled. Final shutdown may join IN_PROGRESS;
	# ordinary scene work keeps its existing timeout and optional Budget quanta.
	for path: String in _jobs.keys():
		var job: Dictionary = _jobs[path]
		if bool(job.get("started", false)) and not bool(job.get("delivering", false)):
			var status := ResourceLoader.load_threaded_get_status(path)
			if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
				ResourceLoader.load_threaded_get(path)
				_get_calls += 1
	_jobs.clear()
	_requests.clear()
	_retirements.clear()
	_applications.clear()


func code_result_retention_current(result: Dictionary, consumer: Node) -> bool:
	var lease: Variant = result.get("lease")
	var resource: Variant = result.get("resource")
	return bool(result.get("success", false)) and lease is RefCounted and is_same(lease.get_script(), Lease) and resource is Script and bool(lease.loaded_code_retention_current(resource, consumer, self))

func transfer_code_result_retention(result: Dictionary, previous: Node, next_consumer: Node) -> bool:
	if not code_result_retention_current(result, previous) or not is_instance_valid(next_consumer) or not next_consumer.is_inside_tree():
		return false
	var previous_script: Script = previous.get_script() as Script
	var next_script: Script = next_consumer.get_script() as Script
	if previous_script == null or next_script == null or previous_script.resource_path != "res://scripts/startup_loading.gd" or next_script.resource_path != "res://scripts/character_select.gd":
		return false
	return bool(result.lease.transfer_loaded_code_retention(result.resource, previous, next_consumer, self))

# One outstanding scene handoff lives in the existing request ledger. It is
# not a cache and owns no native request. The next actual current scene closes
# an unclaimed handoff; only the prepared PackedScene's Script may claim.
var _code_world_handoff_id := 0

func _stage_code_world_handoff(result: Dictionary, consumer: Node, scene: PackedScene) -> int:
	if _code_world_handoff_id != 0 or _requests.size() >= MAX_CODE_REQUESTS or not code_result_retention_current(result, consumer) or not is_same(get_tree().current_scene, consumer) or scene == null or scene.resource_path != "res://scenes/main.tscn" or not is_same(ResourceLoader.get_cached_ref(scene.resource_path), scene):
		return 0
	var consumer_script: Script = consumer.get_script() as Script
	var publisher: Node = get_tree().root.get_node_or_null("ContentLayers")
	if consumer_script == null or consumer_script.resource_path != "res://scripts/character_select.gd" or not is_instance_valid(publisher) or not is_same(publisher._feature_resources(), self):
		return 0
	var generation: int = consumer.get("_launch_code_generation")
	var overlay: Control = consumer.get("launch_loading_overlay") as Control
	var overlay_script: Script
	if is_instance_valid(overlay):
		overlay_script = overlay.get_script() as Script
	if overlay_script == null or overlay_script.resource_path != "res://scripts/loading_transition_overlay.gd" or not is_same(overlay.get_parent(), consumer) or not consumer.is_code_preparation_generation_current(generation) or not consumer.is_code_preparation_loading_phase_current(generation) or overlay.code_preparation_cover_receipt().is_empty():
		return 0
	var state: SceneState = scene.get_state()
	if state.get_node_count() != 1 or state.get_node_property_count(0) > 64:
		return 0
	var world_script: Script
	for index in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, index) == &"script":
			world_script = state.get_node_property_value(0, index) as Script
	if world_script == null or world_script.resource_path != "res://scripts/game_root.gd" or not is_same(ResourceLoader.get_cached_ref(world_script.resource_path), world_script):
		return 0
	if not bool(result.lease.transfer_loaded_code_retention(result.resource, consumer, publisher, self)):
		return 0
	_next_request += 1
	var id := _next_request
	var request := Request.new()
	request.kind = "code_retention_handoff"
	request.consumer = weakref(consumer)
	request.publisher = weakref(publisher)
	request.input_lease = result.lease
	request.plan = {"result": result.duplicate(false), "world_script": world_script}
	_requests[id] = request
	_code_world_handoff_id = id
	_queue_code_step(id, "code_retention_handoff")
	_activate()
	return id

func change_scene_with_code_retention(result: Dictionary, consumer: Node, scene: PackedScene) -> int:
	# Reservation, original SceneTree call and error cleanup are atomic: no
	# caller can exit/reenter between staging and submitting its replacement.
	var id := _stage_code_world_handoff(result, consumer, scene)
	if id == 0:
		return ERR_UNAVAILABLE
	var error: int = get_tree().change_scene_to_packed(scene)
	if error != OK:
		var request: Request = _requests[id]
		var publisher: Node = request.publisher.get_ref()
		var held: Dictionary = request.plan.result
		if code_result_retention_current(held, publisher) and bool(held.lease.transfer_loaded_code_retention(held.resource, publisher, consumer, self)):
			_requests.erase(id)
			_code_world_handoff_id = 0
			request.plan.clear()
			request.input_lease = null # original Hall dictionary still owns its lease.
		else:
			_retire_code_world_handoff()
	return error

func claim_code_world_handoff(consumer: Node) -> Dictionary:
	if _code_world_handoff_id == 0 or not _requests.has(_code_world_handoff_id) or not is_instance_valid(consumer) or not consumer.is_inside_tree() or consumer.is_queued_for_deletion() or not is_same(get_tree().current_scene, consumer) or not is_same(consumer.get_parent(), get_tree().root) or consumer.scene_file_path != "res://scenes/main.tscn":
		return {}
	var request: Request = _requests[_code_world_handoff_id]
	var publisher: Node = request.publisher.get_ref()
	var held: Dictionary = request.plan.result
	if not is_same(consumer.get_script(), request.plan.world_script) or not code_result_retention_current(held, publisher) or not bool(held.lease.transfer_loaded_code_retention(held.resource, publisher, consumer, self)):
		return {}
	var result: Dictionary = held.duplicate(false)
	_requests.erase(_code_world_handoff_id)
	_code_world_handoff_id = 0
	request.plan.clear()
	request.input_lease = null
	return result

func _retire_code_world_handoff() -> void:
	if _code_world_handoff_id == 0 or not _requests.has(_code_world_handoff_id):
		_code_world_handoff_id = 0
		return
	var request: Request = _requests[_code_world_handoff_id]
	_requests.erase(_code_world_handoff_id)
	_code_world_handoff_id = 0
	retire_code_result(request.plan.result)
	request.plan.clear()
	request.input_lease = null

func _step_code_world_handoff(id: int) -> void:
	if id != _code_world_handoff_id or not _requests.has(id):
		return
	var request: Request = _requests[id]
	var publisher: Node = request.publisher.get_ref()
	if not code_result_retention_current(request.plan.result, publisher):
		_retire_code_world_handoff()
	else:
		var current_scene: Node = get_tree().current_scene
		var previous: Node = request.consumer.get_ref()
		# SceneTree removes the old scene immediately and adds the replacement at
		# its existing frame boundary. Null is an in-progress replacement, not an
		# invented failure timeout. New GameRoot claims synchronously in _ready.
		if is_instance_valid(current_scene) and not is_same(current_scene, previous):
			_retire_code_world_handoff()
		else:
			_queue_code_step(id, "code_retention_handoff")

func pending_code_count() -> int:
	var count := 0
	for request: Request in _requests.values():
		count += 1 if request.kind in ["code_publication", "code_inputs", "code_target", "code_retention_handoff"] else 0
	for job: Dictionary in _jobs.values():
		count += 1 if job.get("kind") == "code_target" else 0
	return count
