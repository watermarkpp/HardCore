extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/published_birth_probe_root.gd")
var proof := Proof.new()
var failures: Array[String] = []
var reported: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual initial mapped world reaches READY within original20seconds")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	game.set_safe_logout_error_reporter(func(action: StringName, reason: String): reported.append(str(action) + ":" + reason))
	var old_generation: int = game._zone_generation
	check(game.background.environment_node_count() > 0, "actual READY world owns environment before failure")
	game._test_force_home_failure = true
	var arrival_operations := [0]
	check(game._begin_map_transition(func(): arrival_operations[0] += 1, game.current_map_id), "real transition starts before unresolved arrival gate")
	deadline = Time.get_ticks_msec() + 5000
	while game._map_transition_in_progress and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(arrival_operations[0] == 0 and game._zone_generation == old_generation, "arrival operation did not execute or invent a new actor world")
	check(game.background.environment_node_count() == 0, "actual preparation already cleared prior environment before arrival failed")
	check(not game.gameplay_input_is_enabled() and int(game._gameplay_input_locks.get("map_transition", 0)) == 1,
		"cleared environment cannot be handed back as an untouched playable old world")
	check(not game._map_transition_in_progress and game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.FAILED,
		"unresolvable home terminates without repeated recovery")
	check(reported.size() >= 1 and reported[0].begins_with("world_pipeline_arrival:"), "actual arrival failure remains observable through original reporter")
	game._test_force_home_failure = false
	check(game.travel_to_service_home(false, true), "resolved home retry uses original travel owner")
	deadline = Time.get_ticks_msec() + 5000
	while game._map_transition_in_progress and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled() and game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY,
		"retry releases gameplay only after real complete home READY")
	check(not game._gameplay_input_locks.has("map_transition") and game.background.environment_node_count() > 0,
		"successful retry transfers retained map lock once and restores real environment")
	game.queue_free(); await get_tree().process_frame; _finish()

func _finish() -> void:
	var ok := proof.write_receipt("published_environment_failure_recovery_test", proof.records.size(), failures.size())
	print("PUBLISHED_ENVIRONMENT_FAILURE_RECOVERY_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
