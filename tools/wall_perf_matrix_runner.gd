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

var _game: Node = null
var _maps: PackedStringArray = DEFAULT_MAPS.split(",")
var _seconds := 30.0
var _stabilize := 8.0


func _ready() -> void:
	PlayerState.test_mode = true
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"maps":
				_maps = pair[1].split(",")
			"seconds":
				_seconds = float(pair[1])
			"stabilize":
				_stabilize = float(pair[1])
	_run.call_deferred()


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
	for map_name: String in _maps:
		var label := map_name.strip_edges()
		if label.is_empty():
			continue
		print("WALL_PERF_MATRIX_TRAVEL map=%s" % label)
		_game.change_zone(label)
		await _wait_transition_done(deadline)
		await get_tree().create_timer(_stabilize).timeout
		probe.start_window(label, _seconds)
		var summary: Dictionary = await probe.window_finished
		print(
			"WALL_PERF_MATRIX_RESULT map=%s p95_ms=%s" % [
				label, str(summary.get("frame_ms", {}).get("p95", "?")),
			]
		)
	print("WALL_PERF_MATRIX_DONE maps=%d" % _maps.size())
	get_tree().quit(0)


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
