extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const TARGET_SCRIPT := "res://scripts/caster_skill_animation_player.gd"
const MAIN_SCENE := "res://scenes/main.tscn"
@export var consumer_mode := "startup"
@export var receipt_scene_id := "code_preparation_startup_consumer_test"
var proof := Proof.new()
var failures: Array[String] = []
var startup: Control
var hall: Control
var world: Node
var last_startup: Dictionary = {}
var last_hall: Dictionary = {}
var startup_scene_request: Dictionary = {}
var hall_scene_request: Dictionary = {}
var captured_code_scope: Dictionary = {}
var first_preparation: Dictionary = {}
var old_profile_directory := ""
var old_profile_index := ""
var profile_directory := ""
var profile_index := ""
var profile_id := ""
var fixture_files: Array[String] = []
var observing := false
var service_owner: Node
var target_observation: Dictionary = {}
var reentry_observation: Dictionary = {}
var observed_retention_lease: WeakRef
var cold_hall_ready: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _process(_delta: float) -> void:
	if not observing:
		return
	if is_instance_valid(startup):
		last_startup = startup.main_scene_prefetch_diagnostic()
		if int(last_startup.get("request_count", 0)) > 0 and startup_scene_request.is_empty():
			startup_scene_request = last_startup.duplicate(true)
		var startup_code: Dictionary = last_startup.get("code_preparation", {})
		if first_preparation.is_empty() and startup_code.has("target_cached_before"):
			first_preparation = startup_code.duplicate(true)
		if startup_code.has("cover"):
			captured_code_scope = startup_code.cover.duplicate(true)
	if is_instance_valid(hall) and hall.has_method("launch_code_preparation_diagnostic"):
		last_hall = hall.launch_code_preparation_diagnostic()
		if first_preparation.is_empty() and last_hall.has("target_cached_before"):
			first_preparation = last_hall.duplicate(true)
		if int(hall.get("_launch_scene_preload_request_count")) > 0 and hall_scene_request.is_empty():
			hall_scene_request = last_hall.duplicate(true)
		if last_hall.has("cover"):
			captured_code_scope = last_hall.cover.duplicate(true)

func _wait_for_code_retirement(service: Node, deadline: int) -> bool:
	while Time.get_ticks_msec() < deadline:
		if service.pending_code_count() == 0:
			return true
		await get_tree().process_frame
	return service.pending_code_count() == 0

func _wait_for_world_retirement(service: Node, deadline: int) -> bool:
	while Time.get_ticks_msec() < deadline:
		if observed_retention_lease != null and observed_retention_lease.get_ref() == null and service.pending_count() == 0:
			return true
		await get_tree().process_frame
	return observed_retention_lease != null and observed_retention_lease.get_ref() == null and service.pending_count() == 0

func _run() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "real consumers retain test_mode=false")
	var nonce := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	var invocation := OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	check(not nonce.is_empty() and not invocation.is_empty() and appdata.contains("/.godot/runtime_appdata/"), "formal runner supplies isolated APPDATA and both identities")
	check(not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(), "receipt is bound to the tested source content")
	check(consumer_mode in ["startup", "hall", "hall_cancel", "startup_cancel", "hall_generation_reentry", "hall_scope_reentry", "hall_source_reentry"], "one scene selects an explicit bounded consumer lifecycle")
	check(not ResourceLoader.has_cached(TARGET_SCRIPT) and ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "real Caster target starts cold with no native retrieval entitlement")
	var api_ready: bool = ContentLayers.has_method("is_internal_code_retention_current") and ContentLayers.has_method("transfer_internal_code_retention")
	check(api_ready, "current ContentLayers/service own the consumer retention APIs")
	if not api_ready or not failures.is_empty():
		_finish()
		return
	var service: Node = ContentLayers._feature_resources()
	service_owner = service
	check(service.has_method("pending_code_count"), "the original preparation owner exposes bounded code-job observation")
	if not service.has_method("pending_code_count"):
		_finish()
		return
	old_profile_directory = PlayerState.profile_directory
	old_profile_index = PlayerState.profile_index_path
	profile_directory = "user://code_consumer_%s_%s" % [invocation, nonce]
	profile_index = profile_directory + "/index.json"
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(profile_directory)), "this invocation owns a fresh profile fixture directory")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_directory)) == OK, "only the invocation-owned fixture directory is created")
	PlayerState.profile_directory = profile_directory
	PlayerState.profile_index_path = profile_index
	check(PlayerState.create_character("加载守卫", "hc.profession.wizard", "男").is_empty(), "real profile authoring creates the selected caster profession in isolated user data")
	profile_id = PlayerState.active_profile_id
	check(not profile_id.is_empty() and not ResourceLoader.has_cached(TARGET_SCRIPT), "profile creation preserves the target Script cold premise")
	if not failures.is_empty():
		_finish()
		return
	observing = true
	var deadline := Time.get_ticks_msec() + 25000
	if consumer_mode.begins_with("startup"):
		# This is the real startup scene and its real finite animation/data/Hall path.
		# The fixture does not call either preparation API or preload a target Script.
		startup = load("res://scenes/startup_loading.tscn").instantiate() as Control
		add_child(startup)
		if consumer_mode == "startup_cancel":
			while Time.get_ticks_msec() < deadline and is_instance_valid(startup) and service.pending_code_count() == 0:
				await get_tree().process_frame
			check(is_instance_valid(startup) and service.pending_code_count() > 0, "real StartupLoading enters its covered code preparation queue")
			if is_instance_valid(startup):
				last_startup = startup.main_scene_prefetch_diagnostic()
				startup.queue_free()
			await get_tree().process_frame
			check(await _wait_for_code_retirement(service, deadline), "startup destruction cancels admission and drains original code ownership")
			check(not ResourceLoader.has_cached(TARGET_SCRIPT) and ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "exit during image/publication preparation never creates a phantom target request")
			_finish()
			return
		while Time.get_ticks_msec() < deadline:
			var current: Node = get_tree().current_scene
			if is_instance_valid(current) and current.get_script() != null and current.get_script().resource_path == "res://scripts/character_select.gd":
				hall = current as Control
				break
			await get_tree().process_frame
		check(is_instance_valid(hall), "real authored startup hands off to the actual CharacterSelect consumer")
	else:
		hall = load("res://scenes/character_select.tscn").instantiate() as Control
		get_tree().root.add_child(hall)
		get_tree().current_scene = hall
		await get_tree().process_frame
		cold_hall_ready = {"request_count": int(hall.get("_launch_scene_preload_request_count")),
			"target_cached": ResourceLoader.has_cached(TARGET_SCRIPT), "main_native_status": ResourceLoader.load_threaded_get_status(MAIN_SCENE),
			"loading_visible": hall.launch_loading_overlay.visible, "process_frame": Engine.get_process_frames()}
		check(int(hall.get("_launch_scene_preload_request_count")) == 0 and not ResourceLoader.has_cached(TARGET_SCRIPT), "independent cold Hall _ready defers main PackedScene prefetch before coverage")
		if not failures.is_empty():
			_finish()
			return
	if not is_instance_valid(hall):
		_finish()
		return
	check(not ContentLayers.is_internal_code_retention_current({"success": true, "lease": true, "resource": null}, hall), "caller booleans/JSON cannot grant this actual Hall a retained Script entitlement")
	# Let a cancelled Startup owner finish its existing retirement before the
	# independent covered click. No new timer or retry is inserted into production.
	check(await _wait_for_code_retirement(service, deadline), "outgoing startup code ownership is terminal before the observed UI activation")
	hall.selected_main_profile_id = profile_id
	hall.enter_button.pressed.emit()
	check(bool(hall.get("_launch_in_progress")) and hall.launch_loading_overlay.visible, "real launch-button signal enters the existing visible Loading synchronously")
	if consumer_mode.ends_with("_reentry"):
		while Time.get_ticks_msec() < deadline and is_instance_valid(hall) and service.pending_code_count() == 0:
			await get_tree().process_frame
		var admitted: bool = is_instance_valid(hall) and service.pending_code_count() > 0
		check(admitted, "actual Hall enters covered preparation before the controlled invalidation")
		var old_generation: int = hall.get("_launch_code_generation") if is_instance_valid(hall) else -1
		var mutated_shader: Shader
		var original_code := ""
		if admitted and consumer_mode == "hall_generation_reentry":
			hall._launch_code_generation += 1
		elif admitted and consumer_mode == "hall_scope_reentry":
			hall.launch_loading_overlay.shade.hide()
		elif admitted and consumer_mode == "hall_source_reentry":
			# Alter only a held runtime representation, before target acceptance.
			# Paths come from the real published producer entry, not a fixture list.
			while Time.get_ticks_msec() < deadline and not ResourceLoader.has_cached(TARGET_SCRIPT) and is_instance_valid(hall) and bool(hall.get("_launch_in_progress")):
				var entries: Dictionary = ContentLayers.get("_internal_code_entries")
				var entry: Dictionary = entries.get("framework.code.caster_animation.v1", {})
				for path: String in entry.get("prepared_inputs", []):
					var resource: Resource = ResourceLoader.get_cached_ref(path)
					if resource is Shader:
						mutated_shader = resource as Shader
						break
				if mutated_shader != null:
					break
				await get_tree().process_frame
			check(mutated_shader != null and not ResourceLoader.has_cached(TARGET_SCRIPT), "real first Shader acquisition is observable before target Script admission")
			if mutated_shader != null:
				original_code = mutated_shader.code
				mutated_shader.code = original_code + "\n// isolated native fixture representation differs\n"
				reentry_observation["mutated_path"] = mutated_shader.resource_path
				reentry_observation["source_file_sha256"] = FileAccess.get_sha256(mutated_shader.resource_path)
		while Time.get_ticks_msec() < deadline and is_instance_valid(hall) and bool(hall.get("_launch_in_progress")):
			await get_tree().process_frame
		check(is_instance_valid(hall) and not bool(hall.get("_launch_in_progress")), "actual consumer rejects invalid generation/scope/loaded source and restores the launch UI")
		check(await _wait_for_code_retirement(service, deadline), "invalid preparation retires through the original code owner before reentry")
		check(not ResourceLoader.has_cached(TARGET_SCRIPT) and ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "rejected controlled admission issued no target Script request/get")
		if mutated_shader != null:
			mutated_shader.code = original_code
			check(mutated_shader.code == FileAccess.get_file_as_string(mutated_shader.resource_path), "only the runtime Shader representation is restored to original authoring bytes")
			mutated_shader = null
		if is_instance_valid(hall):
			hall.launch_loading_overlay.shade.show()
			reentry_observation["old_generation"] = old_generation
			reentry_observation["retired_generation"] = int(hall.get("_launch_code_generation"))
			hall.enter_button.pressed.emit()
			check(int(hall.get("_launch_code_generation")) > old_generation and bool(hall.get("_launch_in_progress")), "actual second activation has a fresh generation and covered serial")
	if consumer_mode == "hall_cancel":
		while Time.get_ticks_msec() < deadline and is_instance_valid(hall) and service.pending_code_count() == 0:
			await get_tree().process_frame
		check(is_instance_valid(hall) and service.pending_code_count() > 0, "real launch consumer has admitted covered preparation before exit")
		if is_instance_valid(hall):
			last_hall = hall.launch_code_preparation_diagnostic()
			hall.queue_free()
		await get_tree().process_frame
		check(await _wait_for_code_retirement(service, deadline), "Hall destruction cancels its original covered preparation owner")
		check(ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "cancelled Hall leaves no native Script retrieval entitlement")
		_finish()
		return
	while Time.get_ticks_msec() < deadline:
		var current: Node = get_tree().current_scene
		if is_instance_valid(current) and current.get_script() != null and current.get_script().resource_path == "res://scripts/game_root.gd":
			world = current
			break
		await get_tree().process_frame
	check(is_instance_valid(world), "real button consumer hands the original PackedScene to the actual GameRoot")
	if is_instance_valid(world):
		var retained_value: Variant = world.get("_initial_code_retention")
		var retained: Dictionary = retained_value if retained_value is Dictionary else {}
		check(retained_value is Dictionary, "actual GameRoot exposes its own code retention lifecycle field")
		check(bool(retained.get("success", false)) and ContentLayers.is_internal_code_retention_current(retained, world), "actual GameRoot first ready claims and holds the same real input/Script lease")
		if retained.get("lease") is RefCounted:
			observed_retention_lease = weakref(retained.lease)
		retained = {} # Drop only this observer reference; do not clear the owner's Dictionary.
		await get_tree().process_frame
		var current_value: Variant = world.get("_initial_code_retention") if is_instance_valid(world) else null
		var current_retention: Dictionary = current_value if current_value is Dictionary else {}
		check(observed_retention_lease != null and observed_retention_lease.get_ref() != null and is_same(observed_retention_lease.get_ref(), current_retention.get("lease")) and ContentLayers.is_internal_code_retention_current(current_retention, world), "actual World retains the original lease across its first real process frame")
		current_retention = {}
	var request_proof: Dictionary = hall_scene_request if not hall_scene_request.is_empty() else startup_scene_request.get("code_preparation", {})
	check(bool(request_proof.get("retention_current_at_scene_request", false)) and bool(request_proof.get("target_cached_at_scene_request", false)), "the first real main scene submission follows retained Caster preparation rather than retrospective _ready approval")
	check(first_preparation.has("target_cached_before") and not bool(first_preparation.target_cached_before), "the first real preparing owner observed the actual target still cold before its protected Script request")
	check(not captured_code_scope.is_empty() and captured_code_scope.get("cover", {}).get("presentation_mode", "") != "", "actual preparing consumer supplies a bound physical cover receipt")
	check(ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "real Caster Script accepted request has one terminal retrieval and no native right remains")
	check(ResourceLoader.load_threaded_get_status(MAIN_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "both real scene-request owners collect their accepted main-scene native rights")
	var script: Script = ResourceLoader.get_cached_ref(TARGET_SCRIPT) as Script
	check(script != null and script.resource_path == TARGET_SCRIPT and script.source_code == FileAccess.get_file_as_string(TARGET_SCRIPT), "actual world owns the original target Script bytes after Hall lease retirement")
	var shader_constants := 0
	if script != null:
		target_observation = {"path": script.resource_path, "class": script.get_class(), "instance_id": script.get_instance_id(), "source_sha256": FileAccess.get_sha256(TARGET_SCRIPT), "source_text_sha256": script.source_code.sha256_text(), "native_status": ResourceLoader.load_threaded_get_status(TARGET_SCRIPT), "assets": []}
		for value: Variant in script.get_script_constant_map().values():
			if value is Shader:
				shader_constants += 1
				check(value.code == FileAccess.get_file_as_string(value.resource_path), "actual Script constant retains the exact authored Shader code: " + value.resource_path)
				target_observation.assets.append({"path": value.resource_path, "class": value.get_class(), "instance_id": value.get_instance_id(), "source_sha256": FileAccess.get_sha256(value.resource_path), "code_sha256": value.code.sha256_text(), "native_status": ResourceLoader.load_threaded_get_status(value.resource_path)})
	check(shader_constants == 2, "the real loaded component exposes both authored Shader constants")
	check(await _wait_for_code_retirement(service, deadline), "original service closes code jobs before actual world retirement")
	script = null
	if is_instance_valid(world):
		world.queue_free()
	await get_tree().process_frame
	check(await _wait_for_world_retirement(service, deadline), "actual World exit releases its last lease and the original service drains retirement without a second resource owner")
	check(ResourceLoader.load_threaded_get_status(TARGET_SCRIPT) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and ResourceLoader.load_threaded_get_status(MAIN_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "world exit creates no fresh target or scene native get entitlement")
	_finish()

func _finish() -> void:
	observing = false
	for value: Variant in [startup, hall, world]:
		if is_instance_valid(value) and not value.is_queued_for_deletion():
			value.queue_free()
	if not profile_directory.is_empty():
		PlayerState.profile_directory = old_profile_directory
		PlayerState.profile_index_path = old_profile_index
		# No recursive delete and no real profile path. Preserve this invocation's
		# isolated profile fixture for source-bound evidence rather than overwrite it.
	var trace_path := "res://outputs/test_logs/framework/" + receipt_scene_id + ".trace.json"
	var trace := FileAccess.open(trace_path, FileAccess.WRITE)
	check(trace != null, "source-bound bounded consumer trace opens")
	if trace != null:
		trace.store_string(JSON.stringify({"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"), "invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "scene_id": receipt_scene_id, "mode": consumer_mode,
			"startup_last": last_startup, "hall_last": last_hall, "startup_scene_request": startup_scene_request, "hall_scene_request": hall_scene_request,
			"first_preparation": first_preparation, "controlled_reentry": reentry_observation,
			"cold_hall_ready": cold_hall_ready,
			"cover": captured_code_scope, "target": target_observation, "phase_metrics": service_owner.code_phase_metrics() if is_instance_valid(service_owner) else {},
			"native_owner_counters": service_owner.metrics() if is_instance_valid(service_owner) else {}, "pending_code": service_owner.pending_code_count() if is_instance_valid(service_owner) else -1,
			"profile_directory": profile_directory, "profile_index": profile_index,
			"scope": "real PC startup/Hall/scene consumer; cold or explicit owner exit; headless cover protocol only; no GPU/APK/natural combat proof"}, "  "))
		trace.flush()
		check(trace.get_error() == OK, "bounded consumer trace writes completely")
		trace.close()
	var written: bool = proof.write_receipt(receipt_scene_id, proof.records.size(), failures.size())
	print(receipt_scene_id.to_upper().trim_suffix("_TEST"), "_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
