extends Node

## One-shot world visual capture (diagnostic tool, user-requested self-test).
## Boots the production game scene, waits for the initial world, travels to
## the requested map, waits for the transition, captures the viewport and
## quits. Run windowed (real renderer), e.g.:
##   godot --display-driver windows --rendering-method gl_compatibility \
##       --audio-driver Dummy --resolution 2664x1200 \
##       res://tools/map_visual_capture.tscn -- <map name> <output path>

const TIMEOUT_MSEC := 120000

var _game: Node = null
var _map_name := "黑暗地带"
var _output_path := "outputs/map_visual_check.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_map_name = args[0]
	if args.size() >= 2:
		_output_path = args[1]
	PlayerState.test_mode = true
	_run.call_deferred()


func _run() -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_world_ready(deadline)
	print("CAPTURE initial world ready, traveling to ", _map_name)
	_game.change_zone(_map_name)
	await _wait_transition_done(deadline)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var resolved := _output_path if _output_path.is_absolute_path() else (
		ProjectSettings.globalize_path("res://" + _output_path)
	)
	DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	var error := image.save_png(resolved)
	print(
		"CAPTURE saved=", resolved, " error=", error,
		" size=", image.get_size()
	)
	get_tree().quit(0 if error == OK else 1)


func _wait_world_ready(deadline: int) -> void:
	while (
		bool(_game.get("_world_bootstrap_in_progress"))
		or bool(_game.get("_map_transition_in_progress"))
	):
		if Time.get_ticks_msec() > deadline:
			push_error("CAPTURE timeout waiting for initial world")
			get_tree().quit(1)
			return
		await get_tree().process_frame


func _wait_transition_done(deadline: int) -> void:
	await get_tree().process_frame
	while bool(_game.get("_map_transition_in_progress")):
		if Time.get_ticks_msec() > deadline:
			push_error("CAPTURE timeout waiting for map transition")
			get_tree().quit(1)
			return
		await get_tree().process_frame
