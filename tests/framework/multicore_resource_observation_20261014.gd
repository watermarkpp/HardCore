extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()

class ControlledLoader:
	extends ResourceFormatLoader
	var gate := Semaphore.new()
	var started := Semaphore.new()
	func _get_recognized_extensions() -> PackedStringArray: return PackedStringArray(["hcobservation"])
	func _handles_type(type: StringName) -> bool: return type == &"Resource"
	func _get_resource_type(_path: String) -> String: return "Resource"
	func _exists(path: String) -> bool: return FileAccess.file_exists(path)
	func _load(_path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
		started.post()
		gate.wait()
		var result := Resource.new()
		result.resource_name = "HardCore actual loader observation fixture"
		return result

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	proof.record(condition, label)

func _finish() -> void:
	var failed := 0
	for record: Dictionary in proof.records:
		if not record.passed: failed += 1
	if not proof.write_receipt("multicore_resource_observation_20261014", proof.records.size(), failed): failed += 1
	print("MULTICORE_RESOURCE_OBSERVATION_%s" % ("PASS" if failed == 0 else "FAIL"))
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	_check(ClassDB.class_exists("HardCoreResourceObservation"), "production native status observation API exists")
	if not ClassDB.class_exists("HardCoreResourceObservation"):
		_finish()
		return
	var port: RefCounted = ClassDB.instantiate("HardCoreResourceObservation")
	_check(port.has_method("threaded_status") and port.has_method("retire_generation"), "exact status and namespace retirement ABI exists")
	if not port.has_method("threaded_status") or not port.has_method("retire_generation"):
		_finish()
		return
	var path := "user://actual_loader.hcobservation"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "isolated fixture source created")
	if file == null:
		_finish()
		return
	file.store_string("source-bound actual ResourceLoader fixture")
	file.close()
	var loader := ControlledLoader.new()
	ResourceLoader.add_resource_format_loader(loader, true)
	var request := ResourceLoader.load_threaded_request(path, "Resource", false, ResourceLoader.CACHE_MODE_IGNORE)
	_check(request == OK, "actual threaded request admitted once")
	if request != OK:
		ResourceLoader.remove_resource_format_loader(loader)
		_finish()
		return
	var deadline := Time.get_ticks_msec() + 2000
	var started := loader.started.try_wait()
	while not started and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		started = loader.started.try_wait()
	_check(started, "real loader task reached held source boundary")
	if started:
		var first: Dictionary = port.call("threaded_status", path, 77, 91)
		var repeated: Dictionary = port.call("threaded_status", path, 77, 91)
		var next: Dictionary = port.call("threaded_status", path, 78, 91)
		var other: Dictionary = port.call("threaded_status", path, 78, 92)
		var old_again: Dictionary = port.call("threaded_status", path, 78, 91)
		_check(first.ok and first.status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not first.progress_ensured, "first real status observes original IN_PROGRESS without repeat progression")
		_check(repeated.ok and repeated.progress_ensured, "same logic P repeats original ensure-load-progress branch")
		_check(next.ok and not next.progress_ensured, "next logic P does not inherit Main frame number")
		_check(other.ok and not other.progress_ensured and old_again.progress_ensured, "incarnations retain independent task observations without overwriting accepted old namespace")
		_check(first.observation_process_epoch == 77 and first.bridge_generation == 91 and first.actual_end_usec >= first.actual_start_usec, "true observation identity and wall-time receipt retained")
		var progress: Array = []
		_check(ResourceLoader.load_threaded_get_status(path, progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS, "ordinary ResourceLoader API remains valid")
		var after_ordinary: Dictionary = port.call("threaded_status", path, 78, 91)
		_check(after_ordinary.progress_ensured, "ordinary poll cannot overwrite registered simulation epoch")
		var invalid: Dictionary = port.call("threaded_status", path, -1, 91)
		_check(not invalid.ok and not invalid.has("status"), "invalid observation is explicit protocol failure rather than guessed loader status")
	# Always unblock and collect the accepted request, even after a check fails.
	loader.gate.post()
	var resource: Resource = ResourceLoader.load_threaded_get(path)
	_check(resource != null and resource.resource_name == "HardCore actual loader observation fixture", "one original GET collects actual resource after release")
	var after_get: Dictionary = port.call("threaded_status", path, 79, 91)
	_check(after_get.ok and after_get.status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "consumed user token retains original INVALID_RESOURCE result")
	_check(port.call("retire_generation", 91).ok and port.call("retire_generation", 92).ok, "completed namespaces retire after accepted request collected")
	ResourceLoader.remove_resource_format_loader(loader)
	resource = null
	port = null
	loader = null
	_finish()
