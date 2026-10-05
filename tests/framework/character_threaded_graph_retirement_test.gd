extends Node

## Controlled engine/dependency characterization. No Hall, world, gameplay,
## profile mutation, synthetic loader or production replacement is involved.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_PATH := "res://scenes/main.tscn"
const ROOT_SCRIPT_PATH := "res://scripts/game_root.gd"
@export var warm_root_graph_on_main_thread := false
@export var root_script_only := false
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"controlled native dependency probe owns isolated user data")
	var started := Time.get_ticks_usec()
	var graph: Script
	if warm_root_graph_on_main_thread and not root_script_only:
		graph = load("res://scripts/game_root.gd") as Script
		check(graph != null and graph.can_instantiate(), "comparison loads the same Root graph on the actual main thread")
	var preparation_usec := Time.get_ticks_usec() - started
	var requested_path: String = ROOT_SCRIPT_PATH if root_script_only else SCENE_PATH
	var requested_type: String = "Script" if root_script_only else "PackedScene"
	var owner_label := "this process has no existing native retrieval owner for the exact main scene"
	if root_script_only: owner_label = "this process has no existing native retrieval owner for the exact Root Script"
	check(ResourceLoader.load_threaded_get_status(requested_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		owner_label)
	var error := ResourceLoader.load_threaded_request(requested_path, requested_type, false)
	var request_label := "one real background request accepts the unchanged main PackedScene"
	if root_script_only: request_label = "one real background request accepts the exact Root Script"
	check(error == OK, request_label)
	var status := ResourceLoader.load_threaded_get_status(requested_path)
	var deadline := Time.get_ticks_msec() + 20000
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(requested_path)
	var completion_label := "the accepted native main scene completes within the bounded probe"
	if root_script_only: completion_label = "the accepted native Root Script completes within the bounded probe"
	check(status == ResourceLoader.THREAD_LOAD_LOADED, completion_label)
	var obtained: Resource
	if error == OK: obtained = ResourceLoader.load_threaded_get(requested_path)
	var valid_obtained: bool = obtained is PackedScene
	if root_script_only:
		valid_obtained = obtained is Script and (obtained as Script).can_instantiate()
	var get_label := "one actual get returns the PackedScene and retires its one native retrieval right"
	if root_script_only: get_label = "one actual get returns an instantiable Script and retires its one native retrieval right"
	check(valid_obtained and ResourceLoader.load_threaded_get_status(requested_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		get_label)
	obtained = null; graph = null
	for frame in 8: await get_tree().process_frame
	var scene_id := "character_threaded_graph_warmed_retirement_test" if warm_root_graph_on_main_thread else "character_threaded_graph_retirement_test"
	if root_script_only: scene_id = "character_threaded_script_retirement_test"
	print("CHARACTER_THREADED_GRAPH_TRACE ", JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"warm_root_graph_on_main_thread":warm_root_graph_on_main_thread,"root_script_only":root_script_only,
		"requested_path":requested_path,"requested_type":requested_type,"request_error":error,
		"completion_status":status,"preparation_usec":preparation_usec,"elapsed_usec":Time.get_ticks_usec()-started,
		"final_native_status":ResourceLoader.load_threaded_get_status(requested_path),
		"scope":"real loader/dependency comparison only; native exit warning identity is in preserved stderr/verbose logs"}))
	var written := proof.write_receipt(scene_id, proof.records.size(), failures.size())
	print("CHARACTER_THREADED_GRAPH_", "PASS" if written and failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
