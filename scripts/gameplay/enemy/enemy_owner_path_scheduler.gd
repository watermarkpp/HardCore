extends RefCounted

var _owner = OS.get_thread_caller_id()
var deps: Dictionary
var _configured = false
func owner_thread_id() -> int:
	return _owner

var jobs_access: RefCounted
var process_scope: RefCounted
func configure_owner(bindings: Dictionary, access: RefCounted, service_handle: Object, scope: RefCounted) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner or service_handle == null or service_handle is Node or service_handle is RefCounted or service_handle.get_instance_id() <= 0:
		push_error("scheduler needs original positive source ID and exact owner")
		return false
	for provider in [access, scope]:
		if provider == null or not provider.has_method("owner_thread_id") or provider.owner_thread_id() != _owner:
			push_error("scheduler requires explicit owner-local access and process scope")
			return false
	for key in ["Terrain", "FrameBudget", "Engine", "Time"]:
		if not bindings.get(key) is RefCounted or not bindings[key].has_method("owner_thread_id") or bindings[key].owner_thread_id() != _owner:
			push_error("scheduler owner dependency missing: " + key)
			return false
	deps = bindings
	jobs_access = access
	process_scope = scope
	_budget_category = "path:%d" % service_handle.get_instance_id()
	_configured = true
	return true
func get_shared() -> RefCounted:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	return self

const SOFT_BUDGET_USEC := 1200
const NODE_NAME := "HCMonsterPathBudget"
var jobs: Dictionary = {}
var queue: Array[int] = []
var service_count = 0
var cancelled_count = 0
var expansions_count = 0
var maximum_wait_frames = 0
var diagnostic_pump_calls = 0
var diagnostic_pump_usec = 0
var maximum_completion_latency_usec = 0
var _budget_category = ""

func retire() -> void:
	deps.FrameBudget.mark_progress_pending(_budget_category, false)

func submit(owner: Object, token: int, search: Object) -> void:
	var id = jobs_access.runtime_id(owner)
	var previous: Dictionary = jobs.get(id, {})
	if not previous.is_empty() and int(previous.token) == token:
		return
	if not previous.is_empty():
		previous.search.detach_shared_goal_field()
	var submitted_frame = int(previous.get("submitted_frame", deps.Engine.get_physics_frames()))
	jobs[id] = {"owner": jobs_access.capture(owner), "token": token, "search": search, "submitted_frame": submitted_frame,
		"queued_at_usec": int(previous.get("queued_at_usec", deps.Time.get_ticks_usec()))}
	if not queue.has(id):
		queue.append(id)
	deps.FrameBudget.mark_progress_pending(_budget_category, not queue.is_empty(), true, false, process_scope, true)

func cancel(owner_id: int) -> void:
	var job: Dictionary = jobs.get(owner_id, {})
	if not job.is_empty():
		job.search.detach_shared_goal_field()
	if jobs.erase(owner_id):
		cancelled_count += 1
	queue.erase(owner_id)
	deps.FrameBudget.mark_progress_pending(_budget_category, not queue.is_empty(), true, false, process_scope, true)

func original_physics_pump(_delta: float) -> void:
	pump()

func pump(soft_budget_usec: int = SOFT_BUDGET_USEC) -> void:
	deps.FrameBudget.mark_progress_pending(_budget_category, not queue.is_empty(), true, false, process_scope, true)
	if queue.is_empty():
		return
	var token = deps.FrameBudget.begin_progress(_budget_category)
	if token == 0:
		return
	var admitted_usec = deps.FrameBudget.remaining_progress_usec()
	if soft_budget_usec > 0:
		admitted_usec = mini(admitted_usec, soft_budget_usec)
	_pump_slice(admitted_usec)
	deps.FrameBudget.end(token)
	deps.FrameBudget.mark_progress_pending(_budget_category, not queue.is_empty(), true, false, process_scope, true)

func _pump_slice(soft_budget_usec: int) -> void:
	var pump_started_usec = deps.Time.get_ticks_usec()
	diagnostic_pump_calls += 1
	var visits = 0
	var initial_count = queue.size()
	var services = 0
	var started_usec = deps.Time.get_ticks_usec()
	var pump_deadline_usec = started_usec + soft_budget_usec
	while not queue.is_empty() and visits < initial_count and services < 2:
		if deps.Time.get_ticks_usec() >= pump_deadline_usec:
			break
		var id: int = queue.pop_front()
		visits += 1
		var job: Dictionary = jobs.get(id, {})
		if job.is_empty():
			continue
		var owner: Object = jobs_access.resolve(job.owner) as Object
		if not jobs_access.present(owner) or jobs_access.queued(owner):
			job.search.detach_shared_goal_field()
			jobs.erase(id)
			continue
		if not bool(jobs_access.invoke(owner, ["_hc_path_job_current", int(job.token)])):
			job.search.detach_shared_goal_field()
			jobs.erase(id)
			continue
		# This is the EXISTING global budget. Never reset it per actor/frame here.
		if not deps.Terrain._claim_path_query_budget():
			queue.push_front(id)
			break
		services += 1
		service_count += 1
		maximum_wait_frames = maxi(maximum_wait_frames, deps.Engine.get_physics_frames() - int(job.submitted_frame))
		var search: Object = job.search
		var before = search.expansions
		var result = search.advance(deps.Terrain.MAX_PATH_EXPANSIONS, pump_deadline_usec)
		expansions_count += search.expansions - before
		if result == "SEARCHING":
			queue.append(id) # Round robin preserves age; one hard job cannot monopolize.
		else:
			search.detach_shared_goal_field()
			jobs.erase(id)
			jobs_access.invoke(owner, ["_hc_path_completed", int(job.token), result, search.path])
			maximum_completion_latency_usec = maxi(maximum_completion_latency_usec,
				deps.Time.get_ticks_usec() - int(job.queued_at_usec))
	diagnostic_pump_usec += deps.Time.get_ticks_usec() - pump_started_usec

func work_snapshot() -> Dictionary:
	var oldest_age_usec = 0
	for job: Dictionary in jobs.values():
		oldest_age_usec = maxi(oldest_age_usec, deps.Time.get_ticks_usec() - int(job.queued_at_usec))
	return {"pending": jobs.size(), "services": service_count, "oldest_age_usec": oldest_age_usec,
		"maximum_completion_latency_usec": maximum_completion_latency_usec}
