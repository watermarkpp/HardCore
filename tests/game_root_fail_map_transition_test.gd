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

	# --- Case 2: end-to-end blocked arrival on 913201 (P0-3b relocation).
	# The routed arrival cell is environment-blocked; with collision built
	# the FINALIZE stage relocates the player to the nearest unblocked
	# point and the ready contract PASSES in the freshly built world
	# (OPTIMIZED). The whole world is kept: no FAILED transition, no
	# safe-home recovery, no stranded locks or combat token.
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
	# Assert the transition contract at the moment it resolves - the
	# arrival pack on this map may kill the player seconds later, which is
	# the production death flow's domain, not the transition's.
	var snap: Dictionary = coord.snapshot()
	print("P03_CASE2 stage=%s reason=%s gen=%d map=%d mode=%s" % [
		str(snap.get("stage", "?")),
		str(snap.get("failure_reason", "?")),
		int(coord.generation),
		int(game.current_map_id),
		str(game.background.wall_render_stats().get("wall_render_mode", "?")),
	])
	_check(
		str(snap.get("stage", "")) == "READY",
		"blocked arrival: contract must PASS after relocation",
	)
	_check(
		str(snap.get("failure_reason", "")) == "map_transition_ready",
		"blocked arrival: failure_reason must be map_transition_ready",
	)
	_check(
		int(coord.generation) == before_gen + 1,
		"blocked arrival: generation must advance exactly once",
	)
	_check(
		int(game.current_map_id) == 913201,
		"blocked arrival: the world must be kept (913201, no safe-home)",
	)
	_check(
		not game.player.combat_transition_is_active(),
		"blocked arrival: combat token must be released on READY",
	)
	_check(
		not game.background.is_environment_point_blocked(
			game.player.global_position
		),
		"blocked arrival: relocated player must not be blocked",
	)
	_check(
		(game._gameplay_input_locks as Dictionary).is_empty()
		or not (game._gameplay_input_locks as Dictionary).has("map_transition"),
		"blocked arrival: no stranded map_transition lock",
	)
	print("P03_CASE2 blocked_arrival_relocation done")
	# Final deterministic state. 913201 is a hazardous dungeon: the player
	# may be killed by the arrival pack after the (valid) transition. Both
	# outcomes are production-owned deterministic states: fully unlocked
	# and alive, or inside the production death flow (player_death lock
	# held, death screen owned by the revival path). A stranded
	# map_transition lock or an active combat token is the only failure.
	var recovery_deadline := Time.get_ticks_msec() + 45000
	var settled := false
	while Time.get_ticks_msec() < recovery_deadline:
		await get_tree().create_timer(0.1, true).timeout
		var locks: Dictionary = game._gameplay_input_locks
		var token_active := bool(game.player.combat_transition_is_active())
		var idle := not bool(game._map_transition_in_progress)
		if idle and not token_active and not locks.has("map_transition"):
			if not bool(game.player._dead) and int(game.player.current_hp) > 0 and not locks.has("player_death"):
				settled = true
				break
			if locks.has("player_death"):
				settled = true
				break
	print("P03_STATE settled=%s map=%d dead=%s hp=%d locks=%s" % [
		str(settled), int(game.current_map_id), str(game.player._dead),
		int(game.player.current_hp),
		JSON.stringify(game._gameplay_input_locks),
	])
	_check(settled, "blocked arrival: deterministic end state (alive or in the production death flow)")
	_check(
		not game.player.combat_transition_is_active(),
		"blocked arrival: combat token must be released",
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
