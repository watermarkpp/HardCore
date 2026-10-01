extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const DeathFixtures := preload("res://tests/death_drop_budget_queue_test.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var epoch := 3000
var clock := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	var game := DeathFixtures.FixtureGameRoot.new()
	game.current_map_id = 5317
	game._zone_generation = 11
	add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	var world: Dictionary = game._world_context.capture_world()
	var profile: Dictionary = game._world_context.capture_profile()
	check(world.is_read_only() and profile.is_read_only(), "identity views are immutable accepted values")
	check(game._world_context.matches_world(world) and game._world_context.matches_profile(profile),
		"views read the actual Root and PlayerState authorities")
	Budget.configure_for_tests(100, func() -> int: return epoch, func() -> int: return clock)
	var token := Budget.begin("path")
	clock = 100
	Budget.end(token)
	game._zone_generation += 1
	game.current_map_id += 1
	check(not game._world_context.matches_world(world), "old world identity is invalidated by the existing zone generation")
	check(game._world_context.matches_profile(profile), "a map change does not invalidate the character ledger identity")
	check(Budget.remaining_usec() == 0 and Budget.snapshot().epoch == epoch,
		"world replacement cannot replenish the application frame budget")
	Budget.reset_test_configuration()
	var before: int = game._time_domains.simulation_usec()
	for step in range(240):
		game._time_domains.advance_simulation(1.0 / 60.0)
	check(game._time_domains.simulation_usec() - before == 4000000,
		"240 fractional physics deltas retain exactly four seconds at microsecond precision")
	get_tree().paused = true
	before = game._time_domains.simulation_usec()
	check(not game._time_domains.advance_simulation(2.0) and game._time_domains.simulation_usec() == before,
		"paused time cannot create simulation catch-up debt")
	get_tree().paused = false
	game.set_physics_process(true)
	for iteration in range(3):
		await get_tree().physics_frame
	game.set_physics_process(false)
	check(game._time_domains.simulation_usec() == before, "empty extension physics callbacks do not advance an unused new simulation domain")
	var saved_profile := PlayerState.active_profile_id
	PlayerState.active_profile_id = "fixture:other_profile"
	check(not game._world_context.matches_profile(profile), "switching character invalidates the former receipt identity")
	PlayerState.active_profile_id = saved_profile
	var context: RefCounted = game._world_context
	game.free()
	check(context.current_world_owner() == null and not context.matches_world(world),
		"context holds no strong world reference after owner destruction")
	if not proof.write_receipt("world_time_contract_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_WORLD_TIME_CONTRACT_PASS" if failures.is_empty()
		else "FRAMEWORK_WORLD_TIME_CONTRACT_FAIL") + " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
