extends Node

## Cold, real ResourceLoader comparison only. The selected fixture path is a
## string: this probe never preloads, loads, instantiates, or factory-creates it
## before the one native threaded request.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

enum FixtureVariant { EMPTY_NODE, INFERRED_REFS, TYPED_REFS,
	SCRIPT_INFERRED_REF, SCRIPT_TYPED_REF, SCRIPT_STATIC_REF }
@export var fixture_variant: FixtureVariant = FixtureVariant.EMPTY_NODE

var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _selected_case() -> Dictionary:
	match fixture_variant:
		FixtureVariant.EMPTY_NODE:
			return {"scene_id": "threaded_minimal_empty_node_probe_test",
				"path": "res://tests/framework/fixtures/threaded_minimal_empty_node.tscn"}
		FixtureVariant.INFERRED_REFS:
			return {"scene_id": "threaded_minimal_inferred_refs_probe_test",
				"path": "res://tests/framework/fixtures/threaded_minimal_inferred_refs.tscn"}
		FixtureVariant.TYPED_REFS:
			return {"scene_id": "threaded_minimal_typed_refs_probe_test",
				"path": "res://tests/framework/fixtures/threaded_minimal_typed_refs.tscn"}
		FixtureVariant.SCRIPT_INFERRED_REF:
			return {"scene_id": "threaded_minimal_script_inferred_ref_probe_test",
				"path": "res://tests/framework/fixtures/threaded_minimal_script_inferred_ref.tscn"}
		FixtureVariant.SCRIPT_TYPED_REF:
			return {"scene_id": "threaded_minimal_script_typed_ref_probe_test",
				"path": "res://tests/framework/fixtures/threaded_minimal_script_typed_ref.tscn"}
		FixtureVariant.SCRIPT_STATIC_REF:
			return {"scene_id": "threaded_minimal_script_static_ref_probe_test",
				"path": "res://tests/framework/fixtures/threaded_minimal_script_static_ref.tscn"}
	return {}

func _run() -> void:
	var selected: Dictionary = _selected_case()
	var scene_id: String = str(selected.get("scene_id", "threaded_minimal_invalid_variant_probe_test"))
	var path: String = str(selected.get("path", ""))
	var started_usec: int = Time.get_ticks_usec()
	var trace := {"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"variant": int(fixture_variant), "scene_id": scene_id, "selected_path": path,
		"scope": "real cold threaded PackedScene request/get only; native exit warnings require preserved runner logs"}
	check(not selected.is_empty(), "the explicit enum selects exactly one minimal fixture path")
	var appdata: String = OS.get_environment("APPDATA").replace("\\", "/")
	check(appdata.contains("/.godot/runtime_appdata/")
		and not str(trace.run_id).is_empty() and not str(trace.invocation_id).is_empty()
		and not str(trace.source_content_sha256).is_empty() and not PlayerState.test_mode,
		"formal runner binds this isolated native process to a receipt identity")
	if selected.is_empty():
		_finish(scene_id, trace)
		return
	var status_before: int = ResourceLoader.load_threaded_get_status(path)
	var cached_before: bool = ResourceLoader.has_cached(path)
	trace["status_before"] = status_before
	trace["cached_before"] = cached_before
	var cold: bool = status_before == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and not cached_before
	check(cold, "the exact selected PackedScene has no cached resource or prior retrieval owner")
	if not cold:
		trace["request_attempted"] = false
		_finish(scene_id, trace)
		return
	var request_error := ResourceLoader.load_threaded_request(path, "PackedScene", false)
	trace["request_attempted"] = true
	trace["request_error"] = request_error
	check(request_error == OK, "one real background PackedScene request is accepted")
	var status: int = ResourceLoader.load_threaded_get_status(path)
	var deadline_msec: int = Time.get_ticks_msec() + 20000
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	trace["completion_status"] = status
	check(status == ResourceLoader.THREAD_LOAD_LOADED,
		"the one native request reaches LOADED within the bounded probe")
	var obtained: Resource
	if request_error == OK:
		obtained = ResourceLoader.load_threaded_get(path)
	var status_after_get: int = ResourceLoader.load_threaded_get_status(path)
	trace["obtained_packed_scene"] = obtained is PackedScene
	trace["status_after_get"] = status_after_get
	check(obtained is PackedScene and status_after_get == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"one actual get returns the PackedScene and consumes its native retrieval right")
	obtained = null
	for frame in 8:
		await get_tree().process_frame
	trace["final_native_status"] = ResourceLoader.load_threaded_get_status(path)
	trace["cached_after_release"] = ResourceLoader.has_cached(path)
	trace["elapsed_usec"] = Time.get_ticks_usec() - started_usec
	_finish(scene_id, trace)

func _finish(scene_id: String, trace: Dictionary) -> void:
	print("THREADED_MINIMAL_REF_TRACE ", JSON.stringify(trace))
	var written: bool = proof.write_receipt(scene_id, proof.records.size(), failures.size())
	print("THREADED_MINIMAL_REF_", "PASS" if written and failures.is_empty() else "FAIL",
		" scene_id=", scene_id, " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
