extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")

var proof := Proof.new()
var failures: Array[String] = []
var game: Node

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "negative fixture reaches READY before fault injection")
	if game.gameplay_input_is_enabled():
		var path := "user://v109_owner_failed_%d.png" % Time.get_ticks_msec()
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("not-a-png")
		file.close()
		var malformed_paths: Array[String] = [path]
		var pump: Dictionary = await game._prewarm_texture_paths_until(
			malformed_paths, Time.get_ticks_usec() + 1000000
		)
		check(int(pump.get("failed", 0)) == 1, "accepted malformed texture reaches FAILED handling")
		check(game._loading_texture_threaded.is_empty(), "prewarm owner retires local FAILED claim")
		check(int(pump.get("completed", 0)) == 0, "FAILED claim is consumed without a second native get")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	var written := proof.write_receipt(
		"v109_world_owner_negative_test", proof.records.size(), failures.size()
	)
	print("V109_WORLD_OWNER_NEGATIVE_", "PASS" if written and failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
