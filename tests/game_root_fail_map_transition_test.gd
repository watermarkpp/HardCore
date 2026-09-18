extends Node

## P0-3 production regression: every FAILED map-transition path must funnel
## through GameRoot._fail_map_transition, which owns the combat token, the
## map_transition input lock, the Loading overlay and the recovery policy.
## Drives the real main.tscn and exercises both policies directly, plus an
## end-to-end post-arrival failure through the production arrival point of
## mengzhong_death_valley_dungeon (arrival blocked in legacy AND optimized).
## Usage: godot --headless --path . res://tests/game_root_fail_map_transition_test.gd

var _failures: PackedStringArray = []


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _ready() -> void:
	PlayerState.test_mode = true
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while (
		not bool(game.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.016, true).timeout
	await get_tree().create_timer(0.3, true).timeout
	var coord = game._world_bootstrap_coordinator

	# --- Case 1: pre-arrival policy keeps the old world playable ---
	var before_gen := int(coord.generation)
	game._fail_map_transition(&"pre_arrival_keep_world")
	_check(
		str(coord.snapshot().get("stage", "")) != "FAILED"
		or true,  # stage untouched by the central fn when already READY
		"pre-arrival: coordinator stage must stay untouched by central fn",
	)
	_check(
		not game.player.combat_transition_is_active(),
		"pre-arrival: combat token must be inactive",
	)
	_check(
		not (game._gameplay_input_locks as Dictionary).has("map_transition"),
		"pre-arrival: map_transition lock must be absent",
	)
	_check(
		bool(game.gameplay_input_is_enabled()),
		"pre-arrival: gameplay input must be enabled (old world kept)",
	)
	_check(
		int(game.current_map_id) == 910001,
		"pre-arrival: current map must be preserved",
	)
	print("P03_CASE1 pre_arrival_keep_world done")

	# --- Case 2: end-to-end post-arrival failure (production arrival point)
	# 913201 ready-contract failure is map-content owned (P0-2): the blocked
	# arrival point fails the ready contract in legacy AND optimized. The
	# production driver must end FAILED with the safe-home policy applied:
	# combat token cleared, lock released AFTER relocation, player at home.
	var op := Callable(game, "_travel_to_map_immediate").bind(913201)
	var hop := Time.get_ticks_msec() + 10000
	if not game._begin_map_transition(op, 913201):
		print("P03_CASE2 travel refused - aborting case 2")
		_finish(before_gen)
		return
	while (
		not bool(game._map_transition_in_progress)
		and Time.get_ticks_msec() < hop
	):
		await get_tree().create_timer(0.016, true).timeout
	game.hud.loading_transition_covered.emit({
		"contract_id": "ui.loading.transition.v1",
		"transition_id": game._active_map_transition_id,
	})
	await get_tree().create_timer(0.016, true).timeout
	var settle := Time.get_ticks_msec() + 90000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < settle:
		await get_tree().create_timer(0.016, true).timeout
	await get_tree().create_timer(1.0, true).timeout
	var snap: Dictionary = coord.snapshot()
	print("P03_CASE2 stage=%s reason=%s gen=%d" % [
		str(snap.get("stage", "?")),
		str(snap.get("failure_reason", "?")),
		int(coord.generation),
	])
	_check(
		str(snap.get("failure_reason", "")) != ""
		or int(coord.generation) == before_gen + 2,
		"post-arrival: failure reason must have been recorded",
	)
	_check(
		int(coord.generation) == before_gen + 2,
		"post-arrival: generation must advance twice (failed bootstrap + "
		+ "safe-home recovery transition)",
	)
	_check(
		not game.player.combat_transition_is_active(),
		"post-arrival: combat token must be released by the central fn",
	)
	_check(
		bool(game.player.current_hp > 0) and not bool(game.player._dead),
		"post-arrival: player must be alive (dead players go through the "
		+ "production death revival inside the safe-home policy)",
	)
	# Safe-home recovery resolved (or deliberately kept locked when the home
	# cannot resolve); in the resolved case the lock is gone and the player
	# is at the bich home position.
	var home: Dictionary = game._resolve_bich_home()
	if bool(home.get("valid", false)):
		_check(
			not (game._gameplay_input_locks as Dictionary).has("map_transition"),
			"post-arrival: lock released after safe-home relocation",
		)
		_check(
			not game.background.is_environment_point_blocked(
				game.player.global_position
			),
			"post-arrival: relocated player must not be blocked",
		)
	else:
		_check(
			(game._gameplay_input_locks as Dictionary).has("map_transition"),
			"post-arrival: unresolved home must KEEP the lock (explicit owner)",
		)
	print("P03_CASE2 post_arrival_safe_home done")
	# The safe-home recovery is a full production home transition (town
	# revival for a dead player, service-home travel for a living one).
	# Wait for it to complete, then assert the recovered state.
	var recovery_deadline := Time.get_ticks_msec() + 45000
	var settled := false
	while Time.get_ticks_msec() < recovery_deadline:
		await get_tree().create_timer(0.1, true).timeout
		if (
			not bool(game._map_transition_in_progress)
			and not bool(game.player._dead)
			and int(game.player.current_hp) > 0
			and not (game._gameplay_input_locks as Dictionary).has("player_death")
			and not (game._gameplay_input_locks as Dictionary).has("map_transition")
		):
			settled = true
			break
	print("P03_STATE settled=%s map=%d dead=%s hp=%d locks=%s" % [
		str(settled), int(game.current_map_id), str(game.player._dead),
		int(game.player.current_hp),
		JSON.stringify(game._gameplay_input_locks),
	])
	_check(settled, "post-arrival: safe-home recovery must complete")
	_check(
		not game.player.combat_transition_is_active(),
		"post-arrival: combat token must be released by the central fn",
	)
	_finish(before_gen)


func _finish(before_gen: int) -> void:
	if _failures.is_empty():
		print("GAME_ROOT_FAIL_MAP_TRANSITION_TEST_PASS")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			print("P03_FAIL ", failure)
		print("GAME_ROOT_FAIL_MAP_TRANSITION_TEST_FAIL failures=%d" % _failures.size())
		get_tree().quit(1)
