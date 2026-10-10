extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

func _check(condition: bool, label: String) -> void:
	_proof.record(condition, label)
	if not condition:
		push_error("startup/hall quit route contract: " + label)

func _ready() -> void:
	await _run()
	var failures := 0
	for item: Dictionary in _proof.records:
		if not bool(item.passed):
			failures += 1
	var receipt_ok := _proof.write_receipt(
		"startup_character_quit_route_contract_test",
		_proof.records.size(),
		failures,
	)
	if not receipt_ok:
		failures += 1
	print("STARTUP_CHARACTER_QUIT_ROUTE_CONTRACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _run() -> void:
	var startup: StartupLoading = load("res://scenes/startup_loading.tscn").instantiate()
	startup.auto_start = false
	startup.suppress_exit_for_test = true
	add_child(startup)
	await get_tree().process_frame
	startup._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check(bool(startup.startup_diagnostic().get("exit_requested", false)), "startup window close enters exiting state")
	_check(startup.startup_diagnostic().get("state", "") == "exiting", "startup window close publishes terminal state")
	startup._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check(startup.startup_diagnostic().get("state", "") == "exiting", "startup window close is idempotent")
	startup.queue_free()
	await get_tree().process_frame

	var hall: Control = load("res://scenes/character_select.tscn").instantiate()
	hall.suppress_quit_for_test = true
	add_child(hall)
	await get_tree().process_frame
	var generation_before := int(hall._launch_scene_preload_generation)
	hall._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check(bool(hall.quit_requested_for_test), "character hall window close requests quit")
	_check(not hall._launch_in_progress, "character hall window close clears launch ownership")
	_check(int(hall._launch_scene_preload_generation) > generation_before, "character hall window close invalidates preload generation")
	hall._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check(bool(hall.quit_requested_for_test), "character hall window close is idempotent")
	hall.queue_free()
	await get_tree().process_frame
