extends Node

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode: bool = PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null)
	var game := packed.instantiate()
	add_child(game)
	await get_tree().process_frame
	await _wait_for_transition(game)
	while game._world_bootstrap_in_progress:
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "initial READY must release gameplay input")
	# This test isolates the UI handshake. Threaded monster streaming has its own
	# budget/cache suite and must not make these transition timing assertions wait.
	game._monster_prefetch_enabled = false

	game.travel_to_map(911001)
	assert(game.current_map_id == 911001, "test mode must preserve synchronous travel")

	PlayerState.test_mode = false
	game.travel_to_map(911002)
	var first_transition_id: String = game._active_map_transition_id
	assert(game._map_transition_in_progress)
	assert(not first_transition_id.is_empty())
	assert(game.current_map_id == 911001, "map changed before Loading covered the scene")
	assert(game.hud.loading_transition_overlay.visible)
	var protected_hp: int = game.player.current_hp
	var protected_mp: int = game.player.current_mp
	var transition_epoch: int = game.player.combat_epoch
	assert(game.player.combat_transition_is_active(), "Loading must isolate damage before its first await")
	game.player.take_damage(100000)
	game.player.take_direct_spell_damage("", 100000, 999, 0)
	game.player._apply_resolved_damage(100000, false, "poison")
	assert(game.player.current_hp == protected_hp and game.player.current_mp == protected_mp,
		"Loading damage must not consume HP, MP or shields")
	assert(not game.player.finish_combat_transition("stale:token"), "stale token must not release isolation")

	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": "stale:request",
	})
	await get_tree().process_frame
	assert(game.current_map_id == 911001, "stale Loading callback changed the map")
	game.travel_to_map(911003)
	assert(
		game._active_map_transition_id == first_transition_id,
		"overlapping travel replaced the active transition"
	)

	await _wait_for_transition(game)
	assert(game.current_map_id == 911002)
	assert(not game._map_transition_in_progress)
	assert(not game.player.combat_transition_is_active(), "READY must release its own protection")
	assert(game.player.combat_epoch == transition_epoch)

	var portal := _portal_to(game, 911003)
	assert(portal != null)
	assert(game.travel_via_portal(portal, true), "portal request was not accepted")
	assert(game.current_map_id == 911002, "portal loaded before Loading covered the scene")
	await _wait_for_transition(game)
	assert(game.current_map_id == 911003)

	game.travel_to_service_home(false, false, "比奇省")
	assert(game.current_map_id == 911003, "return-home loaded before Loading covered the scene")
	var return_home_transition_id: String = game._active_map_transition_id
	game._on_scroll_used("回城卷")
	assert(
		game._active_map_transition_id == return_home_transition_id,
		"duplicate return-home scroll replaced the active transition"
	)
	await _wait_for_transition(game)
	assert(game.current_map_id == GameData.service_runtime_map_id(0))

	PlayerState.test_mode = true
	game.travel_to_map(911001)
	PlayerState.test_mode = false
	game.player._dead = true
	game.player.current_hp = 0
	assert(not game.travel_to_service_home(false, false, "比奇省"),
		"dead player must not travel through the ordinary home entry")
	game._on_player_death_requested()
	assert(game.hud.death_revival_panel.visible, "death UI did not open before revival travel")
	assert(not game._map_transition_in_progress, "death started Loading before the player selected revival")
	game.hud.death_revival_panel.town_button.pressed.emit()
	assert(game.current_map_id == 911001, "death revival moved before Loading covered the scene")
	await _wait_for_transition(game)
	assert(game.current_map_id == GameData.service_runtime_map_id(0))
	assert(
		game.player.global_position.is_equal_approx(game._bich_home_screen_position_px()),
		"death revival did not finish at the service-home anchor"
	)
	assert(not game.player._dead and game.player.current_hp == game.player.max_hp)

	PlayerState.test_mode = previous_test_mode
	game.queue_free()
	print("GAME_ROOT_LOADING_TRANSITION_PASS: unique id, covered-before-load, stale rejection, single-flight, portal, scroll and death-revival wiring")
	get_tree().quit()


func _wait_for_transition(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not game._map_transition_in_progress, "Loading transition did not finish")


func _portal_to(game: Node, target_map_id: int) -> ZonePortal:
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if node is ZonePortal and node.target_map_id == target_map_id:
			return node
	return null
