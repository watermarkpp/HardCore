extends Node
const Proof = preload("res://tests/framework/helpers/check_receipt.gd")
const Service = preload("res://scripts/json_persistence_service.gd")
var proof = Proof.new()
var failures: Array[String] = []
var checks = 0
var worker = Thread.new()

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _run() -> void:
	PlayerState.test_mode = true
	check(Service.new().has_method("configure_owner"), "coordinator has explicit owner configuration")
	if failures.is_empty():
		get_tree().paused = true
		Engine.time_scale = 0.0
		check(worker.start(_on_simulation_owner) == OK, "Godot simulation owner thread starts")
		while worker.is_alive():
			await get_tree().process_frame
		var result: Dictionary = worker.wait_to_finish()
		check(bool(result.success), "simulation U service completes real durable JSON while paused and time scale zero")
		check(bool(result.callback_owner), "validator guard update and completion run on simulation owner")
		check(bool(result.immutable), "durable receipt document is immutable")
		check(bool(result.disk), "promoted document exists with approved contents")
		check(result.events == ["update", "validate", "guard", "guard", "complete"], "original approval and completion order remains")
		check(bool(result.empty), "owner drains every accepted request")
		Engine.time_scale = 1.0
		get_tree().paused = false
	if not proof.write_receipt("multicore_persistence_owner_20261014", checks, failures.size()): failures.append("receipt")
	print("MULTICORE_PERSISTENCE_OWNER_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _on_simulation_owner() -> Dictionary:
	var owner = OS.get_thread_caller_id()
	var service = Service.new()
	service.configure_owner("simulation")
	var events: Array[String] = []
	var callback_owner = [true]
	var receipts: Array = []
	var path = "user://v115_profile_owner_%d/result.json" % Time.get_ticks_usec()
	var validator = func(_document: Dictionary) -> Dictionary:
		callback_owner[0] = callback_owner[0] and OS.get_thread_caller_id() == owner
		events.append("validate")
		return {"valid": true, "terminal": false}
	var guard = func(_identity: Dictionary) -> bool:
		callback_owner[0] = callback_owner[0] and OS.get_thread_caller_id() == owner
		events.append("guard")
		return true
	var update = func(_previous: Dictionary, _identity: Dictionary) -> Dictionary:
		callback_owner[0] = callback_owner[0] and OS.get_thread_caller_id() == owner
		events.append("update")
		return {"profile_id": "old_profile", "gold": 123}
	var complete = func(receipt: Dictionary) -> void:
		callback_owner[0] = callback_owner[0] and OS.get_thread_caller_id() == owner
		events.append("complete")
		receipts.append(receipt)
	var job = service.submit(path, {"profile_id": "old_profile"}, {}, validator, guard, false, null, complete, false, null, "", false, update)
	var deadline = Time.get_ticks_msec() + 3000
	while not job.response.get("finished", false) and Time.get_ticks_msec() < deadline:
		service.pump()
		OS.delay_usec(100)
	var disk_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result = {"success": job.response.get("success", false), "callback_owner": callback_owner[0] and owner != OS.get_main_thread_id(),
		"immutable": job.response.get("document", {}).is_read_only(), "events": events,
		"disk": disk_document is Dictionary and disk_document.size() == 2 and disk_document.get("profile_id") == "old_profile" and disk_document.get("gold") == 123, "empty": service.pending_count() == 0}
	service.drain()
	return result