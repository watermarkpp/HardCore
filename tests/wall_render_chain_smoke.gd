extends Node

## WALL-P1R R7: long mixed-chain cross-map consumer smoke (>=15 hops).
## Sequence interleaves A (OPTIMIZED) and B (LEGACY plan-missing) maps,
## including re-entries of the same map. Per hop, assert on arrival:
##   1. node counts match EXACTLY the current map's plan (no residue from
##      the previous map: composite == groups, chunk nodes == chunks;
##      B maps must have zero P1R nodes)
##   2. zero legacy residue inside wall wrappers
##   3. zero unexpected sync loads
##   4. coordinator generation strictly increases by one per bootstrap
##   5. mode is OPTIMIZED (A) / LEGACY (B)
## Usage: godot --headless --path . res://tests/wall_render_chain_smoke.tscn

const AUTHORITY := preload("res://tools/wall_rollout_authority.gd")
const PLAN_DIR := "res://assets/data/runtime/map_editor/wall_render_plans"

var _failures: PackedStringArray = []
var _pass_count := 0
var _log_file: FileAccess = null


func _log(line: String) -> void:
	if _log_file == null:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("res://outputs/wall_perf")
		)
		_log_file = FileAccess.open(
			"res://outputs/wall_perf/r7_chain_live.log", FileAccess.WRITE
		)
	_log_file.store_line(line)
	_log_file.flush()
	print(line)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
	else:
		_failures.append(label)
		_log("R7_CHECK_FAIL " + label)


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


func _recover(game: Node) -> void:
	# Same driver protocol as the R6 smoke: revive through the production
	# path, and release stranded map_transition locks / combat tokens via
	# the production calls (a transition that ended through an early return
	# leaves both behind; headless also never animates transitions).
	var locks: Dictionary = game._gameplay_input_locks
	if (
		locks.has("map_transition")
		and not bool(game._map_transition_in_progress)
	):
		game._release_gameplay_input_lock(&"map_transition")
	if (
		game.player.combat_transition_is_active()
		and not bool(game._map_transition_in_progress)
	):
		game.player.finish_combat_transition(str(
			game.get_meta("map_combat_transition_token", "")
		))
	if not bool(game.player._dead) and int(game.player.current_hp) > 0:
		return
	_log("R7_STAGE revive")
	game._finish_death_revival()
	var deadline := Time.get_ticks_msec() + 10000
	while (
		bool(game.player._dead) and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.016, true).timeout


func _travel(game: Node, map_id: int) -> bool:
	var lock_deadline := Time.get_ticks_msec() + 15000
	while (
		not bool(game.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < lock_deadline
	):
		await _recover(game)
		await get_tree().create_timer(0.016, true).timeout
	if int(game.current_map_id) == map_id:
		return true
	if not bool(game.gameplay_input_is_enabled()):
		_log("R7_STAGE unreachable map=%d input=false" % map_id)
		return false
	var op := Callable(game, "_travel_to_map_immediate").bind(map_id)
	if not game._begin_map_transition(op, map_id):
		_log("R7_STAGE travel_refused map=%d" % map_id)
		return false
	var deadline := Time.get_ticks_msec() + 10000
	while (
		not bool(game._map_transition_in_progress)
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.016, true).timeout
	game.hud.loading_transition_covered.emit({
		"contract_id": "ui.loading.transition.v1",
		"transition_id": game._active_map_transition_id,
	})
	await get_tree().create_timer(0.016, true).timeout
	while bool(game._map_transition_in_progress):
		if Time.get_ticks_msec() > deadline + 60000:
			_log("R7_STAGE transition_timeout map=%d" % map_id)
			return false
		await _recover(game)
		await get_tree().create_timer(0.016, true).timeout
	var idle_deadline := Time.get_ticks_msec() + 30000
	while (
		bool(game._world_bootstrap_in_progress)
		and Time.get_ticks_msec() < idle_deadline
	):
		await get_tree().create_timer(0.016, true).timeout
	return true


func _ready() -> void:
	PlayerState.test_mode = true
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while (
		not bool(game.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.016, true).timeout
	game._monster_prefetch_enabled = false
	var authority := AUTHORITY.classify()
	if authority["error"] != "":
		printerr("R7_FAIL %s" % str(authority["error"]))
		get_tree().quit(1)
		return
	var id_by_key := {}
	var keys_by_id := {}
	for row: Dictionary in authority["rows"]:
		var map_id := int(row["map_id"])
		id_by_key[str(row["map_key"])] = map_id
		keys_by_id[map_id] = str(row["map_key"])
	# 16-hop mixed chain: A/B interleaved, dark and chiyue included, two
	# deliberate re-entries (910002 twice, dark twice at the tail).
	var chain_keys := [
		"bich_orc_tomb_f1", "world_snake_valley", "bich_orc_tomb_f2",
		"world_mengzhong_province", "mengzhong_dark_area",
		"world_fengmo_valley", "chiyue_valley", "world_cangyue_island",
		"bich_orc_tomb_f3", "world_white_day_gate", "bich_mine_f1",
		"mengzhong_between_life_and_death", "world_wooma_forest",
		"mengzhong_terror_space", "world_snake_valley",
		"mengzhong_dark_area",
	]
	var chain: Array = []
	for map_key: String in chain_keys:
		chain.append({"id": int(id_by_key[map_key]), "key": map_key})
	var previous_generation := int(
		game._world_bootstrap_coordinator.generation
	)
	var hops_ok := 0
	for hop: Dictionary in chain:
		var map_key := str(hop["key"])
		var map_id := int(hop["id"])
		var klass := "B"
		for row: Dictionary in authority["rows"]:
			if str(row["map_key"]) == map_key:
				klass = str(row["class"])
		_log("R7_HOP %s class=%s" % [map_key, klass])
		if not await _travel(game, map_id):
			_check(false, "%s: hop unreachable" % map_key)
			continue
		if int(game.current_map_id) != map_id:
			_check(false, "%s: arrival mismatch" % map_key)
			continue
		var generation := int(game._world_bootstrap_coordinator.generation)
		_check(
			generation == previous_generation + 1,
			"%s: generation %d -> %d" % [
				map_key, previous_generation, generation,
			],
		)
		previous_generation = generation
		var coord = game._world_bootstrap_coordinator
		var stats: Dictionary = game.background.wall_render_stats()
		if klass == "A":
			var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/%s.wall_render_plan.json" % [PLAN_DIR, map_key]
			))
			var groups := 0
			for entry: Dictionary in plan.get("atlas_entries", []):
				groups += entry.get("group_mappings", []).size()
			var chunks: int = plan.get("shadow_chunks", []).size()
			_check(
				str(stats["wall_render_mode"]) == "OPTIMIZED"
				and bool(stats["wall_render_plan_found"])
				and bool(stats["wall_render_plan_valid"]),
				"%s: mode/plan state" % map_key,
			)
			_check(
				_count_meta(game, "editor_runtime_wall_composite") == groups,
				"%s: composite residue/count != %d" % [map_key, groups],
			)
			_check(
				_count_meta(game, "wall_static_chunk") == chunks,
				"%s: chunk residue/count != %d" % [map_key, chunks],
			)
		else:
			_check(
				str(stats["wall_render_mode"]) == "LEGACY"
				and not bool(stats["wall_render_plan_found"]),
				"%s: B mode/plan state" % map_key,
			)
			_check(
				_count_meta(game, "editor_runtime_wall_composite") == 0
				and _count_meta(game, "wall_static_chunk") == 0,
				"%s: B zero P1R nodes" % map_key,
			)
		_residue_check(game, map_key)
		_check(
			int(coord.unexpected_sync_load_count) == 0,
			"%s: unexpected sync loads %d" % [
				map_key, int(coord.unexpected_sync_load_count),
			],
		)
		hops_ok += 1
		_log("R7_ARRIVED %s gen=%d mode=%s" % [
			map_key, generation, str(stats["wall_render_mode"]),
		])
	_check(hops_ok == chain.size(), "hops completed %d/%d" % [
		hops_ok, chain.size(),
	])
	if _failures.is_empty():
		print("WALL_RENDER_R7_CHAIN_PASS hops=%d checks=%d" % [
			chain.size(), _pass_count,
		])
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			print("R7_FAIL ", failure)
		print("WALL_RENDER_R7_CHAIN_FAIL failures=%d checks=%d" % [
			_failures.size(), _pass_count,
		])
		get_tree().quit(1)
