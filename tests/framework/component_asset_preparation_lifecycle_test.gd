extends Node

## Candidate only. No preload, type annotation or class-name reference to the
## selected production Script. Only string paths reach ResourceLoader.
## Exit warning evidence belongs to native stderr after this scene terminates.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const EXPECTED_CHECKS := 29
const COMPONENT_PATH := "res://scripts/caster_skill_animation_player.gd"
const ASSET_PATHS: Array[String] = [
	"res://assets/shaders/trial_magic_screen.gdshader",
	"res://assets/shaders/fire_wall_screen_blend_multiply.gdshader",
]
const CONSTANT_NAMES: Array[String] = ["TrialScreenShader", "FireWallMultiplyShader"]
const EXPECTED_SOURCE_SHA256: Array[String] = [
	"365cdebbfe74104d08de7eda5558455190e8aaf5e63399dadffe269b648c1ef3",
	"9d48b1e894223e063a5c71c2190d4b8d5994fa0ba8e750d07ccbd07b97c4e4e6",
	"061187e21bd6b82450009501cc4f82cea5bedef4f0f39bffab8518e9d3cc5f82",
]
const NAMED_CLASS_PATHS: Array[String] = [
	"res://scripts/profession_rules.gd", "res://scripts/caster_skill_visual_registry.gd",
]
const WAIT_FRAMES_AFTER_RELEASE := 8
const POLL_LIMIT_MSEC := 12000
const RUN_POLL_LIMIT_MSEC := 25000

enum Preparation { COLD, TWO_KNOWN_SHADERS, OMIT_ONE_KNOWN_SHADER }
enum OwnerExit { BEFORE_REQUEST, AFTER_ACCEPT_BEFORE_GET, AFTER_GET_AND_FIRST_USE }

@export var scene_id := "component_cold_asset_lifecycle_test"
@export var preparation: Preparation = Preparation.COLD
@export var omitted_asset_index := 1
@export var owner_exit: OwnerExit = OwnerExit.AFTER_GET_AND_FIRST_USE

var proof := Proof.new()
var failures: Array[String] = []
var _prepared_assets: Array[Resource] = [] # max 2, owned by retirement coordinator
var _tickets: Array[Dictionary] = [] # exactly 2 logical consumer generations
var _owner_refs: Array[WeakRef] = [] # max 2, no ownership
var _component_refs: Array[WeakRef] = [] # max 2, no ownership
var _started_usec := 0
var _poll_deadline_msec := 0
var _trace: Dictionary = {}

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_started_usec = Time.get_ticks_usec()
	_poll_deadline_msec = Time.get_ticks_msec() + RUN_POLL_LIMIT_MSEC
	_trace = {
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"engine_version": Engine.get_version_info(), "scene_id": scene_id,
		"component_path": COMPONENT_PATH, "preparation": int(preparation),
		"omitted_asset_index": omitted_asset_index, "owner_exit": int(owner_exit),
		"source_hashes_before": _source_hashes(), "named_class_edges_before": _named_edges_snapshot(),
		"closure_status": "NOT_RUN", "root_preparation_status": "NOT_RUN",
		"gpu_status": "NOT_RUN", "native_internal_token_identity": "MISSING",
		"scope": "same production Script bytes; only its two observed direct Shader preloads; fixture retirement owner, no production Loading integration",
	}
	check(OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/")
		and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(),
		"fresh native process has runner-isolated user data and a real run identity")
	check(_source_bytes_match(), "selected production Script and both Shader source bytes match the fixed candidate baseline")
	check(not ResourceLoader.has_cached(COMPONENT_PATH), "selected component Script is cold before any preparation or request")
	check(_initial_assets_cold(), "both observed Shader assets start cold without preexisting native requests")
	var preparation_started := Time.get_ticks_usec()
	var prepared := _prepare_assets(int(preparation), omitted_asset_index)
	_trace["initial_preparation"] = prepared
	_trace["initial_preparation_elapsed_usec"] = Time.get_ticks_usec() - preparation_started
	check(bool(prepared.valid), "main thread prepares and retains exactly the explicitly selected known Shader assets")
	check(not ResourceLoader.has_cached(COMPONENT_PATH), "main-thread asset preparation does not preload the selected component Script")
	await _cycle("initial", int(owner_exit))
	check(_all_native_rights_absent() and _prepared_assets.is_empty() and _source_bytes_match(),
		"released first generation has no owned native rights and leaves original bytes intact before legal reentry")
	# Reentry is deliberately warm-two in all scenes. Its cache state is measured;
	# only the first generation provides the cold/warm/omit cold-process control.
	var reentry_preparation := _prepare_assets(int(Preparation.TWO_KNOWN_SHADERS), -1)
	_trace["reentry_preparation"] = reentry_preparation
	check(bool(reentry_preparation.valid), "reentry obtains both exact Shader assets on the main thread with measured cache state")
	await _cycle("reentry", int(OwnerExit.AFTER_GET_AND_FIRST_USE))
	check(_all_native_rights_absent(), "final selected Script and both known Shader paths have no native retrieval right")
	check(_prepared_assets.is_empty() and _all_weak_nodes_gone(), "all fixture asset leases and both consumer/component Nodes are released")
	var expected_accepted := 1 if owner_exit == OwnerExit.BEFORE_REQUEST else 2
	check(_ledger_balanced(expected_accepted), "each real accepted request has exactly one get; canceled unaccepted generation has no get")
	_trace["tickets"] = _tickets
	_trace["named_class_edges_after"] = _named_edges_snapshot()
	_trace["source_hashes_after"] = _source_hashes()
	_trace["final_native_states"] = _known_native_snapshot()
	_trace["elapsed_usec"] = Time.get_ticks_usec() - _started_usec
	_trace["expected_checks"] = EXPECTED_CHECKS
	_trace["recorded_checks"] = proof.records.size()
	print("COMPONENT_ASSET_PREPARATION_LIFECYCLE_TRACE ", JSON.stringify(_trace))
	var written := proof.write_receipt(scene_id, EXPECTED_CHECKS, failures.size())
	print("COMPONENT_ASSET_PREPARATION_LIFECYCLE_", "PASS" if written and failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)

func _cycle(generation: String, requested_exit: int) -> void:
	var cycle_started := Time.get_ticks_usec()
	var owner := Node.new()
	owner.name = "ComponentConsumer_" + generation
	var ticket := {
		"generation": generation, "consumer_owner": owner.name,
		"retrieval_owner": "fixture_retirement_coordinator",
		"preparation_lease_owner": "fixture_retirement_coordinator",
		"requested_owner_exit": requested_exit, "accepted": false, "get_calls": 0,
		"owner_exited": false, "first_use": {}, "status_transitions": [],
		"cache_before_request": ResourceLoader.has_cached(COMPONENT_PATH),
		"native_before_request": ResourceLoader.load_threaded_get_status(COMPONENT_PATH),
	}
	_tickets.append(ticket)
	_owner_refs.append(weakref(owner))
	owner.tree_exited.connect(_on_owner_tree_exited.bind(ticket))
	add_child(owner)
	check(owner.is_inside_tree(), "%s consumer enters the real SceneTree" % generation)
	var obtained: Resource
	var obtained_weak: WeakRef
	var completion_status := ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	if requested_exit == OwnerExit.BEFORE_REQUEST:
		_retire_owner(owner, ticket)
		owner = null
		ticket["request_error"] = "NOT_RUN"
		ticket["completion_status"] = "NOT_RUN"
		check(not bool(ticket.accepted) and int(ticket.get_calls) == 0,
			"%s retired-before-request consumer creates no native request or phantom get" % generation)
		check(ResourceLoader.load_threaded_get_status(COMPONENT_PATH) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"%s canceled generation has no native completion to collect" % generation)
		check(obtained == null, "%s canceled generation owns no component Resource" % generation)
		check(int(ticket.get_calls) == 0 and _all_native_rights_absent(), "%s canceled generation has zero native retrieval rights" % generation)
		check(_component_refs.is_empty(), "%s canceled generation does not instantiate a component" % generation)
	else:
		var request_started := Time.get_ticks_usec()
		var request_error := ResourceLoader.load_threaded_request(COMPONENT_PATH, "Script", false)
		ticket["request_elapsed_usec"] = Time.get_ticks_usec() - request_started
		ticket["request_error"] = request_error
		ticket["accepted"] = request_error == OK
		ticket["native_after_request"] = ResourceLoader.load_threaded_get_status(COMPONENT_PATH)
		ticket["cache_after_request"] = ResourceLoader.has_cached(COMPONENT_PATH)
		check(request_error == OK, "%s real background request accepts the exact unchanged component Script" % generation)
		if requested_exit == OwnerExit.AFTER_ACCEPT_BEFORE_GET:
			_retire_owner(owner, ticket)
			owner = null
		var poll_started := Time.get_ticks_usec()
		completion_status = ResourceLoader.load_threaded_get_status(COMPONENT_PATH)
		var deadline := mini(_poll_deadline_msec, Time.get_ticks_msec() + POLL_LIMIT_MSEC)
		var transitions: Array = ticket.status_transitions
		transitions.append(completion_status)
		while completion_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			var next_status := ResourceLoader.load_threaded_get_status(COMPONENT_PATH)
			if next_status != completion_status:
				transitions.append(next_status)
			completion_status = next_status
		ticket["poll_elapsed_usec"] = Time.get_ticks_usec() - poll_started
		ticket["completion_status"] = completion_status
		ticket["poll_timed_out"] = completion_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS
		check(completion_status == ResourceLoader.THREAD_LOAD_LOADED,
			"%s accepted Script reaches LOADED within the bounded observation window" % generation)
		# Acceptance is the sole retrieval-right authority. FAILED is collected
		# once too; an unaccepted INVALID path is never passed to get. Godot has
		# no cancellation API: after poll timeout this one native get may block,
		# and the external 30 s runner owns the missing-evidence classification.
		if bool(ticket.accepted):
			ticket["get_calls"] = 1
			var get_started := Time.get_ticks_usec()
			obtained = ResourceLoader.load_threaded_get(COMPONENT_PATH)
			ticket["get_elapsed_usec"] = Time.get_ticks_usec() - get_started
			ticket["get_status_before"] = completion_status
			ticket["native_after_get"] = ResourceLoader.load_threaded_get_status(COMPONENT_PATH)
			ticket["obtained"] = _resource_description(obtained)
			if obtained != null:
				obtained_weak = weakref(obtained)
		var usable_script := obtained is Script and (obtained as Script).can_instantiate() and obtained.resource_path == COMPONENT_PATH
		check(usable_script, "%s one native get returns the exact instantiable production Script" % generation)
		check(int(ticket.get_calls) == (1 if bool(ticket.accepted) else 0)
			and ResourceLoader.load_threaded_get_status(COMPONENT_PATH) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"%s retrieval coordinator consumes the accepted right exactly once" % generation)
		var first_use_started := Time.get_ticks_usec()
		var first_use := _verify_constants_and_optional_instance(obtained as Script, owner)
		ticket["first_use"] = first_use
		ticket["first_use_elapsed_usec"] = Time.get_ticks_usec() - first_use_started
		check(bool(first_use.valid) and bool(first_use.instantiated) == (requested_exit == OwnerExit.AFTER_GET_AND_FIRST_USE),
			"%s exact Shader constants are usable; only a live consumer owns the real Sprite2D first use" % generation)
		if is_instance_valid(owner):
			_retire_owner(owner, ticket)
			owner = null
	var exit_matches := bool(ticket.owner_exited)
	if requested_exit == OwnerExit.BEFORE_REQUEST:
		exit_matches = exit_matches and not bool(ticket.accepted) and int(ticket.native_at_owner_exit) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	elif requested_exit == OwnerExit.AFTER_ACCEPT_BEFORE_GET:
		var in_progress_observed := int(ticket.native_at_owner_exit) == ResourceLoader.THREAD_LOAD_IN_PROGRESS
		ticket["in_progress_exit_observation"] = "PASS" if in_progress_observed else "MISSING"
		# Do not invent a worker delay to force this result. If native loading
		# finishes before removal, the scene preserves that MISSING observation.
		exit_matches = exit_matches and bool(ticket.accepted) and int(ticket.get_calls_at_owner_exit) == 0 and in_progress_observed
	else:
		exit_matches = exit_matches and int(ticket.get_calls_at_owner_exit) == 1 and int(ticket.native_at_owner_exit) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	check(exit_matches, "%s requested real consumer-exit timing is observed, including native state" % generation)
	var release_started := Time.get_ticks_usec()
	obtained = null
	_prepared_assets.clear()
	for frame in WAIT_FRAMES_AFTER_RELEASE:
		await get_tree().process_frame
		ticket["release_observed_frames"] = frame + 1
	ticket["release_wait_elapsed_usec"] = Time.get_ticks_usec() - release_started
	ticket["weak_script_alive_after_release"] = obtained_weak != null and obtained_weak.get_ref() != null
	ticket["cache_after_release"] = ResourceLoader.has_cached(COMPONENT_PATH)
	ticket["native_after_release"] = ResourceLoader.load_threaded_get_status(COMPONENT_PATH)
	ticket["cycle_elapsed_usec"] = Time.get_ticks_usec() - cycle_started
	check(_prepared_assets.is_empty() and _all_native_rights_absent() and _all_weak_nodes_gone(),
		"%s fixture releases Resources, frees Nodes and observes absent native rights after eight real frames" % generation)
	check(_source_bytes_match(), "%s source Script and both Shader files remain byte-identical after retirement" % generation)

func _retire_owner(owner: Node, ticket: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	remove_child(owner) # synchronous tree exit, before any explicit get
	owner.queue_free() # real deferred Node destruction, observed after frames
	ticket["owner_removal_elapsed_usec"] = Time.get_ticks_usec() - started

func _on_owner_tree_exited(ticket: Dictionary) -> void:
	ticket["owner_exited"] = true
	ticket["owner_exit_usec_since_start"] = Time.get_ticks_usec() - _started_usec
	ticket["native_at_owner_exit"] = ResourceLoader.load_threaded_get_status(COMPONENT_PATH)
	ticket["get_calls_at_owner_exit"] = int(ticket.get_calls)
	ticket["cache_at_owner_exit"] = ResourceLoader.has_cached(COMPONENT_PATH)

func _verify_constants_and_optional_instance(selected: Script, owner: Node) -> Dictionary:
	var result := {"valid": false, "instantiated": false, "shader_constants": []}
	if selected == null:
		return result
	var constants: Dictionary = selected.get_script_constant_map()
	var shaders: Array[Shader] = []
	var valid := true
	for index in ASSET_PATHS.size():
		var asset: Resource = constants.get(CONSTANT_NAMES[index]) as Resource
		var row := _resource_description(asset)
		row["constant_name"] = CONSTANT_NAMES[index]
		row["expected_path"] = ASSET_PATHS[index]
		row["source_sha256"] = _file_sha256(ASSET_PATHS[index])
		row["code_equals_exact_source"] = asset is Shader and (asset as Shader).code == FileAccess.get_file_as_string(ASSET_PATHS[index])
		row["native_request_state"] = ResourceLoader.load_threaded_get_status(ASSET_PATHS[index])
		valid = valid and bool(row.code_equals_exact_source) and asset.resource_path == ASSET_PATHS[index]
		result.shader_constants.append(row)
		shaders.append(asset as Shader)
		asset = null
	if is_instance_valid(owner) and valid and selected.can_instantiate():
		var component: Node = selected.new() as Node
		if component is Sprite2D:
			var trial_material := ShaderMaterial.new()
			trial_material.shader = shaders[0]
			(component as Sprite2D).material = trial_material
			owner.add_child(component) # runs the unchanged component's _ready
			component.set_process(false)
			_component_refs.append(weakref(component))
			var trial_bound := (component as Sprite2D).material == trial_material and trial_material.shader == shaders[0]
			var multiply_material := ShaderMaterial.new()
			multiply_material.shader = shaders[1]
			(component as Sprite2D).material = multiply_material
			result["instantiated"] = component.is_inside_tree() and trial_bound and multiply_material.shader == shaders[1]
			result["component_class"] = component.get_class()
			result["component_instance_id"] = component.get_instance_id()
			result["configured_animation"] = false
			result["gpu_draw_status"] = "NOT_RUN"
			trial_material = null
			multiply_material = null
		elif component != null:
			component.queue_free()
			valid = false
		else:
			valid = false
		component = null
	result["valid"] = valid
	constants.clear()
	shaders.clear()
	return result

func _prepare_assets(mode: int, omitted: int) -> Dictionary:
	var result := {"valid": _prepared_assets.is_empty(), "owner": "fixture_retirement_coordinator", "assets": []}
	for index in ASSET_PATHS.size():
		var path := ASSET_PATHS[index]
		var selected := mode == Preparation.TWO_KNOWN_SHADERS or (mode == Preparation.OMIT_ONE_KNOWN_SHADER and index != omitted)
		var row := {"path": path, "selected_for_main_thread_prepare": selected,
			"cache_before": ResourceLoader.has_cached(path), "native_before": ResourceLoader.load_threaded_get_status(path),
			"load_elapsed_usec": 0, "class": "NOT_RUN", "source_sha256": _file_sha256(path)}
		var asset: Resource
		if selected:
			var started := Time.get_ticks_usec()
			asset = ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_REUSE)
			row["load_elapsed_usec"] = Time.get_ticks_usec() - started
			row.merge(_resource_description(asset), true)
			row["code_equals_exact_source"] = asset is Shader and (asset as Shader).code == FileAccess.get_file_as_string(path)
			result["valid"] = bool(result.valid) and bool(row.code_equals_exact_source) and asset.resource_path == path
			if asset != null:
				_prepared_assets.append(asset)
		row["cache_after"] = ResourceLoader.has_cached(path)
		row["native_after"] = ResourceLoader.load_threaded_get_status(path)
		result["valid"] = bool(result.valid) and int(row.native_before) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and int(row.native_after) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		if selected:
			result["valid"] = bool(result.valid) and bool(row.cache_after)
		else:
			result["valid"] = bool(result.valid) and not bool(row.cache_after)
		result.assets.append(row)
		asset = null
	result["held_asset_count"] = _prepared_assets.size()
	var expected_held := 2 if mode == Preparation.TWO_KNOWN_SHADERS else (1 if mode == Preparation.OMIT_ONE_KNOWN_SHADER else 0)
	result["valid"] = bool(result.valid) and _prepared_assets.size() == expected_held
	if mode == Preparation.OMIT_ONE_KNOWN_SHADER:
		result["valid"] = bool(result.valid) and omitted in [0, 1]
	result["component_cached_after_prepare"] = ResourceLoader.has_cached(COMPONENT_PATH)
	return result

func _resource_description(resource: Resource) -> Dictionary:
	return {"class": resource.get_class() if resource != null else "MISSING",
		"path": resource.resource_path if resource != null else "",
		"instance_id": resource.get_instance_id() if resource != null else 0}

func _file_sha256(path: String) -> String:
	return FileAccess.get_sha256(path)

func _source_hashes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var paths: Array[String] = [COMPONENT_PATH, ASSET_PATHS[0], ASSET_PATHS[1]]
	for path in paths:
		rows.append({"path": path, "sha256": _file_sha256(path)})
	return rows

func _source_bytes_match() -> bool:
	var rows := _source_hashes()
	for index in rows.size():
		if str(rows[index].sha256) != EXPECTED_SOURCE_SHA256[index]:
			return false
	return true

func _initial_assets_cold() -> bool:
	for path in ASSET_PATHS:
		if ResourceLoader.has_cached(path) or ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return false
	return ResourceLoader.load_threaded_get_status(COMPONENT_PATH) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

func _named_edges_snapshot() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for path in NAMED_CLASS_PATHS:
		rows.append({"path": path, "cached": ResourceLoader.has_cached(path), "native_state": ResourceLoader.load_threaded_get_status(path), "source_sha256": _file_sha256(path)})
	return rows

func _known_native_snapshot() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for path: String in [COMPONENT_PATH, ASSET_PATHS[0], ASSET_PATHS[1]]:
		rows.append({"path": path, "cached": ResourceLoader.has_cached(path), "native_state": ResourceLoader.load_threaded_get_status(path)})
	return rows

func _all_native_rights_absent() -> bool:
	for row: Dictionary in _known_native_snapshot():
		if int(row.native_state) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return false
	return true

func _all_weak_nodes_gone() -> bool:
	for reference: WeakRef in _owner_refs + _component_refs:
		if reference.get_ref() != null:
			return false
	return true

func _ledger_balanced(expected_accepted: int) -> bool:
	var accepted_count := 0
	var get_count := 0
	for ticket in _tickets:
		accepted_count += 1 if bool(ticket.accepted) else 0
		get_count += int(ticket.get_calls)
		if int(ticket.get_calls) != (1 if bool(ticket.accepted) else 0):
			return false
	return accepted_count == expected_accepted and get_count == accepted_count and _tickets.size() == 2
