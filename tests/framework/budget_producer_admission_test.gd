extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Service := preload("res://scripts/json_persistence_service.gd")
const Scheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Streaming := preload("res://scripts/monster_visual_streaming_coordinator.gd")
const DeathFixtures := preload("res://tests/death_drop_budget_queue_test.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var epoch := 1000
var clock := 0

class PathOwner extends Node:
	var completions := 0
	func _hc_path_job_current(token: int) -> bool:
		return token == 1
	func _hc_path_completed(_token: int, state: String, _path: PackedVector2Array) -> void:
		assert(state == "FOUND")
		completions += 1

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	clock = Time.get_ticks_usec()
	Budget.configure_for_tests(100000, func() -> int: return epoch, func() -> int: return clock)
	var token := Budget.begin("already_spent")
	clock += 100000
	Budget.end(token)
	check(Budget.remaining_usec() == 0, "fixture exhausts the actual shared ledger before production entry")
	var stream := Streaming.new()
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	stream._threaded_profile_requests["ready:fixture"] = {"state": "loaded",
		"lane": Streaming.JOB_LANE_RUNTIME_DEMAND, "map_generation": -1, "request_sequence": 1,
		"resources": {"idle": texture, "walk": texture, "attack": texture, "hit": texture, "death": texture}}
	stream.poll_once(Engine.get_process_frames())
	check(stream.apply_order().is_empty() and stream.pending_request_count() == 1,
		"ready resource admission cannot acquire a second frame allowance")
	var game := DeathFixtures.FixtureGameRoot.new()
	game.current_map_id = 5317
	game._zone_generation = 11
	add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.set_process(false)
	game._enemy_death_flush_queued = true
	var enemy := EnemyActor.new()
	var canonical := GameData.get_monster_by_id(34)
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("death_runtime_snapshot", game._build_enemy_death_runtime_snapshot(canonical))
	enemy.set_meta("death_origin", {"captured": true, "map_id": 5317, "generation": 11,
		"death_position": Vector2.ZERO, "spawn_position": Vector2.ZERO, "spawn_context": {}})
	game._on_enemy_died(enemy, canonical)
	enemy.free()
	var rng_before: int = game._rng.state
	var experience_before: int = PlayerState.experience
	game._pump_enemy_death_work_queue()
	check(game._pending_enemy_deaths.size() == 1 and str(game._pending_enemy_deaths[0].state) == "QUEUED"
		and game._rng.state == rng_before and PlayerState.experience == experience_before,
		"optional death settlement cannot bypass exhaustion with a first-job exception")
	# This fixture checks admission; the established real reward/loot suite
	# separately proves exactly-once completion through the same state machine.
	game._flush_enemy_deaths(false)
	check(game._pending_enemy_deaths.is_empty(), "explicit death lifecycle barrier drains preserved work")
	game.free()
	var service := Service.new()
	var directory := "user://framework_budget_admission_%d" % Time.get_ticks_usec()
	var job := service.submit(directory.path_join("request.json"), {"request": 1}, {"value": 1},
		func(_document: Dictionary) -> Dictionary: return {"valid": true, "terminal": false})
	check(job != null, "exhaustion preserves the accepted ordered request")
	if job != null:
		check(job._task_id == -1 and str(service._queue[0].phase) == "NEW",
			"ordinary JSON entry cannot start optional work after another owner exhausts the frame")
		var completed: Dictionary = service.finish(job, true)
		check(bool(completed.get("success", false)), "explicit lifecycle barrier completes real durable IO despite exhaustion")
		check(service.pending_count() == 0, "explicit barrier consumes all receipt ownership")
	var owner := PathOwner.new()
	add_child(owner)
	var scheduler := Scheduler.new()
	add_child(scheduler)
	scheduler.set_physics_process(false)
	var search := Search.new()
	search.configure({"valid": true, "contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": 1, "build_sha256": "b".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(16, 16), "blocked_cells": {}}, Vector2i(1, 1),
		{Vector2i(10, 10): Vector2(10.5, 10.5)}, 0.35, Callable())
	scheduler.submit(owner, 1, search)
	scheduler.pump()
	check(scheduler.service_count == 0 and scheduler.jobs.size() == 1 and search.expansions == 0,
		"real path scheduler cannot reset the exhausted process-frame allowance")
	for iteration in range(30):
		if owner.completions > 0:
			break
		await get_tree().physics_frame
		epoch += 1
		clock = Time.get_ticks_usec()
		stream.poll_once(Engine.get_process_frames())
		scheduler.pump()
	check(owner.completions == 1 and scheduler.jobs.is_empty(),
		"deferred real path eventually completes exactly once after fresh admission")
	check(Budget.snapshot().open_scopes == 0, "all production entries close synchronous scopes")
	check(stream.apply_order() == ["ready:fixture"] and stream.pending_request_count() == 0,
		"ready resource is delivered exactly once after fresh admission")
	scheduler.free()
	owner.free()
	Budget.reset_test_configuration()
	if not proof.write_receipt("budget_producer_admission_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_BUDGET_PRODUCER_ADMISSION_PASS" if failures.is_empty()
		else "FRAMEWORK_BUDGET_PRODUCER_ADMISSION_FAIL") + " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
