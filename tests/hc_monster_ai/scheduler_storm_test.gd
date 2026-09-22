extends Node

## R2-W7 scheduler counterexamples the path suite leaves open: the invalid
## task storm. A monster that re-decides its path every physics frame
## re-submits the scheduler job with a fresh token; the scheduler must keep
## at most one queued job per owner, preserve the original submission age
## ("round robin preserves age"), detach the replaced search from its shared
## goal field, and service only the newest token. Also pins the stale-token
## drop and the oldest-first service order.

const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const Scheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
const GU := preload("res://scripts/ground_unit_space.gd")

var checks := 0
var failures: Array[String] = []


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("PATH_SCHEDULER_STORM: " + label)


class StormOwner:
	extends Node
	var current_token := 1
	var completed_tokens: Array[int] = []
	var completed_states: Array[String] = []
	var searches: Dictionary = {}
	func _hc_path_job_current(token: int) -> bool:
		return token == current_token
	func _hc_path_completed(token: int, state: String, _path: PackedVector2Array) -> void:
		completed_tokens.append(token)
		completed_states.append(state)


func context() -> Dictionary:
	return context_sized(Vector2i(512, 512))


func context_sized(size: Vector2i) -> Dictionary:
	var value := {
		"valid": true, "contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": 1, "build_sha256": "a".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": size, "blocked_cells": {},
	}
	value.make_read_only()
	return value


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var scheduler := Scheduler.new()
	add_child(scheduler)
	scheduler.set_physics_process(false)

	# ---- 1. Token storm: one owner re-submits a fresh token every pump ----
	# The 512x512 graph needs more than one service quantum (~700 expansions
	# against the 384 cap), so the queued job survives between pumps and the
	# re-submission truly replaces live work.
	var storm_owner := StormOwner.new()
	add_child(storm_owner)
	var replaced_searches: Array[Search] = []
	var token := 1
	var first_frame: int = Engine.get_physics_frames()
	for storm_frame in range(6):
		var search := Search.new()
		search.configure(context(), Vector2i(1, 1),
			{Vector2i(500, 500): Vector2(500.5, 500.5)}, .35, Callable())
		replaced_searches.append(search)
		storm_owner.current_token = token
		scheduler.submit(storm_owner, token, search)
		storm_owner.searches[token] = search
		scheduler.pump(0)
		check(
			scheduler.jobs.size() <= 1 and scheduler.queue.size() <= 1,
			"storm keeps at most one job and one queue entry (frame %d)" %
			storm_frame
		)
		token += 1
		await get_tree().physics_frame
	# The surviving job carries the newest token and the original age.
	check(
		not scheduler.jobs.is_empty()
		and int(scheduler.jobs.values()[0].token) == token - 1,
		"storm keeps only the newest token's job"
	)
	check(
		int(scheduler.jobs.values()[0].submitted_frame) == first_frame,
		"re-submission preserves the original submission age"
	)
	# Every superseded search was detached from any shared goal field.
	for index in range(replaced_searches.size() - 1):
		var superseded: Search = replaced_searches[index]
		check(
			superseded.shared_goal_field == null,
			"replaced search detaches its shared goal field (index %d)" % index
		)
	# The storm drains exactly once, with the final token.
	for frame in range(30):
		await get_tree().physics_frame
		scheduler.pump(0)
		if not scheduler.jobs.is_empty() and scheduler.queue.is_empty() \
				and storm_owner.completed_tokens.size() > 0:
			break
	check(
		storm_owner.completed_tokens == [token - 1],
		"storm owner completes exactly once with the newest token (got %s)" %
		str(storm_owner.completed_tokens)
	)
	check(
		scheduler.jobs.is_empty() and scheduler.queue.is_empty(),
		"storm drains without duplicates or abandoned jobs"
	)

	# ---- 2. Stale-token jobs are dropped without service ----
	var stale_owner := StormOwner.new()
	add_child(stale_owner)
	stale_owner.current_token = 2
	var stale_search := Search.new()
	stale_search.configure(context(), Vector2i(1, 1),
		{Vector2i(10, 10): Vector2(10.5, 10.5)}, .35, Callable())
	scheduler.submit(stale_owner, 1, stale_search)
	check(scheduler.jobs.size() == 1, "stale job queued")
	scheduler.pump(0)
	check(
		scheduler.jobs.is_empty() and stale_owner.completed_tokens.is_empty(),
		"stale-token job is dropped without completing or servicing"
	)

	# ---- 3. Oldest submission is serviced first (FIFO across pumps) ----
	# The older request is a tiny graph (completes in one service); the newer
	# one is a huge graph (stays SEARCHING). The older request must complete
	# first and the newer one must still drain without being starved.
	var first_owner := StormOwner.new()
	var second_owner := StormOwner.new()
	add_child(first_owner)
	add_child(second_owner)
	var first_search := Search.new()
	first_search.configure(context_sized(Vector2i(16, 16)), Vector2i(1, 1),
		{Vector2i(10, 10): Vector2(10.5, 10.5)}, .35, Callable())
	var second_search := Search.new()
	second_search.configure(context(), Vector2i(1, 1),
		{Vector2i(250, 250): Vector2(250.5, 250.5)}, .35, Callable())
	scheduler.submit(first_owner, 1, first_search)
	scheduler.submit(second_owner, 1, second_search)
	scheduler.pump(0)
	check(
		first_owner.completed_tokens == [1],
		"oldest submission completes in the first pump (FIFO order)"
	)
	check(
		not second_owner.completed_tokens.is_empty()
		or second_search.state == "SEARCHING",
		"newer submission is serviced after the older one, not instead of it"
	)
	for frame in range(60):
		await get_tree().physics_frame
		scheduler.pump(0)
		if second_owner.completed_tokens.size() > 0:
			break
	check(
		second_owner.completed_tokens == [1]
		and second_owner.completed_states[0] == "FOUND",
		"newer submission still drains to FOUND (no starvation)"
	)
	check(
		scheduler.jobs.is_empty() and scheduler.queue.is_empty(),
		"FIFO drain leaves no residue"
	)

	scheduler.queue_free()
	storm_owner.queue_free()
	stale_owner.queue_free()
	first_owner.queue_free()
	second_owner.queue_free()

	if failures.is_empty():
		print("PATH_SCHEDULER_STORM_PASS checks=", checks)
		get_tree().quit(0)
	else:
		print("PATH_SCHEDULER_STORM_FAILED count=%d" % failures.size())
		get_tree().quit(1)
