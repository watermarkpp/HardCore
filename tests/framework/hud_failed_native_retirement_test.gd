extends Node

## Controlled regression. Controlled HUD ownership injection over a real native FAILED token.
## This does not claim a natural UI trigger or measure production get() calls.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const PANEL_PATHS: Array[String] = [
	"res://scripts/inventory_panel.gd",
	"res://scripts/enhancement_panel.gd",
	"res://scripts/map_panel.gd",
	"res://scripts/skill_panel.gd",
	"res://scripts/quest_panel.gd",
	"res://scripts/warehouse_panel.gd",
	"res://scripts/shop_panel.gd",
]
const DAMAGE_BYTES := "OWNED_HUD_FAILED"
const INVALID := ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
const IN_PROGRESS := ResourceLoader.THREAD_LOAD_IN_PROGRESS
const LOADED := ResourceLoader.THREAD_LOAD_LOADED
const FAILED := ResourceLoader.THREAD_LOAD_FAILED

class InertHUD extends "res://scripts/hud.gd":
	func _ready() -> void:
		set_process(false)

@export var exit_without_poll := false
var proof := Proof.new()
var failures: Array[String] = []
var evidence: Dictionary = {}
var owned_path := ""
var owns_path := false
var hud_owner: InertHUD
var panel_warm_refs: Array[Script] = []
var fixture_supplemental_get_count := 0
var fixture_precondition_get_count := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _scene_id() -> String:
	return "hud_failed_native_exit_retirement_test" if exit_without_poll else "hud_failed_native_poll_retirement_test"

func _identity() -> Dictionary:
	return {
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
	}

func _status() -> int:
	return ResourceLoader.load_threaded_get_status(owned_path)

func _write_exact_bytes(bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(owned_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	return okay

func _collect_precondition_request() -> void:
	if owned_path.is_empty():
		return
	var status := _status()
	if status in [IN_PROGRESS, LOADED, FAILED]:
		var unused: Resource = ResourceLoader.load_threaded_get(owned_path)
		fixture_precondition_get_count += 1
		evidence["precondition_cleanup_result_is_null"] = unused == null
	evidence["native_after_precondition_cleanup"] = _status()

func _run() -> void:
	var identity := _identity()
	evidence = identity.merged({
		"scene_id": _scene_id(),
		"exit_without_poll": exit_without_poll,
		"scope": "controlled test-owned user:// binary GDScript FAILED token injected into actual HUD pending dictionary; inherited HUD poll/exit; not natural UI, Loading, GPU, combat, APK, or device evidence",
		"get_call_count": "MISSING",
		"get_call_count_scope": "native status is measured; no instrumentation of production ResourceLoader.load_threaded_get call count",
	})
	var isolated := OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/")
	check(isolated and not PlayerState.test_mode, "real PlayerState mode and runner-isolated APPDATA")
	check(not str(identity.run_id).is_empty() and not str(identity.invocation_id).is_empty()
		and str(identity.source_content_sha256).length() == 64,
		"runner supplies run, invocation, and source identity")
	if not failures.is_empty():
		_finish()
		return

	# A deliberate main-thread control prevents this probe from classifying the
	# seven existing panel scripts' threaded compilation as an owned-file result.
	for path: String in PANEL_PATHS:
		var panel_script: Script = ResourceLoader.load(path) as Script
		check(panel_script != null and panel_script.can_instantiate(),
			"declared panel Script prewarms on the main thread: " + path.get_file())
		if panel_script != null:
			panel_warm_refs.append(panel_script)
	if not failures.is_empty():
		_finish()
		return

	var nonce := str(identity.run_id).validate_filename()
	owned_path = "user://hud_failed_native_%s_%d_%s.res" % [nonce, OS.get_process_id(),
		"exit" if exit_without_poll else "poll"]
	evidence["owned_path"] = owned_path
	check(not FileAccess.file_exists(owned_path), "this invocation owns a previously absent exact fixture path")
	if not failures.is_empty():
		_finish()
		return
	var owned_script: GDScript = GDScript.new()
	owned_script.source_code = "extends RefCounted\n"
	var reload_error := owned_script.reload()
	check(reload_error == OK and owned_script.can_instantiate(), "in-memory GDScript compiles before binary save")
	if not failures.is_empty():
		owned_script = null
		_finish()
		return
	var save_error := ResourceSaver.save(owned_script, owned_path)
	owns_path = FileAccess.file_exists(owned_path)
	evidence["binary_save_error"] = save_error
	check(save_error == OK and owns_path, "GDScript saves as a test-owned binary .res")
	owned_script = null
	if not failures.is_empty():
		_finish()
		return
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(owned_path)
	evidence["original_size"] = original_bytes.size()
	check(original_bytes.size() > DAMAGE_BYTES.length(), "original binary bytes are captured before damage")
	check(not ResourceLoader.has_cached(owned_path), "saved script references are released and native cache is cold")
	if not failures.is_empty():
		_finish()
		return
	check(_write_exact_bytes(DAMAGE_BYTES.to_utf8_buffer()), "only owned binary .res receives controlled corrupt bytes")
	if not failures.is_empty():
		_finish()
		return
	var request_error := ResourceLoader.load_threaded_request(owned_path)
	evidence["failed_request_error"] = request_error
	check(request_error == OK, "native ResourceLoader accepts the corrupted owned-file request")
	if request_error != OK:
		_finish()
		return
	evidence["native_after_failed_request"] = _status()
	hud_owner = InertHUD.new()
	add_child(hud_owner)
	check(hud_owner._panel_script_pending.is_empty(), "inert real HUD begins with no registered panel requests")
	hud_owner._panel_script_pending[owned_path] = true
	evidence["owner_pending_after_controlled_admission"] = hud_owner._panel_script_pending.keys()
	check(hud_owner._panel_script_pending.has(owned_path), "accepted native request enters HUD's actual pending owner dictionary")
	var deadline := Time.get_ticks_msec() + 5000
	var status := _status()
	while status == IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		status = _status()
	evidence["native_before_owner_action"] = status
	check(status == FAILED, "owned corrupt binary reaches actual native FAILED without get")
	if status != FAILED:
		_collect_precondition_request()
		_finish()
		return

	if exit_without_poll:
		remove_child(hud_owner)
		evidence["owner_pending_after_action"] = hud_owner._panel_script_pending.keys()
		hud_owner.free()
		hud_owner = null
	else:
		var result: Dictionary = await hud_owner._prefetch_panel_scripts(true)
		evidence["prefetch_result"] = result
		evidence["owner_pending_after_action"] = hud_owner._panel_script_pending.keys()
		var saw_owned_failure := false
		var saw_unrelated_failure := false
		for failure: String in result.get("failures", []):
			if failure.begins_with(owned_path + ":"):
				saw_owned_failure = true
			else:
				saw_unrelated_failure = true
		check(saw_owned_failure and not saw_unrelated_failure,
			"poll reports exactly the controlled FAILED path, with no unrelated panel failures")
	var after_action := _status()
	evidence["native_after_owner_action"] = after_action
	check(after_action == INVALID, "actual HUD owner action retires its accepted FAILED native token")
	check(evidence["owner_pending_after_action"].is_empty(),
		"actual HUD owner action leaves the whole pending dictionary empty")

	# RED cleanup follows the assertions. Its count remains visible even when
	# the owner dropped the path, so test-only retrieval cannot make RED green.
	if after_action in [FAILED, IN_PROGRESS, LOADED]:
		var unused: Resource = ResourceLoader.load_threaded_get(owned_path)
		fixture_supplemental_get_count = 1
		evidence["fixture_supplemental_result_is_null"] = unused == null
	evidence["fixture_supplemental_get_count"] = fixture_supplemental_get_count
	evidence["native_after_fixture_cleanup"] = _status()
	check(fixture_supplemental_get_count == 0,
		"fixture needs zero supplemental get calls after real HUD ownership closes")
	check(_status() == INVALID, "owned FAILED request is retired before restoring its bytes")
	if is_instance_valid(hud_owner):
		remove_child(hud_owner)
		hud_owner.free()
		hud_owner = null
	if _status() != INVALID:
		_finish()
		return

	check(_write_exact_bytes(original_bytes), "same owned path receives its exact original bytes")
	check(FileAccess.get_file_as_bytes(owned_path) == original_bytes,
		"restored byte sequence equals the captured original sequence")
	check(not ResourceLoader.has_cached(owned_path), "restored path is uncached before independent retry")
	if FileAccess.get_file_as_bytes(owned_path) != original_bytes or ResourceLoader.has_cached(owned_path):
		_finish()
		return
	var retry_error := ResourceLoader.load_threaded_request(owned_path)
	evidence["retry_request_error"] = retry_error
	check(retry_error == OK, "same restored path accepts a second native request")
	if retry_error != OK:
		_finish()
		return
	evidence["native_after_retry_request"] = _status()
	deadline = Time.get_ticks_msec() + 5000
	status = _status()
	while status == IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		status = _status()
	evidence["native_before_retry_get"] = status
	check(status == LOADED, "same restored path reaches native LOADED")
	var retry_script: Script
	var retry_get_count := 0
	if status in [IN_PROGRESS, LOADED, FAILED]:
		retry_script = ResourceLoader.load_threaded_get(owned_path) as Script
		retry_get_count = 1
	evidence["retry_get_count"] = retry_get_count
	evidence["retry_script_nonnull"] = retry_script != null
	evidence["native_after_retry_get"] = _status()
	check(retry_get_count == 1 and retry_script != null and retry_script.can_instantiate(),
		"one native get returns a usable Script from the restored binary")
	check(_status() == INVALID, "restored binary request retires after one get")
	retry_script = null
	_finish()

func _finish() -> void:
	if is_instance_valid(hud_owner):
		remove_child(hud_owner)
		hud_owner.free()
		hud_owner = null
	evidence["fixture_supplemental_get_count"] = fixture_supplemental_get_count
	evidence["fixture_precondition_get_count"] = fixture_precondition_get_count
	if owns_path:
		var final_status := _status()
		evidence["native_before_fixture_file_delete"] = final_status
		if final_status in [IN_PROGRESS, LOADED, FAILED]:
			var unused: Resource = ResourceLoader.load_threaded_get(owned_path)
			fixture_precondition_get_count += 1
			evidence["final_safety_cleanup_result_is_null"] = unused == null
		check(_status() == INVALID, "test-owned request is retired before exact file deletion")
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(owned_path)) == OK,
			"only this invocation's exact owned binary file is deleted")
		evidence["native_after_fixture_file_delete"] = _status()
		evidence["fixture_precondition_get_count"] = fixture_precondition_get_count
	var trace_directory := "res://outputs/test_logs/framework"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trace_directory)) == OK,
		"isolated native trace directory is available")
	var trace_path := trace_directory.path_join(_scene_id().trim_suffix("_test") + "_trace.json")
	var trace := FileAccess.open(trace_path, FileAccess.WRITE)
	check(trace != null, "bounded native FAILED token trace opens")
	if trace != null:
		evidence["checks"] = proof.records
		evidence["failures"] = failures
		trace.store_string(JSON.stringify(evidence, "  "))
		trace.flush()
		check(trace.get_error() == OK, "native FAILED token trace writes completely")
		trace.close()
	var written := proof.write_receipt(_scene_id(), proof.records.size(), failures.size())
	print("HUD_FAILED_NATIVE_RETIREMENT_", "PASS" if written and failures.is_empty() else "FAIL",
		" scene=", _scene_id(), " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
