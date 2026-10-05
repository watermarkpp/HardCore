extends Node

## Candidate only: actual UIItemTextureCache request/poll under its existing
## force-threaded seam. Owned corruption stays in native stderr; no suppression.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Cache := preload("res://scripts/ui_item_texture_cache.gd")
const BASELINE_SERVICE_SHA256 := "bf1b8ede2787845b98e3c35e471e27f3337cabc0f3ae17ca7ceb1ba3dd00da80"
const SERVICE_PATH := "res://scripts/ui_item_texture_cache.gd"
const INVALID := ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
const IN_PROGRESS := ResourceLoader.THREAD_LOAD_IN_PROGRESS
const LOADED := ResourceLoader.THREAD_LOAD_LOADED
const FAILED := ResourceLoader.THREAD_LOAD_FAILED
const POLL_MSEC := 6000
const RELEASE_FRAMES := 8
const NORMAL_CHECKS := 21
const FAILED_CHECKS := 29

@export var inject_owned_failure := false
var proof := Proof.new()
var failures: Array[String] = []
var trace: Dictionary = {}
var owned_path := ""
var owns_file := false
var accepted_open := false
var accepted_count := 0
var fixture_extra_get_count := 0
var source_before := ""
var force_before := false
var seam_set := false
var sync_before := 0
var serial_loads_before := 0
var original_bytes: PackedByteArray = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _scene_id() -> String:
	return "ui_cache_failed_native_retirement_test" if inject_owned_failure else "ui_cache_normal_native_reuse_test"

func _status() -> int:
	return ResourceLoader.load_threaded_get_status(owned_path)

func _source_hash() -> String:
	return FileAccess.get_sha256(SERVICE_PATH)

func _run() -> void:
	source_before = _source_hash()
	trace = {
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"engine_version": Engine.get_version_info(), "scene_id": _scene_id(),
		"baseline_service_sha256": BASELINE_SERVICE_SHA256, "observed_service_sha256_before": source_before,
		"controlled_force_threaded_seam": true, "inject_owned_failure": inject_owned_failure,
		"production_get_call_count": "MISSING", "native_internal_token_identity": "MISSING",
		"scope": "controlled headless service request/poll; exact owned ImageTexture resource; not natural GPU/UI, world, imports, Loading or APK reproduction",
	}
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"real PlayerState mode and runner-isolated APPDATA stay active") # 1
	check(not str(trace.run_id).is_empty() and not str(trace.invocation_id).is_empty()
		and str(trace.source_content_sha256).length() == 64,
		"native runner binds run, invocation and source identity") # 2
	check(Cache.threaded_pending_count() == 0,
		"fresh process has no foreign UI cache request rights to clear or consume") # 3
	if not failures.is_empty():
		_finish()
		return
	force_before = Cache._test_force_threaded_prefetch
	sync_before = Cache.sync_miss_count()
	serial_loads_before = int(Cache.headless_prefetch_diagnostics().load_count)
	Cache._test_force_threaded_prefetch = true
	seam_set = true
	check(DisplayServer.get_name() == "headless" and not Cache._use_headless_serial_prefetch(),
		"existing controlled seam selects the actual async service branch in headless") # 4
	var nonce := str(trace.run_id).validate_filename()
	owned_path = "user://ui_cache_owned_%s_%d_%s.tres" % [nonce, OS.get_process_id(), "failed" if inject_owned_failure else "normal"]
	trace["owned_path"] = owned_path
	check(_exact_owned_target() and not FileAccess.file_exists(owned_path),
		"one previously absent exact resource belongs only to this isolated invocation") # 5
	if not failures.is_empty():
		_finish()
		return
	var save_started := Time.get_ticks_usec()
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var texture := ImageTexture.create_from_image(image)
	var save_error := ResourceSaver.save(texture, owned_path)
	owns_file = FileAccess.file_exists(owned_path)
	texture = null
	image = null
	original_bytes = FileAccess.get_file_as_bytes(owned_path) if owns_file else PackedByteArray()
	trace["save_elapsed_usec"] = Time.get_ticks_usec() - save_started
	trace["original_bytes_sha256"] = FileAccess.get_sha256(owned_path)
	trace["original_size"] = original_bytes.size()
	check(save_error == OK and owns_file and not original_bytes.is_empty() and not ResourceLoader.has_cached(owned_path),
		"actual red ImageTexture serializes to a released uncached owned resource") # 6
	var header := FileAccess.get_file_as_string(owned_path).split("\n")[0] if owns_file else ""
	trace["actual_resource_header"] = header
	check(header.begins_with("[gd_resource ") and header.contains("type=\"ImageTexture\"")
		and ResourceLoader.exists(owned_path, "Texture2D"),
		"real ResourceSaver header is a recognized Texture2D subtype") # 7
	if not failures.is_empty():
		_finish()
		return
	if inject_owned_failure:
		await _failed_then_repaired(header)
	else:
		await _normal_reuse()
	_finish()

func _normal_reuse() -> void:
	var accepted := _request("normal")
	check(accepted == 1 and Cache._threaded_paths.has(owned_path), "service actually accepts and owns the cold native texture request") # 8
	check(int(Cache.headless_prefetch_diagnostics().load_count) == serial_loads_before, "normal request does not use headless serial fallback") # 9
	check(Cache.request_threaded_paths([owned_path]) == 0 and Cache.threaded_pending_count() == 1, "duplicate active path adds no second native request") # 10
	var terminal := await _wait_without_service_poll("normal")
	check(terminal == LOADED, "actual native texture worker reaches LOADED within six seconds") # 11
	var ready := _service_poll("normal")
	check(ready == 1 and not Cache._threaded_paths.has(owned_path), "service poll returns one ready texture and retires its pending entry") # 12
	check(_status() == INVALID, "service itself consumes the successful native retrieval right before fixture cleanup") # 13
	var first := Cache.texture_at_path(owned_path)
	check(_valid_red_texture(first), "service cache returns the exact saved Texture2D pixels, dimensions and path") # 14
	var second := Cache.texture_at_path(owned_path)
	check(first != null and is_same(first, second) and Cache.sync_miss_count() == sync_before, "repeat lookup reuses the same Resource without a synchronous miss") # 15
	check(Cache.request_threaded_paths([owned_path]) == 0 and Cache.threaded_pending_count() == 0 and _status() == INVALID, "cached request reuses residency without any new native token") # 16
	first = null
	second = null
	Cache._textures.erase(owned_path) # only this fixture's cache entry
	for frame in RELEASE_FRAMES:
		await get_tree().process_frame
	check(not Cache._textures.has(owned_path) and _status() == INVALID, "owned texture cache reference releases after eight actual frames with no native right") # 17
	_cleanup_open_right("normal_supplemental_cleanup")
	check(fixture_extra_get_count == 0, "healthy service path requires zero fixture supplemental gets") # 18
	check(_remove_owned_file(), "normal fixture deletes only its exact owned isolated file") # 19
	_restore_seam()
	check(_source_hash() == source_before and not PlayerState.test_mode and Cache._test_force_threaded_prefetch == force_before, "source bytes, real mode and existing seam state remain intact") # 20
	check(accepted_count == 1 and not accepted_open and _status() == INVALID, "one accepted successful generation leaves no observable native retrieval right") # 21

func _failed_then_repaired(header: String) -> void:
	# Preserve the exact legal ResourceSaver ImageTexture header; only this
	# owned text-resource body refers to a deliberately absent SubResource.
	var broken_bytes := (header + "\n\n[resource]\nimage = SubResource(\"ui_cache_owned_missing_image\")\n").to_utf8_buffer()
	check(_write_owned_bytes(broken_bytes) and FileAccess.get_file_as_bytes(owned_path) == broken_bytes,
		"only owned resource body is corrupted while its legal Texture2D subtype header remains") # 8
	trace["damaged_bytes_sha256"] = FileAccess.get_sha256(owned_path)
	check(ResourceLoader.exists(owned_path, "Texture2D") and not ResourceLoader.has_cached(owned_path),
		"damaged owned body still passes the service's real existence gate with no cached Resource") # 9
	if not failures.is_empty():
		return
	var accepted := _request("failed")
	check(accepted == 1 and Cache._threaded_paths.has(owned_path), "formal service accepts and owns the actual corrupt Texture2D request") # 10
	check(int(Cache.headless_prefetch_diagnostics().load_count) == serial_loads_before, "failure request follows controlled async branch without serial fallback") # 11
	var terminal := await _wait_without_service_poll("failed")
	check(terminal == FAILED, "owned missing-SubResource body reaches real native FAILED before any service poll or fixture get") # 12
	var ready := _service_poll("failed")
	var after_service := _status()
	trace["native_after_failed_service_poll_before_cleanup"] = after_service
	trace["failed_right_left_by_service_observed"] = after_service == FAILED
	trace["service_pending_after_failed_poll"] = Cache._threaded_paths.has(owned_path)
	check(ready == 0 and not Cache._threaded_paths.has(owned_path), "service poll removes the failed pending entry without declaring a ready texture") # 13
	# Intended RED on baseline: FAILED persists after erase. This assertion
	# runs BEFORE any supplemental fixture get. A repaired service is INVALID.
	check(after_service == INVALID, "service itself retires the real FAILED retrieval right before fixture cleanup") # 14
	var extras_before := fixture_extra_get_count
	_cleanup_open_right("failed_extra_cleanup")
	var expected_extra := 1 if accepted == 1 and after_service in [IN_PROGRESS, LOADED, FAILED] else 0
	check(_status() == INVALID and fixture_extra_get_count - extras_before == expected_extra,
		"explicit extra cleanup consumes at most this accepted residual right once; INVALID receives no phantom get") # 15
	for frame in RELEASE_FRAMES:
		await get_tree().process_frame
	check(_status() == INVALID and not Cache._textures.has(owned_path), "released failed generation has no texture or native right before repair") # 16
	check(_write_owned_bytes(original_bytes) and FileAccess.get_file_as_bytes(owned_path) == original_bytes and not ResourceLoader.has_cached(owned_path),
		"same owned path repairs to original lawful uncached Texture2D bytes") # 17
	var accepted_reentry := _request("reentry")
	check(accepted_reentry == 1 and Cache._threaded_paths.has(owned_path), "same service legally accepts one fresh repaired-path generation") # 18
	check(Cache.request_threaded_paths([owned_path]) == 0 and Cache.threaded_pending_count() == 1, "reentry duplicate does not acquire a second native right") # 19
	var reentry_terminal := await _wait_without_service_poll("reentry")
	check(reentry_terminal == LOADED, "repaired owned texture reaches actual native LOADED") # 20
	var reentry_ready := _service_poll("reentry")
	check(reentry_ready == 1 and not Cache._threaded_paths.has(owned_path), "service poll owns and collects exactly one ready reentry resource") # 21
	check(_status() == INVALID, "service itself retires successful reentry's native right") # 22
	var first := Cache.texture_at_path(owned_path)
	check(_valid_red_texture(first), "reentry returns the exact repaired red Texture2D from actual service cache") # 23
	var second := Cache.texture_at_path(owned_path)
	check(first != null and is_same(first, second) and Cache.sync_miss_count() == sync_before, "reentry repeat lookup keeps Resource identity without sync fallback") # 24
	check(Cache.request_threaded_paths([owned_path]) == 0 and Cache.threaded_pending_count() == 0 and _status() == INVALID, "repaired cached path creates no replacement native task") # 25
	first = null
	second = null
	Cache._textures.erase(owned_path)
	for frame in RELEASE_FRAMES:
		await get_tree().process_frame
	check(not Cache._textures.has(owned_path) and _status() == INVALID, "successful reentry releases only its owned resource reference and has no token") # 26
	check(_remove_owned_file(), "failed/repaired fixture deletes only its exact isolated file after rights close") # 27
	_restore_seam()
	check(_source_hash() == source_before and not PlayerState.test_mode and Cache._test_force_threaded_prefetch == force_before,
		"formal service source, real mode and seam state remain intact through negative and reentry") # 28
	check(accepted_count == 2 and not accepted_open and fixture_extra_get_count <= 1 and _status() == INVALID,
		"two accepted generations close their observable rights; only recorded failed extra cleanup may assist the old service") # 29

func _request(generation: String) -> int:
	var started := Time.get_ticks_usec()
	var accepted := Cache.request_threaded_paths([owned_path])
	if accepted == 1:
		accepted_open = true
		accepted_count += 1
	trace[generation + "_request"] = {"accepted": accepted, "elapsed_usec": Time.get_ticks_usec() - started,
		"status": _status(), "pending_owned": Cache._threaded_paths.has(owned_path), "cached": ResourceLoader.has_cached(owned_path)}
	return accepted

func _wait_without_service_poll(generation: String) -> int:
	var started := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + POLL_MSEC
	var status := _status()
	var transitions: Array[int] = [status]
	while status == IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var next_status := _status()
		if next_status != status:
			transitions.append(next_status)
		status = next_status
	trace[generation + "_terminal_observation"] = {"status": status, "transitions": transitions,
		"elapsed_usec": Time.get_ticks_usec() - started, "timed_out": status == IN_PROGRESS}
	return status

func _service_poll(generation: String) -> int:
	var started := Time.get_ticks_usec()
	var before := _status()
	var ready := Cache.poll_threaded_paths()
	var after := _status()
	if accepted_open and after == INVALID:
		accepted_open = false
	trace[generation + "_service_poll"] = {"ready": ready, "native_before": before, "native_after": after,
		"pending_owned_after": Cache._threaded_paths.has(owned_path), "elapsed_usec": Time.get_ticks_usec() - started,
		"production_get_call_count": "MISSING", "fixture_gets_before_poll": fixture_extra_get_count}
	return ready

func _cleanup_open_right(reason: String) -> void:
	var status := _status() if not owned_path.is_empty() else INVALID
	if not accepted_open or status == INVALID:
		if status == INVALID:
			accepted_open = false
		return
	var started := Time.get_ticks_usec()
	var resource: Resource = ResourceLoader.load_threaded_get(owned_path)
	fixture_extra_get_count += 1
	trace[reason] = {"native_before": status, "returned_null": resource == null,
		"returned_class": resource.get_class() if resource != null else "MISSING",
		"elapsed_usec": Time.get_ticks_usec() - started, "native_after": _status(),
		"attribution": "fixture supplemental cleanup; never production retirement proof"}
	resource = null
	accepted_open = false
	# No ownership injection or global clear. Only remove this exact path if
	# an exceptional IN_PROGRESS timeout left its service entry still present.
	Cache._threaded_paths.erase(owned_path)

func _valid_red_texture(texture: Texture2D) -> bool:
	if texture == null or texture.resource_path != owned_path or texture.get_size() != Vector2(8, 8):
		return false
	var image := texture.get_image()
	return image != null and not image.is_empty() and image.get_pixel(0, 0) == Color.RED and image.get_pixel(7, 7) == Color.RED

func _exact_owned_target() -> bool:
	if not owned_path.begins_with("user://ui_cache_owned_") or not owned_path.ends_with(".tres"):
		return false
	var target := ProjectSettings.globalize_path(owned_path).replace("\\", "/")
	var prefix := OS.get_user_data_dir().replace("\\", "/").trim_suffix("/") + "/"
	return target.begins_with(prefix) and owned_path.get_file() == target.get_file()

func _write_owned_bytes(bytes: PackedByteArray) -> bool:
	if not owns_file or not _exact_owned_target():
		return false
	var file := FileAccess.open(owned_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	return okay

func _remove_owned_file() -> bool:
	if not owns_file or not _exact_owned_target() or accepted_open or _status() != INVALID:
		return false
	var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(owned_path)) == OK
	if removed:
		owns_file = false
	return removed and not FileAccess.file_exists(owned_path)

func _restore_seam() -> void:
	if seam_set:
		Cache._test_force_threaded_prefetch = force_before
		seam_set = false

func _finish() -> void:
	# Failure-path sanitation is explicit and happens after the business
	# observations. It can never turn their failed checks into passing checks.
	_cleanup_open_right("final_exceptional_extra_cleanup")
	if owns_file:
		Cache._textures.erase(owned_path)
		trace["final_exceptional_owned_file_removed"] = _remove_owned_file()
	_restore_seam()
	trace["fixture_extra_get_count"] = fixture_extra_get_count
	trace["accepted_count"] = accepted_count
	trace["final_native_status"] = _status() if not owned_path.is_empty() else INVALID
	trace["observed_service_sha256_after"] = _source_hash()
	trace["expected_checks"] = FAILED_CHECKS if inject_owned_failure else NORMAL_CHECKS
	trace["recorded_checks"] = proof.records.size()
	print("UI_CACHE_OWNED_NATIVE_LIFECYCLE_TRACE ", JSON.stringify(trace))
	var expected_checks := FAILED_CHECKS if inject_owned_failure else NORMAL_CHECKS
	var written := proof.write_receipt(_scene_id(), expected_checks, failures.size())
	print("UI_CACHE_OWNED_NATIVE_LIFECYCLE_", "PASS" if written and failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
