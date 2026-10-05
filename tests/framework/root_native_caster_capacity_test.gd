extends Node

## Controlled native ResourceLoader capacity counterexample. This fixture
## changes only test-owned user://.hcwarm files and registers one narrow loader.
## Root, registry queue, threaded requests, status, get, and retirement are real.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Visual := preload("res://scripts/monster_visual.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const SCENE_ID := "root_native_caster_capacity_test"
const TRACE_PATH := "res://outputs/test_logs/framework/root_native_caster_capacity_trace.json"
const MAX_IN_FLIGHT := 4

class GatedTextureLoader extends ResourceFormatLoader:
	var _gates: Dictionary = {} # Immutable after registration/thread launch.
	var _mutex := Mutex.new()
	var _entered: Dictionary = {}
	var _completed: Dictionary = {}

	func configure(gates_by_path: Dictionary) -> void:
		_gates = gates_by_path.duplicate()

	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["hcwarm"])

	func _handles_type(type: StringName) -> bool:
		return String(type) in ["Texture2D", "Resource"]

	func _get_resource_type(path: String) -> String:
		return "Texture2D" if path.ends_with(".hcwarm") and _gates.has(path) else ""

	func _recognize_path(path: String, type: StringName) -> bool:
		return path.ends_with(".hcwarm") and _gates.has(path) and String(type) in ["", "Texture2D", "Resource"]

	func _exists(path: String) -> bool:
		return path.ends_with(".hcwarm") and _gates.has(path) and FileAccess.file_exists(path)

	func _get_resource_uid(_path: String) -> int:
		return -1

	func _load(path: String, original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
		var key := original_path if _gates.has(original_path) else path
		if not _gates.has(key):
			return ERR_FILE_UNRECOGNIZED
		_mutex.lock()
		_entered[key] = int(_entered.get(key, 0)) + 1
		_mutex.unlock()
		var gate: Semaphore = _gates[key]
		gate.wait()
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.25, 0.5, 0.75, 1.0))
		var texture := ImageTexture.create_from_image(image)
		_mutex.lock()
		_completed[key] = int(_completed.get(key, 0)) + 1
		_mutex.unlock()
		return texture

	func counters() -> Dictionary:
		_mutex.lock()
		var result := {"entered": _entered.duplicate(), "completed": _completed.duplicate()}
		_mutex.unlock()
		return result

var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var loader: GatedTextureLoader
var loader_registered := false
var paths: Array[String] = []
var owned_files: Array[String] = []
var gates: Array[Semaphore] = []
var gate_open: Array[bool] = []
var snapshots: Array[Dictionary] = []
var cleanup_gets: Array[String] = []
var native_after_exit: Dictionary = {}
var exit_budget: Dictionary = {}
var owner_destroyed := false
var reached_delivery := false
var counterexample_observed := false

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _open_gate(index: int) -> void:
	if index < 0 or index >= gates.size() or gate_open[index]:
		return
	gate_open[index] = true
	gates[index].post()

func _release_all() -> void:
	for index in gates.size():
		_open_gate(index)

func _capture(stage: String) -> Dictionary:
	var owner_paths: Array[String] = []
	if is_instance_valid(game):
		for path: String in game._frame_texture_threaded.keys():
			owner_paths.append(path)
	var native: Dictionary = {}
	for path: String in paths:
		native[path] = ResourceLoader.load_threaded_get_status(path)
	var row := {"stage": stage, "owner_paths": owner_paths,
		"owner_count": owner_paths.size(),
		"pending_count": CasterSkillVisualRegistry.pending_warm_path_count(),
		"native_status": native,
		"loader_counters": loader.counters() if loader != null else {}}
	snapshots.append(row)
	return row

func _run() -> void:
	var nonce := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	check(not nonce.is_empty() and not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty()
		and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(),
		"run, invocation, and source identities are present")
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"native fixture owns an isolated production user-data directory")
	if not failures.is_empty():
		_finish()
		return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade()
		and PlayerState.create_character("原生容量对照", "hc.profession.wizard").is_empty(),
		"distinct profile starts through production startup")
	if not failures.is_empty():
		_finish()
		return
	check(ContentLayers.feature_configuration().enabled_modules.is_empty(),
		"extension modules remain disabled")
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled() and not CasterSkillVisualRegistry.is_loading_window_active(),
		"mapped Root reaches READY with combat warm channel open")
	if not failures.is_empty():
		_finish()
		return
	# Only the fixture stops automatic Root frames; every observed pump below is
	# the real production method, with no fabricated request or clock step.
	deadline = Time.get_ticks_msec() + 5000
	while (not game._frame_texture_threaded.is_empty() or CasterSkillVisualRegistry.pending_warm_path_count() != 0) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	game.set_process(false)
	check(not game.is_processing() and game._frame_texture_threaded.is_empty()
		and CasterSkillVisualRegistry.pending_warm_path_count() == 0,
		"controlled pump starts with no inherited owner or pending requests")
	if not failures.is_empty():
		_finish()
		return

	var gates_by_path: Dictionary = {}
	for index in 6:
		var path := "user://caster_capacity_%s_%d.hcwarm" % [nonce.sha256_text().substr(0, 16), index]
		check(not FileAccess.file_exists(path), "fixture path %d does not preexist" % index)
		if not failures.is_empty():
			_finish()
			return
		var file := FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "fixture file %d opens" % index)
		if file == null:
			_finish()
			return
		owned_files.append(path)
		file.store_buffer(("HCWARM:%s:%d" % [nonce, index]).to_utf8_buffer())
		file.flush()
		check(file.get_error() == OK, "fixture file %d writes completely" % index)
		file.close()
		if not failures.is_empty():
			_finish()
			return
		check(not ResourceLoader.has_cached(path), "fixture path %d starts uncached" % index)
		paths.append(path)
		var gate := Semaphore.new()
		gates.append(gate)
		gate_open.append(false)
		gates_by_path[path] = gate
	if not failures.is_empty():
		_finish()
		return
	loader = GatedTextureLoader.new()
	loader.configure(gates_by_path)
	ResourceLoader.add_resource_format_loader(loader, true)
	loader_registered = true
	CasterSkillVisualRegistry.queue_sequence_warm(paths)
	check(CasterSkillVisualRegistry.pending_warm_path_count() == 6,
		"all six cold paths enter the real registry queue")
	game._pump_pending_warm_textures()
	var after_first := _capture("pump_1")
	check(int(after_first.owner_count) == 2 and int(after_first.pending_count) == 4,
		"first real pump owns two requests and retains four pending")
	game._pump_pending_warm_textures()
	var after_second := _capture("pump_2")
	check(int(after_second.owner_count) == MAX_IN_FLIGHT and int(after_second.pending_count) == 2,
		"second real pump owns four native requests and retains two pending")
	for index in 4:
		check(ResourceLoader.load_threaded_get_status(paths[index]) == ResourceLoader.THREAD_LOAD_IN_PROGRESS,
			"held native request %d remains IN_PROGRESS" % index)
	if not failures.is_empty():
		_finish()
		return

	_open_gate(0)
	deadline = Time.get_ticks_msec() + 10000
	while ResourceLoader.load_threaded_get_status(paths[0]) != ResourceLoader.THREAD_LOAD_LOADED and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var before_third := _capture("one_loaded_three_held_two_pending")
	check(int(before_third.native_status[paths[0]]) == ResourceLoader.THREAD_LOAD_LOADED
		and int(before_third.owner_count) == 4 and int(before_third.pending_count) == 2,
		"one completed request awaits collection while three are held and two remain pending")
	for index in range(1, 4):
		check(int(before_third.native_status[paths[index]]) == ResourceLoader.THREAD_LOAD_IN_PROGRESS,
			"native request %d is still unfinished before replacement" % index)
	if not failures.is_empty():
		_finish()
		return

	game._pump_pending_warm_textures()
	var after_third := _capture("pump_3_after_replacement")
	var native_live := 0
	for path: String in paths:
		if int(after_third.native_status[path]) in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED]:
			native_live += 1
	counterexample_observed = int(after_third.owner_count) == 5 and native_live == 5
	check(ResourceLoader.load_threaded_get_status(paths[0]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		and CasterSkillVisualRegistry.frame_texture_is_resident(paths[0]),
		"real Root collects and retains the first completed native texture")
	check(int(after_third.owner_count) <= MAX_IN_FLIGHT and native_live <= MAX_IN_FLIGHT,
		"replacement admission never exceeds four Root-owned native requests")
	# On the old pump this assertion records FAIL with owner_count=native_live=5;
	# cleanup and all-six delivery still run to retain evidence safely.
	_release_all()
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		game._pump_pending_warm_textures()
		var done: bool = game._frame_texture_threaded.is_empty() and CasterSkillVisualRegistry.pending_warm_path_count() == 0
		for path: String in paths:
			done = done and (CasterSkillVisualRegistry.frame_texture_is_resident(path)
				and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
		if done:
			reached_delivery = true
			break
		await get_tree().process_frame
	_capture("all_gates_open_after_drain")
	check(reached_delivery, "all six requests are delivered by Root with no lost pending path or native retrieval right")
	if reached_delivery:
		var counts := loader.counters()
		for path: String in paths:
			check(int(counts.entered.get(path, 0)) == 1 and int(counts.completed.get(path, 0)) == 1,
				"loader ran and completed exactly once for %s" % path)
	_finish()

func _finish() -> void:
	# The first teardown operation on every path, including early failures, is
	# to open every gate. Root._exit_tree may join a native get synchronously.
	_release_all()
	if is_instance_valid(game):
		var owner_ref: WeakRef = weakref(game)
		game.free()
		game = null
		owner_destroyed = owner_ref.get_ref() == null
	for path: String in paths:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
			ResourceLoader.load_threaded_get(path)
			cleanup_gets.append(path)
		native_after_exit[path] = ResourceLoader.load_threaded_get_status(path)
	exit_budget = Budget.snapshot()
	if reached_delivery:
		check(owner_destroyed and Visual.streaming_coordinator() == null
			and int(exit_budget.open_scopes) == 0,
			"Root owner and world access retire with all budget scopes closed")
		check(cleanup_gets.is_empty(), "fixture cleanup never substitutes for Root ownership")
		for path: String in paths:
			check(int(native_after_exit[path]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
				"native retrieval token is absent after Root exit for %s" % path)
	if loader_registered:
		ResourceLoader.remove_resource_format_loader(loader)
		loader_registered = false
	for path: String in owned_files:
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
			"only exact owned fixture is removed: %s" % path)
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/test_logs/framework")) == OK,
		"native capacity trace directory exists")
	var trace := FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	check(trace != null, "bounded native capacity trace opens")
	if trace != null:
		trace.store_string(JSON.stringify({"schema_version": 1,
			"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"scene_id": SCENE_ID, "max_in_flight": MAX_IN_FLIGHT,
			"fixture_paths": paths, "snapshots": snapshots,
			"loader_counters": loader.counters() if loader != null else {},
			"counterexample_observed": counterexample_observed,
			"reached_delivery": reached_delivery, "cleanup_gets": cleanup_gets,
			"native_after_exit": native_after_exit,
			"owner_destroyed": owner_destroyed, "exit_budget": exit_budget,
			"scope": "controlled production API capacity counterexample: real Root and ResourceLoader with six test-owned gated textures; not natural P6, combat, APK, or device evidence"}, "  "))
		trace.flush()
		check(trace.get_error() == OK, "native capacity trace writes completely")
		trace.close()
	var written := proof.write_receipt(SCENE_ID, proof.records.size(), failures.size())
	print("ROOT_NATIVE_CASTER_CAPACITY_", "PASS" if written and failures.is_empty() else "FAIL",
		" checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
