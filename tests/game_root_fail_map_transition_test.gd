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
	var before_stage := str(coord.snapshot().get("stage", ""))
	game._fail_map_transition(&"pre_arrival_keep_world")
	var notice_text := str(game.hud.notice_presenter.current_notice().get("message", ""))
	_check(notice_text == "地图切换失败，已保留当前区域，可稍后重试。", "map failure notice must not expose internal failure codes")
	_check(
		str(coord.snapshot().get("stage", "")) == before_stage,
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

	# --- Case 2b: post_arrival_safe_home policy through the central owner.
	# A real post-arrival FAILED transition must route the player back to
	# the service home WORLD with no stranded map_transition lock and no
	# combat token. A living player must start that recovery immediately -
	# the 5s death-settle window is only for hp<=0 players whose death
	# settlement has not landed yet.
	var op2 := Callable(game, "_travel_to_map_immediate").bind(913202)
	# 913202's arrival pack can kill the player between READY and the
	# failure injection; pad HP so the living-player branch is genuinely
	# exercised (the death branch is covered by the production town
	# revival path and by case 2's settled-state clauses).
	game.player.max_hp = 9999
	game.player.current_hp = 9999
	if not game._begin_map_transition(op2, 913202):
		_check(false, "case 2b transition refused")
		_finish(before_gen)
		return
	# Test-mode cover may finish synchronously; only wait for active work.
	var settle2b := Time.get_ticks_msec() + 90000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < settle2b:
		await get_tree().create_timer(0.016, true).timeout
	_check(
		int(game.current_map_id) == 913202
		and str(coord.snapshot().get("stage", "")) == "READY",
		"case 2b: pre-failure travel to 913202 must be READY",
	)
	_check(
		not bool(game.player._dead) and int(game.player.current_hp) > 0,
		"case 2b: player must be alive to exercise the living-player branch",
	)
	var t0 := Time.get_ticks_msec()
	await game._fail_map_transition(&"post_arrival_safe_home")
	var central_ms := Time.get_ticks_msec() - t0
	_check(
		central_ms < 3000,
		"case 2b: living player must start safe-home immediately "
		+ "(%d ms, no 5s death-settle wait)" % central_ms,
	)
	var done2b := Time.get_ticks_msec() + 90000
	while (
		(bool(game._map_transition_in_progress)
			or int(game.current_map_id) != 910001)
		and Time.get_ticks_msec() < done2b
	):
		await get_tree().create_timer(0.05, true).timeout
	await get_tree().create_timer(0.5, true).timeout
	_check(
		int(game.current_map_id) == 910001,
		"case 2b: recovery must land the player in the home world",
	)
	_check(
		not bool(game.player._dead) and int(game.player.current_hp) > 0,
		"case 2b: living player must stay alive through safe-home",
	)
	_check(
		not (game._gameplay_input_locks as Dictionary).has("map_transition"),
		"case 2b: no stranded map_transition lock",
	)
	_check(
		not game.player.combat_transition_is_active(),
		"case 2b: no stranded combat token",
	)
	print("P03_CASE2B post_arrival_safe_home done (central=%d ms)" % central_ms)

	# --- Case 2: end-to-end blocked arrival on 913201 (P0-3b relocation).
	# The routed arrival cell is environment-blocked; with collision built
	# the FINALIZE stage relocates the player to the nearest unblocked
	# point and the ready contract PASSES in the freshly built world
	# (OPTIMIZED). The whole world is kept: no FAILED transition, no
	# safe-home recovery, no stranded locks or combat token.
	var before_gen_case2 := int(coord.generation)
	var op := Callable(game, "_travel_to_map_immediate").bind(913201)
	if not game._begin_map_transition(op, 913201):
		_check(false, "case 2 transition refused")
		_finish(before_gen)
		return
	# Test-mode cover may finish synchronously; only wait for active work.
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
		int(coord.generation) == before_gen_case2 + 1,
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
