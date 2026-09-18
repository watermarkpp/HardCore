extends Node

## WALL-P1R R6: full-rollout consumer smoke over the release registry.
## For every A map (classification rebuilt in-process): real staged travel,
## then assert plan_found/plan_valid/OPTIMIZED, dynamic_group_count ==
## sum(entry.group_mappings) of the committed plan, actual composite nodes
## == dynamic_group_count, chunk nodes == plan shadow_chunks count, zero
## legacy residue inside wall wrappers, zero unexpected sync loads.
## For every B map: plan-missing LEGACY with zero P1R nodes.
## Usage: godot --headless --path . res://tests/wall_render_rollout_smoke.tscn

const AUTHORITY := preload("res://tools/wall_rollout_authority.gd")
const PLAN_DIR := "res://assets/data/runtime/map_editor/wall_render_plans"

var _failures: PackedStringArray = []
var _pass_count := 0
var _log_file: FileAccess = null


func _log(line: String) -> void:
	if _log_file == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/wall_perf"))
		_log_file = FileAccess.open("res://outputs/wall_perf/r6_smoke_live.log", FileAccess.WRITE)
	_log_file.store_line(line)
	_log_file.flush()
	print(line)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
	else:
		_failures.append(label)


func _wait_bootstrap_idle(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while bool(game._world_bootstrap_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.016, true).timeout


func _recover_player_death(game: Node) -> void:
	# Hazardous spawn points can kill the test player (death lock held until
	# the production revival path runs), and long staged chains can strand a
	# map_transition_local lock from a transition that ended through an early
	# return. Recover both so the chain can continue; neither hides a wall
	# render defect - the per-map assertions still run on arrival.
	var locks: Dictionary = game._gameplay_input_locks
	if not locks.has("player_death") and (
		locks.has("map_transition")
		and not bool(game._map_transition_in_progress)
	):
		_log("R6_STAGE transition_lock_cleanup %s" % JSON.stringify(locks))
		# Release through the production path so the derived
		# _player_input_enabled flag is recomputed (direct erase leaves it
		# stale-false with an empty lock table).
		game._release_gameplay_input_lock(&"map_transition")
	# A transition that ended through an early return also strands the
	# player's combat transition token (production clears it only on the
	# READY path); finish it through the same production call.
	if (
		game.player.combat_transition_is_active()
		and not bool(game._map_transition_in_progress)
	):
		_log("R6_STAGE combat_token_cleanup")
		game.player.finish_combat_transition(str(
			game.get_meta("map_combat_transition_token", "")
		))
	if not bool(game.player._dead) and int(game.player.current_hp) > 0:
		return
	_log("R6_STAGE player_death_recover")
	game._finish_death_revival()
	var deadline := Time.get_ticks_msec() + 10000
	while (
		(game._gameplay_input_locks as Dictionary).has("player_death")
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.016, true).timeout
	if (game._gameplay_input_locks as Dictionary).has("player_death"):
		_log("R6_STAGE revive_incomplete %s" % JSON.stringify(
			game._gameplay_input_locks
		))


func _travel(game: Node, map_id: int) -> void:
	var t0 := Time.get_ticks_msec()
	await _recover_player_death(game)
	# The map-transition input lock releases asynchronously after the
	# transition flag clears; wait for the lock itself, not a delay.
	var lock_deadline := Time.get_ticks_msec() + 15000
	var lock_ok := true
	_log("R6_STAGE travel_begin map=%d" % map_id)
	while (
		not bool(game.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < lock_deadline
	):
		# The player can die at any point (hazardous maps kill during/after
		# assertions); revive through the production path whenever detected.
		if bool(game.player._dead):
			await _recover_player_death(game)
		await get_tree().create_timer(0.016, true).timeout
	if not bool(game.gameplay_input_is_enabled()):
		lock_ok = false
	_log("R6_STAGE lock_wait_done map=%d input=%s" % [
		map_id, str(game.gameplay_input_is_enabled()),
	])
	if not lock_ok:
		_failures.append("UNREACHABLE map=%d (input lock never released)" % map_id)
		_log("R6_MAP_UNREACHABLE map_id=%d locks=%s dead=%s hp=%d token_active=%s input_flag=%s" % [
			map_id, JSON.stringify(game._gameplay_input_locks),
			str(game.player._dead), int(game.player.current_hp),
			str(game.player.combat_transition_is_active()),
			str(game._player_input_enabled),
		])
		return
	# Same protocol as the C10 matrix runner: headless/windowed runs make
	# _should_animate_map_transition() false, so _request_map_travel falls
	# back to the synchronous legacy _load_zone and bypasses the staged
	# wall-render pipeline entirely. Force the staged transition.
	var op := Callable(game, "_travel_to_map_immediate").bind(map_id)
	if not game._begin_map_transition(op, map_id):
		_check(
			false,
			"travel request failed map=%d input=%s" % [
				map_id, str(game.gameplay_input_is_enabled()),
			],
		)
		return
	_log("R6_STAGE request_accepted map=%d" % map_id)
	var deadline := Time.get_ticks_msec() + 10000
	while not bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.016, true).timeout
	game.hud.loading_transition_covered.emit({
		"contract_id": "ui.loading.transition.v1",
		"transition_id": game._active_map_transition_id,
	})
	await get_tree().create_timer(0.016, true).timeout
	while bool(game.get("_map_transition_in_progress")):
		if Time.get_ticks_msec() > deadline + 60000:
			_check(false, "transition timeout map=%d" % map_id)
			return
		await get_tree().create_timer(0.016, true).timeout
	await _wait_bootstrap_idle(game)
	while Time.get_ticks_msec() - t0 < 400:
		await get_tree().create_timer(0.016, true).timeout


func _count_meta(game: Node, meta: String) -> int:
	var count := 0
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and bool(node.get_meta(meta, false)):
			count += 1
	return count


func _residue_check(game: Node, label: String) -> void:
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and bool(
			node.get_meta("editor_runtime_wall_composite", false)
		):
			for child in node.get_parent().get_children():
				if child is Sprite2D and bool(
					child.get_meta("editor_runtime_instance", false)
				):
					_check(false, "%s: legacy residue in wrapper" % label)
					return


func _ready() -> void:
	PlayerState.test_mode = true
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not bool(game.gameplay_input_is_enabled()) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.016, true).timeout
	await _wait_bootstrap_idle(game)
	game._monster_prefetch_enabled = false
	var authority := AUTHORITY.classify()
	if authority["error"] != "":
		printerr("R6_FAIL %s" % str(authority["error"]))
		get_tree().quit(1)
		return
	var ordered: Array = []
	for row: Dictionary in authority["rows"]:
		ordered.append(row)
	for row: Dictionary in ordered:
		var map_key := str(row["map_key"])
		var map_id := int(row["map_id"])
		var klass := str(row["class"])
		if int(game.current_map_id) == map_id:
			# Already parked on this map (the initial world IS 910001):
			# same-map travel requests are rejected by production.
			_log("R6_MAP already-on-map %s" % map_key)
		else:
			await _travel(game, map_id)
		if int(game.current_map_id) != map_id:
			_check(false, "%s: arrival map mismatch" % map_key)
			continue
		var stats: Dictionary = game.background.wall_render_stats()
		var coord = game._world_bootstrap_coordinator
		if klass == "A":
			var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/%s.wall_render_plan.json" % [PLAN_DIR, map_key]
			))
			var groups := 0
			for entry: Dictionary in plan.get("atlas_entries", []):
				groups += entry.get("group_mappings", []).size()
			var chunks: int = plan.get("shadow_chunks", []).size()
			_check(bool(stats["wall_render_plan_found"]), "%s plan_found" % map_key)
			_check(bool(stats["wall_render_plan_valid"]), "%s plan_valid" % map_key)
			_check(
				str(stats["wall_render_mode"]) == "OPTIMIZED",
				"%s mode=%s" % [map_key, str(stats["wall_render_mode"])],
			)
			_check(
				int(stats["dynamic_group_count"]) == groups,
				"%s groups %d != plan %d" % [
					map_key, int(stats["dynamic_group_count"]), groups,
				],
			)
			_check(
				_count_meta(game, "editor_runtime_wall_composite") == groups,
				"%s composite nodes != %d" % [map_key, groups],
			)
			_check(
				_count_meta(game, "wall_static_chunk") == chunks,
				"%s chunk nodes != %d" % [map_key, chunks],
			)
			_residue_check(game, map_key)
			_check(
				int(coord.unexpected_sync_load_count) == 0,
				"%s sync loads %d" % [
					map_key, int(coord.unexpected_sync_load_count),
				],
			)
		else:
			_check(
				not bool(stats["wall_render_plan_found"]),
				"%s B plan_found" % map_key,
			)
			_check(str(stats["wall_render_mode"]) == "LEGACY", "%s B mode" % map_key)
			_check(
				_count_meta(game, "editor_runtime_wall_composite") == 0
				and _count_meta(game, "wall_static_chunk") == 0,
				"%s B zero P1R nodes" % map_key,
			)
			_check(
				int(coord.unexpected_sync_load_count) == 0,
				"%s B sync loads" % map_key,
			)
		_log("R6_MAP %s class=%s mode=%s groups=%s chunks=%s" % [
			map_key, klass, str(stats["wall_render_mode"]),
			str(stats["dynamic_group_count"]), str(stats["static_chunk_count"]),
		])
	var a_ok := 0
	for row: Dictionary in ordered:
		if str(row["class"]) == "A":
			a_ok += 1
	if _failures.is_empty():
		print("WALL_RENDER_R6_SMOKE_PASS maps=%d a_maps=%d checks=%d" % [
			ordered.size(), a_ok, _pass_count,
		])
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			print("R6_FAIL ", failure)
		print("WALL_RENDER_R6_SMOKE_FAIL failures=%d checks=%d" % [
			_failures.size(), _pass_count,
		])
		get_tree().quit(1)
