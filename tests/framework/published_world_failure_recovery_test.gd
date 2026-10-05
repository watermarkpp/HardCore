extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/failed_publication_probe_root.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _publish_invalid(game: Node) -> bool:
	return game._begin_map_transition(func():
		game._load_zone(game.current_zone, true, game.current_map_data)
		game._spawn_enemy({"monster_id": 19.5}, game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5)), false, -1.0,
			{"respawn_enabled": false, "spawn_slot_id": "test:failed-publication:invalid"})
	, game.current_map_id)

func _settle(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while game._map_transition_in_progress and Time.get_ticks_msec() < deadline: await get_tree().process_frame

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual initial mapped world reaches READY within original20seconds")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	game.player.max_hp = 9999; game.player.current_hp = 9999
	var generation: int = game._zone_generation
	var home_operations: int = game.home_operations
	check(_publish_invalid(game), "real cold malformed descriptor starts actual failed publication")
	await _settle(game)
	check(game.home_operations == home_operations + 1, "one actual home recovery operation without repeated same-map fallback")
	check(game._zone_generation == generation + 2, "failed same-home world recovers through a genuine newly published home generation")
	check(game.gameplay_input_is_enabled() and game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY,
		"healthy recovery releases gameplay only after original READY contract")
	check(game.feature_world_capacity_bound().sealed and game.feature_world_capacity_bound().proved,
		"recovery owns complete sealed home birth closure")
	check(not game.player.combat_transition_is_active() and not game._gameplay_input_locks.has("map_transition"),
		"successful recovery releases original combat token and map lock")
	game.player.take_damage(999999)
	deadline = Time.get_ticks_msec() + 5000
	while game._active_death_id.is_empty() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.player._dead and not game._active_death_id.is_empty(), "real fatal HP delivery reaches original formal death owner")
	generation = game._zone_generation
	home_operations = game.home_operations
	await game._fail_map_transition(&"post_arrival_safe_home")
	await _settle(game)
	check(game.home_operations == home_operations + 1 and game._zone_generation == generation + 1,
		"settled dead-player recovery performs one genuine home publication")
	check(not game.player._dead and game.player.current_hp == game.player.max_hp and game._active_death_id.is_empty(),
		"real production town revival completes original death lifecycle")
	check(game.gameplay_input_is_enabled() and not game._gameplay_input_locks.has("map_transition")
		and not game._gameplay_input_locks.has("player_death"), "synchronously completed accepted revival cannot strand either original input lock")
	game.reject_home_publication = true
	home_operations = game.home_operations
	check(_publish_invalid(game), "second real publication failure starts bounded recovery")
	await _settle(game)
	check(game.home_operations == home_operations + 1, "a failing actual home plan terminates after one recovery attempt")
	check(not game._map_transition_in_progress and game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.FAILED,
		"real SceneTree failure reaches terminal FAILED instead of recursive recovery")
	check(not game.gameplay_input_is_enabled() and game._gameplay_input_locks.has("map_transition"),
		"incomplete home world remains closed to gameplay")
	check(int(game._gameplay_input_locks.get("map_transition", 0)) == 1,
		"terminal failure retains exactly one original map lock without acquiring a duplicate owner")
	check(not game.player.combat_transition_is_active(), "terminal failure releases obsolete combat token")
	var notice := str(game.hud.notice_presenter.current_notice().get("message", ""))
	check(notice == "安全区域加载失败，请重新进入游戏。", "terminal failure immediately presents explicit player error")
	var terminal_generation: int = game._world_bootstrap_coordinator.generation
	for _frame in range(3): await get_tree().process_frame
	check(game._world_bootstrap_coordinator.generation == terminal_generation and game.home_operations == home_operations + 1,
		"later SceneTree frames do not restart failed recovery")
	game.queue_free(); await get_tree().process_frame; _finish()

func _finish() -> void:
	var ok := proof.write_receipt("published_world_failure_recovery_test", proof.records.size(), failures.size())
	print("PUBLISHED_WORLD_FAILURE_RECOVERY_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
