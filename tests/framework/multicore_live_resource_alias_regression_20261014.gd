extends Node
const Core := preload("res://tests/framework/helpers/multicore_live_resource_alias_regression_20261014.gd")
var host: Object
var observer: Object
var held: Dictionary
var tick := 0
var closing := false
var checks := 0
var failures: Array[String] = []
var label := Label.new()
func check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures.append(name)
func _ready() -> void:
	add_child(label)
	host = ClassDB.instantiate("HardCoreSimulationHost")
	observer = ClassDB.instantiate("HardCoreResourceObservation")
	var handoff: Dictionary = host.capture_main_gameplay_random()
	check(handoff.size() == 4, "actual Main read-only coherent global capture")
	var world := {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":get_instance_id(),"world_epoch":1,"runtime_map_id":913203,"profile_id":"live_resource_fixture"}
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,
		"bridge_generation":57,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),
		"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb")) * 256,
		"primitive_request_capacity":65536,"primitive_result_capacity":65536,"live_primitive_capacity":2}
	check(host.start_clock_fixture(Core,{"world_identity":world,"gameplay_random_handoff":handoff},config), "actual S live transport fixture start")
func _process(_delta: float) -> void:
	if host == null:
		return
	var presentation: Dictionary = host.acquire_presentation(tick+1,16)
	if not presentation.is_empty():
		tick = int(presentation.tick)
		var frame: Dictionary = presentation.frame
		check(frame.valid, "S RNG owner and current Host qualification")
		host.ack_events(int(presentation.through_ordinal))
		if frame.done and not closing:
			closing = true
			host.request_close()
	if held.is_empty():
		held = host.acquire_pending_live_original_resource()
	if not held.is_empty() and tick >= 3:
		check(tick >= 3, "S H frames continued while Main withheld optional resource result")
		var request: Dictionary = held.request
		var delta: Dictionary = host.acquire_original_main_prefix(request.main_prefix)
		if delta.is_empty():
			return # Nonblocking contention; retain accepted packet for the next Main turn.
		check(not delta.is_empty(), "unique actual Main prefix delta")
		for event: Dictionary in delta.events:
			label.text = str(event.arguments[0])
		check(label.text == "actual prefix before live status", "Main prefix actually applied")
		check(host.ack_live_original_main_prefix(request.identity, request.main_prefix), "actual prefix ACK")
		check(host.validate_live_original_resource_ticket(request), "one actual API execution claim")
		check(not host.validate_live_original_resource_ticket(request), "duplicate execution refused")
		var cpu_start: int = host.sample_main_thread_cpu_usec()
		var started := Time.get_ticks_usec()
		var observation: Dictionary = observer.threaded_status(str(request.args[0]), Engine.get_process_frames(),57)
		var finished := Time.get_ticks_usec()
		var cpu_finish: int = host.sample_main_thread_cpu_usec()
		check(cpu_start >= 0 and cpu_finish >= cpu_start, "actual Main CPU counter")
		var reply := {"request":request,"executed":true,"disposition":&"executed_late","result":int(observation.status),
			"started_usec":started,"finished_usec":finished,"main_cpu_usec":cpu_finish-cpu_start,"completed_prefix_ordinal":1,
			"actual_lease_obligations":[],"native_observation":observation}
		check(host.submit_live_original_resource_result(request.identity,reply), "actual late ResourceLoader observation accepted")
		held = {}
	if closing and host.status().join_complete:
		check(host.close_and_join(), "Main safe async close after S settlement and real empty lease retirement")
		host = null
		print("LIVE_RESOURCE_FIXTURE ", {"status":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"scope":"actual Native Host component only"})
		get_tree().quit(0 if failures.is_empty() else 1)
