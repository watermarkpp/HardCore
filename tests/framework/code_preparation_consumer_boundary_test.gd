extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const TARGET := "res://scripts/caster_skill_animation_player.gd"
const MAIN := "res://scenes/main.tscn"
const HALL := "res://scenes/character_select.tscn"
const WRONG := "res://tests/framework/helpers/code_preparation_nonclaim_scene.tscn"
@export var boundary_mode := "cancel_all"
@export var receipt_scene_id := "code_preparation_handoff_cancel_all_test"
var proof := Proof.new()
var failures: Array[String] = []
var service: Node
var hall: Control
var world: Node
var wrong_marker: Node
var wrong_scene: PackedScene
var observed_lease: WeakRef
var phase := "setup"
var entered_count := 0
var boundary_count := 0
var accepted_boundary_id := 0
var wrong_change_error := -1
var old_directory := ""
var old_index := ""
var fixture_directory := ""
var profile_id := ""
var deadline := 0
var snapshots: Array[Dictionary] = []
var expected_catalogue_generation := -1

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _is_world(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var script: Script = node.get_script() as Script
	return script != null and script.resource_path == "res://scripts/game_root.gd"

func _retained(node: Node) -> Dictionary:
	var value: Variant = node.get("_initial_code_retention") if is_instance_valid(node) else null
	return value if value is Dictionary else {}

func _observe_world_lease(node: Node) -> WeakRef:
	var result: Dictionary = _retained(node)
	var lease: Variant = result.get("lease")
	return weakref(lease) if lease is RefCounted else null

func _lease_dead(reference: WeakRef) -> bool:
	# A tiny returned boolean prevents an observer's temporary StrongRef from
	# surviving across a frame await and blocking the very retirement observed.
	var held: RefCounted = reference.get_ref() as RefCounted if reference != null else null
	return reference != null and held == null

func _snapshot(label: String) -> void:
	if snapshots.size() >= 24:
		check(false, "bounded trace capacity is not exceeded")
		return
	var id: int = service.get("_code_world_handoff_id") if is_instance_valid(service) else -1
	var ledger: Dictionary = service.get("_requests") if is_instance_valid(service) else {}
	var handoffs := 0
	for request: Variant in ledger.values():
		handoffs += 1 if request.get("kind") == "code_retention_handoff" else 0
	var current: Node = get_tree().current_scene
	snapshots.append({"label": label, "phase": phase, "tick_usec": Time.get_ticks_usec(),
		"handoff_id": id, "handoff_in_ledger": ledger.has(id), "handoff_requests": handoffs,
		"pending_code": service.pending_code_count() if is_instance_valid(service) else -1,
		"pending_total": service.pending_count() if is_instance_valid(service) else -1,
		"native_counters": service.metrics() if is_instance_valid(service) else {},
		"code_phase_metrics": service.code_phase_metrics() if is_instance_valid(service) else {},
		"target_native_status": ResourceLoader.load_threaded_get_status(TARGET),
		"main_native_status": ResourceLoader.load_threaded_get_status(MAIN),
		"current_scene_path": current.scene_file_path if is_instance_valid(current) else "",
		"current_scene_id": current.get_instance_id() if is_instance_valid(current) else 0,
		"catalogue_generation": int(ContentLayers.get("_feature_preparation_sequence")),
		"lease_dead": _lease_dead(observed_lease)})

func _handoff_absent() -> bool:
	if int(service.get("_code_world_handoff_id")) != 0:
		return false
	var ledger: Dictionary = service.get("_requests")
	for request: Variant in ledger.values():
		if request.get("kind") == "code_retention_handoff":
			return false
	return true

func _await_retirement(reference: WeakRef) -> bool:
	while Time.get_ticks_msec() < deadline:
		if _lease_dead(reference) and _handoff_absent() and service.pending_code_count() == 0 and service.pending_count() == 0:
			return true
		await get_tree().process_frame
	return _lease_dead(reference) and _handoff_absent() and service.pending_code_count() == 0 and service.pending_count() == 0

func _enter_hall(suppress_handoff: bool) -> void:
	hall = load(HALL).instantiate() as Control
	hall.suppress_scene_change_for_test = suppress_handoff
	get_tree().root.add_child(hall)
	get_tree().current_scene = hall
	hall.selected_main_profile_id = profile_id
	hall.enter_button.pressed.emit()
	check(bool(hall.get("_launch_in_progress")) and hall.launch_loading_overlay.visible, phase + ": actual Hall button enters its existing Loading")

func _await_world_ready() -> Node:
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(world) and world.is_inside_tree() and world.is_node_ready():
			return world
		await get_tree().process_frame
	return null

func _world_entered(node: Node) -> void:
	if not _is_world(node):
		return
	world = node
	entered_count += 1
	var id: int = service.get("_code_world_handoff_id")
	var ledger: Dictionary = service.get("_requests")
	check(id > 0 and ledger.has(id) and not node.is_node_ready() and is_same(get_tree().current_scene, node), phase + ": accepted main replacement is observed inside Tree before actual Root ready/claim")
	if id <= 0 or not ledger.has(id):
		return
	var request: Variant = ledger[id]
	check(request.get("kind") == "code_retention_handoff", phase + ": original service ledger owns the passive request")
	var lease: Variant = request.get("input_lease")
	check(lease is RefCounted, phase + ": accepted bridge carries a real input lease")
	if lease is RefCounted:
		observed_lease = weakref(lease)
	var before: Dictionary = service.metrics()
	var foreign: Dictionary = ContentLayers.claim_internal_code_world_retention(self)
	check(foreign.is_empty() and int(service.get("_code_world_handoff_id")) == id and ledger.has(id), phase + ": rejected foreign claimant does not steal the legal Root entitlement")
	check(service.metrics() == before, phase + ": rejected passive claim creates no native request/get")
	_snapshot("before_ready_foreign_claim_rejected")
	if phase != "negative":
		return
	boundary_count += 1
	accepted_boundary_id = id
	if boundary_mode == "cancel_all":
		service.cancel_all()
		check(_handoff_absent(), "same original service cancel_all clears accepted bridge ID and request before Root claim")
	elif boundary_mode == "generation":
		var generation: int = ContentLayers.get("_feature_preparation_sequence")
		ContentLayers.cancel_feature_resource_preparation()
		expected_catalogue_generation = int(ContentLayers.get("_feature_preparation_sequence"))
		check(expected_catalogue_generation > generation, "actual ContentLayers cancellation advances its own publication generation")
		check(_handoff_absent(), "publisher withdrawal retires its accepted bridge through the same service")
	elif boundary_mode == "wrong_scene":
		check(is_instance_valid(wrong_marker) and wrong_marker.is_inside_tree() and is_same(wrong_marker.get_parent(), get_tree().root), "nonclaim scene is an actual direct Tree-root child before the controlled selection change")
		if is_instance_valid(wrong_marker):
			# Public selection of a different real scene prevents the just-entered
			# Root from claiming while its parent is in the enter/ready traversal.
			# The actual SceneTree replacement follows deferred, after that lock.
			get_tree().current_scene = wrong_marker
			var denied: Dictionary = ContentLayers.claim_internal_code_world_retention(wrong_marker)
			check(denied.is_empty() and int(service.get("_code_world_handoff_id")) == id and ledger.has(id), "wrong actual scene cannot claim or consume the original eligible bridge")
			_replace_with_wrong_scene.call_deferred()
	var after: Dictionary = service.metrics()
	check(after.get("request_calls") == before.get("request_calls") and after.get("get_calls") == before.get("get_calls"), "controlled passive boundary does not get a native resource or create a resource request")
	_snapshot("boundary_applied_before_root_ready")

func _replace_with_wrong_scene() -> void:
	wrong_change_error = get_tree().change_scene_to_packed(wrong_scene)
	check(wrong_change_error == OK, "actual SceneTree accepts the plain wrong/nonclaim scene replacement after enter traversal")
	if is_instance_valid(world) and not world.is_queued_for_deletion():
		world.queue_free()
	_snapshot("actual_wrong_scene_change_returned")

func _control_and_release(label: String) -> bool:
	phase = label
	world = null
	observed_lease = null
	_enter_hall(false)
	var actual: Node = await _await_world_ready()
	check(is_instance_valid(actual), label + ": actual Hall button reaches actual ready GameRoot")
	if not is_instance_valid(actual):
		return false
	var retained: Dictionary = _retained(actual)
	check(bool(retained.get("success", false)) and ContentLayers.is_internal_code_retention_current(retained, actual), label + ": correct actual Root claims its original verified lease")
	var reference: WeakRef = _observe_world_lease(actual)
	retained = {}
	check(reference != null and _handoff_absent(), label + ": claim closes the original bridge ID and request")
	_snapshot(label + "_claimed")
	await get_tree().process_frame
	var still_retained: Dictionary = _retained(actual)
	check(ContentLayers.is_internal_code_retention_current(still_retained, actual), label + ": original lease stays held across a real process frame")
	still_retained = {}
	actual.queue_free()
	await get_tree().process_frame
	check(await _await_retirement(reference), label + ": actual World exit drains last lease, handoff, original requests and retirement queue")
	check(ResourceLoader.load_threaded_get_status(TARGET) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and ResourceLoader.load_threaded_get_status(MAIN) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, label + ": original resource owners have no residual native get rights")
	world = null
	hall = null
	_snapshot(label + "_retired")
	return failures.is_empty()

func _pre_engine_reject_and_recover() -> void:
	phase = "pre_engine_rejection"
	world = null
	_enter_hall(true)
	while Time.get_ticks_msec() < deadline and is_instance_valid(hall):
		var diagnostic: Dictionary = hall.launch_code_preparation_diagnostic()
		# Resource readiness precedes the original launch coroutine's final
		# suppress-handoff return. Observe its final overlay progress as well,
		# so recovery cannot race the first button activation still awaiting it.
		if str(hall.get("_launch_scene_preload_state")) == "ready" and str(diagnostic.get("state", "")).begins_with("retained") and is_equal_approx(float(hall.launch_loading_overlay.get("_progress_value")), 1.0):
			break
		await get_tree().process_frame
	var value: Variant = hall.get("_launch_code_result") if is_instance_valid(hall) else null
	var held: Dictionary = value if value is Dictionary else {}
	check(is_instance_valid(hall) and ContentLayers.is_internal_code_retention_current(held, hall), "real suppressed Hall handoff holds its own service-issued target/input lease")
	if not is_instance_valid(hall) or not bool(held.get("success", false)):
		return
	var reference: WeakRef = weakref(held.lease)
	var counter_before: Dictionary = service.metrics()
	var null_error: int = ContentLayers.change_scene_with_internal_code_retention(held, hall, null)
	var empty_scene := PackedScene.new()
	var empty_error: int = ContentLayers.change_scene_with_internal_code_retention(held, hall, empty_scene)
	check(null_error == ERR_UNAVAILABLE and empty_error == ERR_UNAVAILABLE, "null/empty inputs are rejected before real SceneTree; never mislabeled as engine ERR_INVALID_PARAMETER/ERR_CANT_CREATE")
	check(_handoff_absent() and service.metrics() == counter_before and is_same(get_tree().current_scene, hall), "pre-engine rejection leaves no bridge ID/request and consumes no native right")
	check(ContentLayers.is_internal_code_retention_current(held, hall) and is_same(reference.get_ref(), held.lease), "rejected inputs preserve the legal Hall's exact real lease")
	observed_lease = reference
	_snapshot("null_empty_pre_engine_rejection")
	empty_scene = null
	held = {}
	value = null
	# This is the existing production error restoration path after an actual
	# business rejection. The test does not invent an engine failure result.
	hall._restore_after_launch_failure("受控场景门禁拒绝")
	hall.suppress_scene_change_for_test = false
	phase = "same_hall_reentry"
	world = null
	hall.enter_button.pressed.emit()
	var actual: Node = await _await_world_ready()
	check(is_instance_valid(actual), "legal same-Hall second button activation succeeds after pre-engine refusal")
	if is_instance_valid(actual):
		var retained: Dictionary = _retained(actual)
		check(is_same(reference.get_ref(), retained.get("lease")) and ContentLayers.is_internal_code_retention_current(retained, actual), "refusal did not steal the original lease now legally claimed by actual Root")
		retained = {}
		actual.queue_free()
		await get_tree().process_frame
		check(await _await_retirement(reference), "same-Hall recovery exits with lease/request/bridge ID and original queues drained")
	world = null
	hall = null
	_snapshot("same_hall_reentry_retired")

func _accepted_boundary() -> void:
	if boundary_mode == "wrong_scene":
		wrong_scene = load(WRONG) as PackedScene
		wrong_marker = wrong_scene.instantiate()
		get_tree().root.add_child(wrong_marker)
	phase = "negative"
	world = null
	observed_lease = null
	_enter_hall(false)
	# wrong replacement may delete its original Root at the deferred boundary.
	if boundary_mode != "wrong_scene":
		var actual: Node = await _await_world_ready()
		check(is_instance_valid(actual) and _retained(actual).is_empty(), "controlled cancellation/withdrawal causes actual Root's late claim to reject")
	else:
		while Time.get_ticks_msec() < deadline and wrong_change_error < 0:
			await get_tree().process_frame
		check(wrong_change_error == OK, "wrong-scene case ran a genuine accepted SceneTree replacement")
	check(boundary_count == 1 and accepted_boundary_id > 0, "one actual accepted-before-ready window was observed and mutated once")
	if is_instance_valid(world) and not world.is_queued_for_deletion():
		check(_retained(world).is_empty(), "original Root retained no rejected bridge qualification")
		world.queue_free()
	await get_tree().process_frame
	check(await _await_retirement(observed_lease), "original passive lease, request and ID retire through real service quanta before reentry")
	if boundary_mode == "wrong_scene":
		var current: Node = get_tree().current_scene
		check(is_instance_valid(current) and current.scene_file_path == WRONG and current.get_script() == null, "actual current wrong scene is plain and never claims a code lease")
		if is_instance_valid(current):
			current.queue_free()
		if is_instance_valid(wrong_marker) and not wrong_marker.is_queued_for_deletion():
			wrong_marker.queue_free()
		await get_tree().process_frame
	check(ResourceLoader.load_threaded_get_status(TARGET) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and ResourceLoader.load_threaded_get_status(MAIN) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "accepted boundary mutation leaves no target/main native get entitlement")
	_snapshot("accepted_boundary_retired")
	world = null
	hall = null
	await _control_and_release("legal_reentry")
	if boundary_mode == "generation":
		check(int(ContentLayers.get("_feature_preparation_sequence")) >= expected_catalogue_generation, "new consumer never restores the withdrawn publication generation")

func _run() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "boundary fixtures use the actual runtime mode")
	check(boundary_mode in ["pre_engine_rejection", "cancel_all", "wrong_scene", "generation"], "scene selects one bounded boundary")
	check(OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty() and not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty() and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(), "official runner isolates APPDATA and binds run/invocation/content")
	check(not ResourceLoader.has_cached(TARGET) and ResourceLoader.load_threaded_get_status(TARGET) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "first real positive starts with cold selected Script and no native right")
	var ready: bool = ContentLayers.has_method("change_scene_with_internal_code_retention") and ContentLayers.has_method("claim_internal_code_world_retention") and ContentLayers.has_method("is_internal_code_retention_current")
	check(ready, "reviewed real retention consumer APIs are integrated")
	if not ready or not failures.is_empty():
		await _finish()
		return
	service = ContentLayers._feature_resources()
	var id_shape: Variant = service.get("_code_world_handoff_id")
	var ledger_shape: Variant = service.get("_requests")
	var service_ready: bool = service.has_method("pending_code_count") and service.has_method("cancel_all") and service.has_method("code_phase_metrics") and id_shape is int and ledger_shape is Dictionary
	check(service_ready, "same original service exposes observation/cancellation")
	if not service_ready:
		await _finish()
		return
	old_directory = PlayerState.profile_directory
	old_index = PlayerState.profile_index_path
	fixture_directory = "user://code_boundary_%s_%s" % [OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"), OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")]
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fixture_directory)), "invocation owns a fresh isolated profile directory")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_directory)) == OK, "isolated fixture profile directory creates")
	PlayerState.profile_directory = fixture_directory
	PlayerState.profile_index_path = fixture_directory + "/index.json"
	check(PlayerState.create_character("交接守卫", "hc.profession.wizard", "男").is_empty(), "actual profile authoring creates stable caster profession")
	profile_id = PlayerState.active_profile_id
	if not failures.is_empty() or profile_id.is_empty():
		await _finish()
		return
	deadline = Time.get_ticks_msec() + 25000
	get_tree().root.child_entered_tree.connect(_world_entered)
	var control: bool = await _control_and_release("positive_control")
	if control:
		if boundary_mode == "pre_engine_rejection":
			await _pre_engine_reject_and_recover()
		else:
			await _accepted_boundary()
	await _finish()

func _finish() -> void:
	phase = "cleanup"
	var extra_cleanup_required := false
	if get_tree().root.child_entered_tree.is_connected(_world_entered):
		get_tree().root.child_entered_tree.disconnect(_world_entered)
	# A real scene replacement may already have freed these observations.
	# Validate the untyped values before constructing any typed Node value.
	for node: Variant in [hall, world, wrong_marker]:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	if is_instance_valid(service):
		extra_cleanup_required = service.pending_count() > 0 or int(service.get("_code_world_handoff_id")) != 0
		if extra_cleanup_required:
			service.cancel_all() # Explicit fixture cleanup, never proof of earlier retirement.
		await get_tree().process_frame
	if not fixture_directory.is_empty():
		PlayerState.profile_directory = old_directory
		PlayerState.profile_index_path = old_index
	var file := FileAccess.open("res://outputs/test_logs/framework/" + receipt_scene_id + ".trace.json", FileAccess.WRITE)
	check(file != null, "bounded source-associated trace opens")
	if file != null:
		file.store_string(JSON.stringify({"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"), "invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"), "source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "scene_id": receipt_scene_id, "mode": boundary_mode,
			"entered_worlds": entered_count, "observed_boundaries": boundary_count, "accepted_boundary_id": accepted_boundary_id,
			"wrong_scene_change_return": wrong_change_error, "generation_after_withdrawal": expected_catalogue_generation,
			"snapshots": snapshots, "original_service_metrics": service.metrics() if is_instance_valid(service) else {},
			"fixture_cleanup_required": extra_cleanup_required, "fixture_cleanup": "if pending, service.cancel_all after assertions; never classified as successful production retirement",
			"immediate_engine_return_branch": "MISSING: valid cached-main gate cannot safely produce engine immediate error; pre-engine scene refusal only",
			"representation": "PC editor text; headless lifecycle only; no GPU/natural combat/Android proof", "profile_directory": fixture_directory}, "  "))
		file.flush()
		check(file.get_error() == OK, "bounded trace writes completely")
		file.close()
	var written: bool = proof.write_receipt(receipt_scene_id, proof.records.size(), failures.size())
	print(receipt_scene_id.to_upper().trim_suffix("_TEST"), "_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
