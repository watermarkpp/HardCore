extends Node

## Uses HUD's seven exact lazy-script paths and real native status/get API.
## No HUD, world, actor or feature runtime is instantiated.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const PATHS: Array[String] = ["res://scripts/inventory_panel.gd", "res://scripts/enhancement_panel.gd",
	"res://scripts/map_panel.gd", "res://scripts/skill_panel.gd", "res://scripts/quest_panel.gd",
	"res://scripts/warehouse_panel.gd", "res://scripts/shop_panel.gd"]
@export var use_sub_threads := false
@export var synchronous_load := false
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"), "panel loader characterization owns isolated data")
	var cold := true
	for path: String in PATHS:
		cold = cold and ResourceLoader.exists(path) and not ResourceLoader.has_cached(path)
	check(cold, "all seven exact panel scripts are cold before request admission")
	if synchronous_load:
		var synchronous_rows: Array[Dictionary] = []
		var started_usec := Time.get_ticks_usec()
		for path: String in PATHS:
			var resource: Script = ResourceLoader.load(path) as Script
			check(resource != null and resource.can_instantiate(), "synchronous native result is a usable panel script: " + path.get_file())
			var retired := ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
			check(retired, "synchronous load leaves no user threaded request: " + path.get_file())
			synchronous_rows.append({"path":path, "retired":retired, "process_frame":Engine.get_process_frames()})
		check(synchronous_rows.size() == 7 and Time.get_ticks_usec() - started_usec < 5000000,
			"same seven synchronous resources complete within the same five-second boundary")
		for frame in 4:
			await get_tree().process_frame
		_finish(synchronous_rows)
		return
	for path: String in PATHS:
		check(ResourceLoader.load_threaded_request(path, "", use_sub_threads) == OK, "real panel request accepts: " + path.get_file())
	var pending := PATHS.duplicate()
	var rows: Array[Dictionary] = []
	var deadline := Time.get_ticks_msec() + 5000
	while not pending.is_empty() and Time.get_ticks_msec() < deadline:
		for path: String in pending.duplicate():
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var resource: Script = ResourceLoader.load_threaded_get(path) as Script
				check(resource != null and resource.can_instantiate(), "native result is a usable panel script: " + path.get_file())
				var retired := ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
				check(retired, "collected panel path retires its user request: " + path.get_file())
				rows.append({"path":path, "retired":retired, "process_frame":Engine.get_process_frames()})
				pending.erase(path)
			elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
				check(false, "native panel request fails: " + path.get_file())
				pending.erase(path)
		if not pending.is_empty():
			await get_tree().process_frame
	check(pending.is_empty() and rows.size() == 7, "all seven exact panel requests complete within the unchanged deadline")
	for frame in 4:
		await get_tree().process_frame
	_finish(rows)

func _finish(rows: Array[Dictionary]) -> void:
	var scene_id := "threaded_panel_script_retirement_subthreads_test" if use_sub_threads else "threaded_panel_script_retirement_test"
	if synchronous_load:
		scene_id = "synchronous_panel_script_retirement_test"
	var file := FileAccess.open("res://outputs/test_logs/framework/" + scene_id.trim_suffix("_test") + "_trace.json", FileAccess.WRITE)
	check(file != null, "bounded panel loader evidence opens")
	if file != null:
		file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "use_sub_threads":use_sub_threads, "synchronous_load":synchronous_load,
			"rows":rows, "scope":"engine-only HUD's declared seven cold lazy scripts; default false matches its native request; no panels or world instantiated"}))
		file.flush()
		check(file.get_error() == OK, "panel loader evidence writes completely")
		file.close()
	var written := proof.write_receipt(scene_id, proof.records.size(), failures.size())
	print("THREADED_PANEL_SCRIPT_RETIREMENT_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
