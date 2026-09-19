extends Node

## WALL-P0 formal-map benchmark matrix runner (diagnostic, read-only).
## Boots the production game, then for each requested map: change_zone,
## wait for the transition, stabilize, run one probe window, move on.
## Run windowed (real renderer), e.g.:
##   godot --display-driver windows --rendering-method gl_compatibility \
##       --audio-driver Dummy --resolution 2664x1200 \
##       res://tools/wall_perf_matrix_runner.tscn -- \
##       maps=黑暗地带,赤月峡谷 seconds=30 stabilize=8

const TIMEOUT_MSEC := 300000
const DEFAULT_MAPS := "比奇省,赤月峡谷,黑暗地带,石墓一层"
# User-reported lag hotspot: the first clamp-worm pack right after entering
# 黑暗地带 (top door cluster). Format "map_name:tx:ty;...".
const DEFAULT_HOTSPOTS := "黑暗地带:21:11"

var _game: Node = null
var _maps: PackedStringArray = DEFAULT_MAPS.split(",")
var _hotspots := {}
var _seconds := 30.0
var _stabilize := 8.0
# C10 A/B support: tag distinguishes opt/legacy captures; screenshot saves a
# same-spot PNG after each probe window for the pixel-diff gate.
var _tag := ""
var _screenshot := false
var _c10_summaries: Array = []
# Optional parallel list of runtime map ids: when present the runner uses
# the PRODUCTION staged travel (_request_map_travel) instead of the legacy
# change_zone path, so the wall render plan pipeline actually engages.
var _map_ids: PackedInt64Array = PackedInt64Array()
# P1-2: optional parallel list of registry map keys, index-aligned with
# maps/map_ids, so every report row carries its requested identity
# explicitly (no more rows[i] == maps[0] implicit semantics).
var _map_keys: PackedStringArray = PackedStringArray()


func _ready() -> void:
	PlayerState.test_mode = true
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"maps":
				_maps = pair[1].split(",")
			"hotspots":
				_parse_hotspots(pair[1])
			"seconds":
				_seconds = float(pair[1])
			"stabilize":
				_stabilize = float(pair[1])
			"tag":
				_tag = pair[1]
			"screenshot":
				_screenshot = pair[1] == "1"
			"map_ids":
				for id_text: String in pair[1].split(",", false):
					_map_ids.append(int(id_text))
			"map_keys":
				for key_text: String in pair[1].split(",", false):
					_map_keys.append(key_text.strip_edges())
	if _hotspots.is_empty():
		_parse_hotspots(DEFAULT_HOTSPOTS)
	_run.call_deferred()


func _parse_hotspots(raw: String) -> void:
	for entry: String in raw.split(";", false):
		var fields := entry.split(":")
		if fields.size() != 3:
			continue
		_hotspots[fields[0]] = Vector2i(int(fields[1]), int(fields[2]))


func _run() -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_world_ready(deadline)
	var background: Node = _game.get("background")
	assert(background != null, "game background missing")
	var probe: Node = preload(
		"res://scripts/wall_runtime_perf_probe.gd"
	).new()
	probe.configure(background, _game, false)
	_game.add_child(probe)
	for i: int in _maps.size():
		var label: String = _maps[i].strip_edges()
		if label.is_empty():
			continue
		print("WALL_PERF_MATRIX_TRAVEL map=%s tag=%s force_legacy=%s" % [
			label, _tag, OS.get_environment("WALL_RENDER_FORCE_LEGACY"),
		])
		if i < _map_ids.size() and _map_ids[i] > 0:
			# Production staged travel (WALL-P1R consumer pipeline), mirroring
			# the smoke-test protocol exactly: request, wait for the
			# transition to actually start, THEN emit covered; monster
			# prefetch stays off so the streaming coordinator cannot
			# interleave with the wall render manifest.
			_game._monster_prefetch_enabled = false
			# Force the ANIMATED (staged) transition path. _request_map_travel
			# falls back to the synchronous _load_zone legacy rebuild when
			# _should_animate_map_transition() is false (windowed runs), which
			# bypasses the wall render pipeline entirely - the opposite of
			# what C10 measures.
			var op := Callable(_game, "_travel_to_map_immediate").bind(
				_map_ids[i]
			)
			_ensure_player_ready_for_travel()
			if not _game._begin_map_transition(op, _map_ids[i]):
				var diag_player = _game.get("player")
				push_error("WALL_PERF travel failed map=%s in_progress=%s dead=%s hp=%s" % [
					label,
					str(_game.get("_map_transition_in_progress")),
					str(diag_player.get("_dead") if diag_player else "?"),
					str(diag_player.get("current_hp") if diag_player else "?"),
				])
				get_tree().quit(1)
				return
			var wait_start := Time.get_ticks_msec() + 10000
			while (
				not bool(_game.get("_map_transition_in_progress"))
				and Time.get_ticks_msec() < wait_start
			):
				await get_tree().process_frame
			_game.hud.loading_transition_covered.emit({
				"contract_id": "ui.loading.transition.v1",
				"transition_id": _game._active_map_transition_id,
			})
			await _wait_transition_done(deadline)
			var boot_deadline := Time.get_ticks_msec() + 60000
			while (
				bool(_game.get("_world_bootstrap_in_progress"))
				and Time.get_ticks_msec() < boot_deadline
			):
				await get_tree().process_frame
			if OS.get_environment("WALL_PERF_DEBUG") == "1":
				print("WALL_PERF_DEBUG current_map=%s has_runtime=%s runtime_empty=%s plan_exists=%s stats=%s" % [
					str(_game.get("current_map_id")),
					str(background.MapEditorRuntimeBridgeScript.has_runtime_map(913203)),
					str(background._runtime_data_for(913203).is_empty()),
					str(FileAccess.file_exists("res://assets/data/runtime/map_editor/wall_render_plans/mengzhong_dark_area.wall_render_plan.json")),
					str(background.wall_render_stats()),
				])
		else:
			_game.change_zone(label)
			await _wait_transition_done(deadline)
		# game_root may rebuild the WorldBackground node across transitions;
		# always measure the CURRENT background, never a detached one.
		background = _game.get("background")
		probe.configure(background, _game, false)
		if _hotspots.has(label):
			_pin_player_to_tile(label, _hotspots[label])
		await get_tree().create_timer(_stabilize).timeout
		_ensure_player_ready_for_travel()
		probe.start_window(label, _seconds)
		var summary: Dictionary = await probe.window_finished
		var mode_stats: Dictionary = background.wall_render_stats() if (
			background.has_method("wall_render_stats")
		) else {}
		summary["wall_render_stats"] = mode_stats
		summary["runner_tag"] = _tag
		summary["forced_legacy"] = (
			OS.get_environment("WALL_RENDER_FORCE_LEGACY") == "1"
		)
		# P1-2 formal row identity: every row names exactly what was
		# requested and what actually happened, so A/B pair validation
		# never depends on implicit rows[i] == maps[0] ordering.
		summary["requested_map_key"] = (
			_map_keys[i] if i < _map_keys.size() else ""
		)
		summary["requested_map_id"] = (
			int(_map_ids[i]) if i < _map_ids.size() else -1
		)
		summary["actual_current_map_id"] = int(_game.get("current_map_id"))
		summary["actual_zone_name"] = str(_game.get("current_zone"))
		summary["wall_render_mode"] = str(mode_stats.get("wall_render_mode", "?"))
		summary["viewport_size"] = [
			snappedf(get_viewport().get_visible_rect().size.x, 0.5),
			snappedf(get_viewport().get_visible_rect().size.y, 0.5),
		]
		summary["sample_count"] = int(
			(summary.get("frame_ms", {}) as Dictionary).get("samples", 0)
		)
		_c10_summaries.append(summary)
		if _screenshot:
			var image := get_viewport().get_texture().get_image()
			var shot_name := "wallshot_%s_%s.png" % [label, _tag]
			image.save_png("res://outputs/wall_perf/" + shot_name)
			summary["screenshot"] = shot_name
			print("WALL_PERF_SCREENSHOT file=%s" % shot_name)
		print(
			"WALL_PERF_MATRIX_RESULT map=%s tag=%s p95_ms=%s mode=%s draw_avg=%s" % [
				label, _tag,
				str(summary.get("frame_ms", {}).get("p95", "?")),
				str(mode_stats.get("wall_render_mode", "?")),
				str(summary.get("draw_calls", {}).get("avg", "?")),
			]
		)
	var report := {
		"contract_id": "hardcore.wall_render_c10_probe.v1",
		"runner_tag": _tag,
		"forced_legacy": OS.get_environment("WALL_RENDER_FORCE_LEGACY") == "1",
		"rows": _c10_summaries,
	}
	var report_path := "res://outputs/wall_perf/wallperf_c10_%s.json" % (
		_tag if not _tag.is_empty() else "untagged"
	)
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("WALL_PERF_C10_REPORT file=%s" % report_path)
	print("WALL_PERF_MATRIX_DONE maps=%d" % _maps.size())
	get_tree().quit(0)


func _pin_player_to_tile(map_name: String, tile: Vector2i) -> void:
	if _game == null or _game.get("player") == null:
		return
	# Use the game's own tile converter: player world space is the canonical
	# screen-px space from the map's projection profile, NOT raw ground px.
	var world: Vector2 = _game._canonical_grid_cell_to_screen_px(tile)
	if world == Vector2.INF or world == Vector2.ZERO:
		return
	_game._set_player_world_position(world)
	var background: Node = _game.get("background")
	if background != null and background.has_method("set_focus_position"):
		background.set_focus_position(world)
	print(
		"WALL_PERF_HOTSPOT map=%s tile=[%d,%d] world=[%.0f,%.0f]" % [
			map_name, tile.x, tile.y, world.x, world.y,
		]
	)


func _ensure_player_ready_for_travel() -> void:
	# The [21,11] hotspot is an active combat pack; the player can die during
	# a window and _begin_map_transition refuses travel for dead players.
	# Direct state surgery is acceptable in this measurement harness.
	var player = _game.get("player")
	if player == null:
		return
	if bool(player.get("_dead")):
		player.set("_dead", false)
	player.set("current_hp", player.get("max_hp"))


func _wait_world_ready(deadline: int) -> void:
	while (
		bool(_game.get("_world_bootstrap_in_progress"))
		or bool(_game.get("_map_transition_in_progress"))
	):
		if Time.get_ticks_msec() > deadline:
			push_error("WALL_PERF timeout waiting for initial world")
			get_tree().quit(1)
			return
		await get_tree().process_frame


func _wait_transition_done(deadline: int) -> void:
	await get_tree().process_frame
	while bool(_game.get("_map_transition_in_progress")):
		if Time.get_ticks_msec() > deadline:
			push_error("WALL_PERF timeout waiting for map transition")
			get_tree().quit(1)
			return
		await get_tree().process_frame
