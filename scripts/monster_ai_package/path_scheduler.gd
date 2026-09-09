class_name HCMonsterPathScheduler
extends Node

const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const SOFT_BUDGET_USEC := 1200
const NODE_NAME := "HCMonsterPathBudget"
var jobs: Dictionary = {}
var queue: Array[int] = []
var service_count := 0
var cancelled_count := 0
var expansions_count := 0
var maximum_wait_frames := 0
var diagnostic_pump_calls := 0
var diagnostic_pump_usec := 0

static func for_tree(tree: SceneTree) -> HCMonsterPathScheduler:
	if tree == null:
		return null
	var found := tree.root.get_node_or_null(NodePath(NODE_NAME))
	if found != null:
		return found as HCMonsterPathScheduler
	var service := HCMonsterPathScheduler.new()
	service.name = NODE_NAME
	# Run after ordinary actors so each newly queued request is visible.
	service.process_physics_priority = 100
	tree.root.add_child(service)
	return service

func submit(owner: Node, token: int, search: Search) -> void:
	var id := owner.get_instance_id()
	var previous: Dictionary = jobs.get(id, {})
	if not previous.is_empty() and int(previous.token) == token:
		return
	if not previous.is_empty():
		(previous.search as Search).detach_shared_goal_field()
	var submitted_frame := int(previous.get("submitted_frame", Engine.get_physics_frames()))
	jobs[id] = {"owner": weakref(owner), "token": token, "search": search, "submitted_frame": submitted_frame}
	if not queue.has(id):
		queue.append(id)

func cancel(owner_id: int) -> void:
	var job: Dictionary = jobs.get(owner_id, {})
	if not job.is_empty():
		(job.search as Search).detach_shared_goal_field()
	if jobs.erase(owner_id):
		cancelled_count += 1
	queue.erase(owner_id)

func _physics_process(_delta: float) -> void:
	pump()

func pump(soft_budget_usec: int = SOFT_BUDGET_USEC) -> void:
	var pump_started_usec := Time.get_ticks_usec()
	diagnostic_pump_calls += 1
	var visits := 0
	var initial_count := queue.size()
	var services := 0
	var started_usec := Time.get_ticks_usec()
	var pump_deadline_usec := started_usec + soft_budget_usec if soft_budget_usec > 0 else 0
	while not queue.is_empty() and visits < initial_count and services < 2:
		if soft_budget_usec > 0 and services > 0 and Time.get_ticks_usec() - started_usec >= soft_budget_usec:
			break
		var id: int = queue.pop_front()
		visits += 1
		var job: Dictionary = jobs.get(id, {})
		if job.is_empty():
			continue
		var owner: Node = (job.owner as WeakRef).get_ref() as Node
		if not is_instance_valid(owner) or owner.is_queued_for_deletion():
			(job.search as Search).detach_shared_goal_field()
			jobs.erase(id)
			continue
		if not bool(owner.call("_hc_path_job_current", int(job.token))):
			(job.search as Search).detach_shared_goal_field()
			jobs.erase(id)
			continue
		# This is the EXISTING global budget. Never reset it per actor/frame here.
		if not Terrain._claim_path_query_budget():
			queue.push_front(id)
			break
		services += 1
		service_count += 1
		maximum_wait_frames = maxi(maximum_wait_frames, Engine.get_physics_frames() - int(job.submitted_frame))
		var search: Search = job.search
		var before := search.expansions
		var result := search.advance(Terrain.MAX_PATH_EXPANSIONS, pump_deadline_usec)
		expansions_count += search.expansions - before
		if result == "SEARCHING":
			queue.append(id) # Round robin preserves age; one hard job cannot monopolize.
		else:
			search.detach_shared_goal_field()
			jobs.erase(id)
			owner.call("_hc_path_completed", int(job.token), result, search.path)
	diagnostic_pump_usec += Time.get_ticks_usec() - pump_started_usec
