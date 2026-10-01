extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

# First P0 gate, to be installed in the new mirror after the R3 handoff.
# This observes the installed engine, including its catch-up and deferred work.
var rows: Array[Dictionary] = []
var physics_by_iteration: Dictionary = {}
var errors: Array[String] = []
var process_count := 0
var deferred_count := 0
var original_physics_ticks := 60
var injected_stall := false

func _ready() -> void:
	original_physics_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 120
	PlayerState.test_mode = true

func _physics_process(_delta: float) -> void:
	var iteration := Engine.get_process_frames()
	physics_by_iteration[iteration] = int(physics_by_iteration.get(iteration, 0)) + 1
	rows.append({"phase": "physics", "iteration": iteration, "physics": Engine.get_physics_frames()})
	_observe_deferred.call_deferred(iteration, "physics")

func _process(_delta: float) -> void:
	var iteration := Engine.get_process_frames()
	rows.append({"phase": "process", "iteration": iteration, "physics": Engine.get_physics_frames()})
	_observe_deferred.call_deferred(iteration, "process")
	process_count += 1
	if not injected_stall and process_count == 3:
		injected_stall = true
		# Intentional test-only foreground stall causes multiple real physics
		# steps in a later outer iteration; no actor callback is hand-driven.
		var deadline := Time.get_ticks_usec() + 100000
		while Time.get_ticks_usec() < deadline:
			pass
	if process_count == 30:
		_finish.call_deferred()

func _observe_deferred(expected_iteration: int, origin: String) -> void:
	deferred_count += 1
	rows.append({"phase": "deferred_" + origin, "iteration": Engine.get_process_frames(),
		"expected_iteration": expected_iteration, "physics": Engine.get_physics_frames()})
	_proof.record(Engine.get_process_frames() == expected_iteration,
		"native " + origin + " deferred epoch " + str(deferred_count))
	if Engine.get_process_frames() != expected_iteration:
		errors.append("deferred work crossed the observed outer-iteration epoch")

func _finish() -> void:
	set_process(false)
	set_physics_process(false)
	Engine.physics_ticks_per_second = original_physics_ticks
	var catch_up_observed := false
	for count: int in physics_by_iteration.values():
		catch_up_observed = catch_up_observed or count > 1
	_proof.record(catch_up_observed, "real multi-physics-step outer iteration")
	if not catch_up_observed:
		errors.append("no real multi-physics-step iteration was observed")
	_proof.record(deferred_count >= process_count, "all deferred observations complete")
	if deferred_count < process_count:
		errors.append("deferred observations were lost")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/test_logs/framework"))
	var file := FileAccess.open("res://outputs/test_logs/framework/frame_epoch.json", FileAccess.WRITE)
	_proof.record(file != null, "native frame trace file opens")
	if file == null:
		errors.append("evidence file could not be written")
	else:
		file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "rows": rows,
			"catch_up_observed": catch_up_observed, "errors": errors}, "  "))
	if not _proof.write_receipt("frame_epoch_test", _proof.records.size(), errors.size()):
		errors.append("framework assertion receipt failed")
	print(("FRAMEWORK_FRAME_EPOCH_PASS" if errors.is_empty() else "FRAMEWORK_FRAME_EPOCH_FAIL")
		+ " observations=" + str(rows.size()) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
