extends Node

## WALL-P1R R6 STRICT: full-rollout consumer smoke with per-transition
## coordinator accountability (P0-1). Every hop captures a coordinator
## snapshot and asserts the strict transition contract:
##   stage == READY, success == true, failure_reason == "map_transition_ready",
##   map_transition lock absent, player combat token inactive, arrival map
##   match. Only then may the hop count toward PASS. A FAILED transition is
## recorded PERMANENTLY for that map - driver-side recovery may keep the
## chain moving so other maps can still be collected, but it never converts
## a FAILED hop into PASS - and the whole run exits 1.
## Usage: godot --headless --path . res://tests/wall_render_rollout_smoke.tscn

const AUTHORITY := preload("res://tools/wall_rollout_authority.gd")
const PLAN_DIR := "res://assets/data/runtime/map_editor/wall_render_plans"

var _failures: PackedStringArray = []
var _failed_maps: PackedStringArray = []
var _pass_count := 0
var _log_file: FileAccess = null


func _log(line: String) -> void:
	if _log_file == null:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("res://outputs/wall_perf")
		)
		_log_file = FileAccess.open(
			"res://outputs/wall_perf/r6_strict_live.log", FileAccess.WRITE
		)
	_log_file.store_line(line)
	_log_file.flush()
	print(line)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
	else:
		_failures.append(label)
		_log("R6_CHECK_FAIL " + label)


func _wait_bootstrap_idle(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while bool(game._world_bootstrap_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.016, true).timeout


func _recover(game: Node) -> void:
	# Driver-side recovery ONLY keeps the chain moving so other maps can be
	# collected; it never changes the verdict of an already-FAILED hop.
	var locks: Dictionary = game._gameplay_input_locks
	if locks.has("map_transition") and not bool(game._map_transition_in_progress):
		_log("R6_STAGE transition_lock_cleanup %s" % JSON.stringify(locks))
		# Release through the production path so the derived
		# _player_input_enabled flag is recomputed (direct erase leaves it
		# stale-false with an empty lock table).
		game._release_gameplay_input_lock(&"map_transition")
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


## P0-1 strict snapshot: everything the contract names, taken at the moment
## the target transition ends (or the moment the coordinator reports FAILED).
func _strict_snapshot(game: Node, map_key: String) -> Dictionary:
	var coord = game._world_bootstrap_coordinator
	var snap: Dictionary = coord.snapshot()
	var stats: Dictionary = game.background.wall_render_stats()
	return {
		"map_key": map_key,
		"stage": str(snap.get("stage", "?")),
		"success": bool(snap.get("success", false)),
		"failure_reason": str(snap.get("failure_reason", "?")),
		"coordinator_map_id": int(snap.get("map_id", -1)),
		"generation": int(coord.generation),
		"current_map_id": int(game.current_map_id),
		"transition_in_progress": bool(game._map_transition_in_progress),
		"locks": JSON.stringify(game._gameplay_input_locks),
		"map_transition_lock": bool(
			(game._gameplay_input_locks as Dictionary).has("map_transition")
		),
		"combat_token_active": bool(game.player.combat_transition_is_active()),
		"player_dead": bool(game.player._dead),
		"player_hp": int(game.player.current_hp),
		"wall_mode": str(stats.get("wall_render_mode", "?")),
		"plan_found": bool(stats.get("wall_render_plan_found", false)),
		"plan_valid": bool(stats.get("wall_render_plan_valid", false)),
		"dynamic_group_count": int(stats.get("dynamic_group_count", -1)),
		"static_chunk_count": int(stats.get("static_chunk_count", -1)),
		"composites": _count_meta(game, "editor_runtime_wall_composite"),
		"chunks": _count_meta(game, "wall_static_chunk"),
	}


## Strict travel. Returns the END-OF-TARGET-TRANSITION snapshot. A
## production safe-home recovery (P0-3) may chain a second transition right
## after a FAILED arrival - often within the same frame - so the FAILED
## snapshot is taken the moment the coordinator reports FAILED, and the
## chained recovery is then waited out so the chain can continue.
func _travel_strict(game: Node, map_id: int, map_key: String) -> Dictionary:
	var coord = game._world_bootstrap_coordinator
	var lock_deadline := Time.get_ticks_msec() + 15000
	_log("R6_STAGE travel_begin map=%d key=%s" % [map_id, map_key])
	while (
		not bool(game.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < lock_deadline
	):
		await _recover(game)
		await get_tree().create_timer(0.016, true).timeout
	if int(game.current_map_id) == map_id:
		# Already parked on this map (the initial world IS 910001): same-map
		# travel requests are rejected by production.
		var already := _strict_snapshot(game, map_key)
		already["hop_kind"] = "already_on_map"
		return already
	if not bool(game.gameplay_input_is_enabled()):
		var blocked := _strict_snapshot(game, map_key)
		blocked["hop_kind"] = "unreachable_input_locked"
		return blocked
	# Same protocol as the C10 matrix runner: headless/windowed runs make
	# _should_animate_map_transition() false, so _request_map_travel falls
	# back to the synchronous legacy _load_zone and bypasses the staged
	# wall-render pipeline entirely. Force the staged transition.
	# Sample the generation BEFORE the transition starts: in test_mode the
	# whole bootstrap (and a chained recovery) can complete within one
	# driver poll, so this is the only stable pre-transition baseline.
	var pre_generation := int(coord.generation)
	var op := Callable(game, "_travel_to_map_immediate").bind(map_id)
	if not game._begin_map_transition(op, map_id):
		var refused := _strict_snapshot(game, map_key)
		refused["hop_kind"] = "travel_refused"
		return refused
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
	# Poll until the target transition resolves: either the coordinator
	# reports FAILED (capture immediately - the production safe-home
	# recovery may chain its own transition without the flag ever going
	# observable false), the chained recovery has already overwritten the
	# stage (detected via the persistent last_failure audit trail), or the
	# flag clears on a READY contract. The target bootstrap's generation is
	# pre_generation + 1 (pre_generation was sampled before the request).
	var poll_deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < poll_deadline:
		var snap: Dictionary = coord.snapshot()
		var stage: String = str(snap.get("stage", ""))
		var generation := int(snap.get("generation", -1))
		var last_failure: Dictionary = coord.last_failure
		if (
			stage == "FAILED" and generation == pre_generation + 1
		) or (
			not last_failure.is_empty()
			and int(last_failure.get("generation", -1)) == pre_generation + 1
			and generation >= pre_generation + 1
		):
			# The target bootstrap FAILED and a chained recovery transition
			# already took over the coordinator: reconstruct the FAILED
			# evidence from the persistent audit trail.
			var failed := _strict_snapshot(game, map_key)
			failed["hop_kind"] = "transition_failed"
			failed["stage"] = "FAILED"
			failed["success"] = false
			failed["failure_reason"] = str(
				last_failure.get("reason", "unknown_chained_recovery")
			)
			failed["coordinator_map_id"] = int(
				last_failure.get("map_id", map_id)
			)
			failed["generation"] = pre_generation + 1
			failed["audit_source"] = "last_failure_persistent_trail"
			_log("R6_STRICT_FAILED_SNAPSHOT %s" % JSON.stringify(failed))
			var recovery_deadline := Time.get_ticks_msec() + 90000
			while (
				bool(game._map_transition_in_progress)
				and Time.get_ticks_msec() < recovery_deadline
			):
				await get_tree().create_timer(0.05, true).timeout
			var settle_deadline := Time.get_ticks_msec() + 30000
			while (
				bool(game._world_bootstrap_in_progress)
				and Time.get_ticks_msec() < settle_deadline
			):
				await get_tree().create_timer(0.05, true).timeout
			return failed
		if (
			not bool(game._map_transition_in_progress)
			and stage == "READY"
			and generation == pre_generation + 1
		):
			break
		await get_tree().create_timer(0.016, true).timeout
	await _wait_bootstrap_idle(game)
	var settled := _strict_snapshot(game, map_key)
	settled["hop_kind"] = "normal"
	return settled


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
	var previous_generation := int(game._world_bootstrap_coordinator.generation)
	for row: Dictionary in ordered:
		var map_key := str(row["map_key"])
		var map_id := int(row["map_id"])
		var klass := str(row["class"])
		var snap: Dictionary = await _travel_strict(game, map_id, map_key)
		var hop_kind := str(snap.get("hop_kind", "normal"))
		if hop_kind == "already_on_map":
			_log("R6_MAP already-on-map %s" % map_key)
		# P0-1 strict transition verdict - permanent, no cleanup conversion.
		var strict_ok := (
			hop_kind == "normal"
			or hop_kind == "already_on_map"
		) and (
			str(snap.get("stage", "")) == "READY"
			and bool(snap.get("success", false))
			and str(snap.get("failure_reason", "")) == "map_transition_ready"
			and not bool(snap.get("map_transition_lock", true))
			and not bool(snap.get("combat_token_active", true))
			and int(snap.get("current_map_id", -1)) == map_id
			and not bool(snap.get("transition_in_progress", true))
		)
		if not strict_ok:
			_failed_maps.append(map_key)
			_check(
				false,
				"%s: STRICT transition FAILED (%s stage=%s reason=%s gen=%d cur=%d locks=%s token=%s)" % [
					map_key, hop_kind, str(snap.get("stage", "?")),
					str(snap.get("failure_reason", "?")),
					int(snap.get("generation", -1)),
					int(snap.get("current_map_id", -1)),
					str(snap.get("locks", "?")),
					str(snap.get("combat_token_active", "?")),
				],
			)
			_log("R6_MAP_STRICT_FAIL %s %s" % [map_key, JSON.stringify(snap)])
			# Continue collecting other maps; this map stays FAILED.
			await _recover(game)
			previous_generation = int(
				game._world_bootstrap_coordinator.generation
			)
			continue
		if hop_kind != "already_on_map":
			_check(
				int(snap.get("generation", -1)) == previous_generation + 1,
				"%s: generation %d -> %d must advance by one" % [
					map_key, previous_generation,
					int(snap.get("generation", -1)),
				],
			)
			previous_generation = int(snap.get("generation", -1))
		var coord = game._world_bootstrap_coordinator
		if klass == "A":
			var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/%s.wall_render_plan.json" % [PLAN_DIR, map_key]
			))
			var groups := 0
			for entry: Dictionary in plan.get("atlas_entries", []):
				groups += entry.get("group_mappings", []).size()
			var chunks: int = plan.get("shadow_chunks", []).size()
			_check(
				str(snap.get("wall_mode", "")) == "OPTIMIZED"
				and bool(snap.get("plan_found", false))
				and bool(snap.get("plan_valid", false)),
				"%s: A mode/plan state mode=%s" % [
					map_key, str(snap.get("wall_mode", "?")),
				],
			)
			_check(
				int(snap.get("dynamic_group_count", -1)) == groups,
				"%s: groups %d != plan %d" % [
					map_key, int(snap.get("dynamic_group_count", -1)), groups,
				],
			)
			_check(
				int(snap.get("composites", -1)) == groups,
				"%s: composite nodes != %d" % [map_key, groups],
			)
			_check(
				int(snap.get("chunks", -1)) == chunks,
				"%s: chunk nodes != %d" % [map_key, chunks],
			)
			_residue_check(game, map_key)
			_check(
				int(coord.unexpected_sync_load_count) == 0,
				"%s: unexpected sync loads %d" % [
					map_key, int(coord.unexpected_sync_load_count),
				],
			)
		else:
			_check(
				str(snap.get("wall_mode", "")) == "LEGACY"
				and not bool(snap.get("plan_found", true)),
				"%s: B mode/plan state" % map_key,
			)
			_check(
				int(snap.get("composites", -1)) == 0
				and int(snap.get("chunks", -1)) == 0,
				"%s: B zero P1R nodes" % map_key,
			)
			_check(
				int(coord.unexpected_sync_load_count) == 0,
				"%s: B unexpected sync loads %d" % [
					map_key, int(coord.unexpected_sync_load_count),
				],
			)
		_log("R6_MAP_STRICT_OK %s class=%s mode=%s groups=%s chunks=%s" % [
			map_key, klass, str(snap.get("wall_mode", "?")),
			str(snap.get("dynamic_group_count", "?")),
			str(snap.get("static_chunk_count", "?")),
		])
	var a_ok := 0
	for row: Dictionary in ordered:
		if str(row["class"]) == "A":
			a_ok += 1
	if _failures.is_empty() and _failed_maps.is_empty():
		print("WALL_RENDER_R6_STRICT_PASS maps=%d a_maps=%d checks=%d" % [
			ordered.size(), a_ok, _pass_count,
		])
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			print("R6_FAIL ", failure)
		print("WALL_RENDER_R6_STRICT_FAIL maps=%d failed_maps=%s checks=%d" % [
			ordered.size(), str(_failed_maps), _pass_count,
		])
		get_tree().quit(1)
