extends Node

## Controlled native Script dependency probe. The selected Script is never
## preloaded or instantiated; exit warning evidence stays in preserved stderr.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const EXPECTED_CHECKS := 7

enum Dependency {
	FRAME_BUDGET,
	WORLD_CONTEXT,
	TIME_DOMAINS,
	COMBAT_RUNTIME_SERVICE,
	MAP_EDITOR_RUNTIME_BRIDGE,
	MONSTER_VISUAL_STREAMING_COORDINATOR,
	FIRE_WALL_FIELD_CONTROLLER,
	CASTER_SKILL_RUNTIME,
	SHADER_CONSTANT_LEAF,
	TEXTURE_CONSTANT_LEAF,
	SHADER_LATE_LEAF,
	TEXTURE_LATE_LEAF,
	SHADER_WARM_CONSTANT_LEAF,
	TEXTURE_WARM_CONSTANT_LEAF,
}

const SCRIPT_PATHS: Array[String] = [
	"res://scripts/layers/runtime/execution/frame_budget.gd",
	"res://scripts/layers/runtime/execution/world_context.gd",
	"res://scripts/layers/runtime/execution/time_domains.gd",
	"res://scripts/layers/runtime/combat_runtime_service.gd",
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd",
	"res://scripts/monster_visual_streaming_coordinator.gd",
	"res://scripts/fire_wall_field_controller.gd",
	"res://scripts/caster_skill_runtime.gd",
	"res://tests/framework/fixtures/threaded_shader_constant_ref.gd",
	"res://tests/framework/fixtures/threaded_texture_constant_ref.gd",
	"res://tests/framework/fixtures/threaded_shader_late_ref.gd",
	"res://tests/framework/fixtures/threaded_texture_late_ref.gd",
	"res://tests/framework/fixtures/threaded_shader_constant_ref.gd",
	"res://tests/framework/fixtures/threaded_texture_constant_ref.gd",
]
const SCENE_IDS: Array[String] = [
	"threaded_dependency_frame_budget_script_probe_test",
	"threaded_dependency_world_context_script_probe_test",
	"threaded_dependency_time_domains_script_probe_test",
	"threaded_dependency_combat_runtime_service_script_probe_test",
	"threaded_dependency_map_editor_runtime_bridge_script_probe_test",
	"threaded_dependency_monster_visual_streaming_coordinator_script_probe_test",
	"threaded_dependency_fire_wall_field_controller_script_probe_test",
	"threaded_dependency_caster_skill_runtime_script_probe_test",
	"threaded_dependency_shader_constant_script_probe_test",
	"threaded_dependency_texture_constant_script_probe_test",
	"threaded_dependency_shader_late_script_probe_test",
	"threaded_dependency_texture_late_script_probe_test",
	"threaded_dependency_shader_warm_constant_script_probe_test",
	"threaded_dependency_texture_warm_constant_script_probe_test",
]

@export var selected_dependency: Dependency = Dependency.FRAME_BUDGET
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var requested_path: String = SCRIPT_PATHS[int(selected_dependency)]
	var scene_id: String = SCENE_IDS[int(selected_dependency)]
	var started := Time.get_ticks_usec()
	var expected_checks := EXPECTED_CHECKS
	var warmed_asset: Resource
	var main_thread_asset_warm: Dictionary = {}
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"controlled native Script probe owns isolated user data")
	if selected_dependency in [Dependency.SHADER_WARM_CONSTANT_LEAF, Dependency.TEXTURE_WARM_CONSTANT_LEAF]:
		expected_checks += 1
		var asset_path := "res://assets/shaders/trial_magic_screen.gdshader" \
			if selected_dependency == Dependency.SHADER_WARM_CONSTANT_LEAF \
			else "res://assets/art/monsters/effects/monster_target_magic/cow_mage_thunder_magic2.png"
		var asset_cache_before := ResourceLoader.has_cached(asset_path)
		var asset_started := Time.get_ticks_usec()
		warmed_asset = ResourceLoader.load(asset_path)
		var warm_elapsed_usec := Time.get_ticks_usec() - asset_started
		check(not asset_cache_before and warmed_asset != null and warmed_asset.resource_path == asset_path,
			"main thread acquires and retains the exact previously uncached asset before requesting its unmodified constant Script")
		main_thread_asset_warm = {"path": asset_path, "cache_before": asset_cache_before,
			"elapsed_usec": warm_elapsed_usec, "class": warmed_asset.get_class() if warmed_asset != null else "MISSING"}
	var cache_before := ResourceLoader.has_cached(requested_path)
	check(not cache_before, "the exact selected Script is not cached before its one native request")
	var status_before := ResourceLoader.load_threaded_get_status(requested_path)
	check(status_before == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"this process has no existing native retrieval owner for the exact selected Script")
	var request_started := Time.get_ticks_usec()
	var request_error := ResourceLoader.load_threaded_request(requested_path, "Script", false)
	var request_elapsed_usec := Time.get_ticks_usec() - request_started
	check(request_error == OK, "one real background request accepts the exact selected Script")
	var status := ResourceLoader.load_threaded_get_status(requested_path)
	var cache_after_request := ResourceLoader.has_cached(requested_path)
	var deadline := Time.get_ticks_msec() + 20000
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(requested_path)
	var completion_elapsed_usec := Time.get_ticks_usec() - started
	check(status == ResourceLoader.THREAD_LOAD_LOADED,
		"the accepted native Script completes within the 20-second bounded probe")
	var obtained: Resource
	var get_elapsed_usec := 0
	if request_error == OK:
		var get_started := Time.get_ticks_usec()
		obtained = ResourceLoader.load_threaded_get(requested_path)
		get_elapsed_usec = Time.get_ticks_usec() - get_started
	var obtained_is_instantiable_script: bool = obtained is Script and (obtained as Script).can_instantiate()
	var status_after_get := ResourceLoader.load_threaded_get_status(requested_path)
	var cache_after_get := ResourceLoader.has_cached(requested_path)
	check(obtained_is_instantiable_script and status_after_get == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"one actual get returns an instantiable Script and retires its one native retrieval right")
	var late_acquisition: Dictionary = {}
	if selected_dependency in [Dependency.SHADER_LATE_LEAF, Dependency.TEXTURE_LATE_LEAF]:
		expected_checks += 3
		var resource_path := str(obtained.get("RESOURCE_PATH"))
		var asset_cache_before := ResourceLoader.has_cached(resource_path)
		check(not asset_cache_before, "late-acquisition leaf has not loaded its exact asset during background Script compilation")
		var asset_started := Time.get_ticks_usec()
		var asset: Resource = obtained.call("acquire_resource")
		var asset_elapsed_usec := Time.get_ticks_usec() - asset_started
		var usable := (asset is Shader and (asset as Shader).code == FileAccess.get_file_as_string(resource_path)) \
			if selected_dependency == Dependency.SHADER_LATE_LEAF \
			else (asset is Texture2D and (asset as Texture2D).get_width() > 0 and (asset as Texture2D).get_height() > 0)
		check(asset != null and asset.resource_path == resource_path and usable,
			"one main-thread first use returns the exact usable source Shader or Texture without a Script instance")
		check(ResourceLoader.has_cached(resource_path) and ResourceLoader.load_threaded_get_status(resource_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"main-thread first use leaves no extra native threaded retrieval right")
		late_acquisition = {"resource_path": resource_path, "cache_before": asset_cache_before,
			"usable": usable, "first_use_elapsed_usec": asset_elapsed_usec,
			"resource_class": asset.get_class() if asset != null else "MISSING"}
		asset = null
	obtained = null
	for frame in 8: await get_tree().process_frame
	var final_status := ResourceLoader.load_threaded_get_status(requested_path)
	var final_cached := ResourceLoader.has_cached(requested_path)
	check(final_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"the selected Script has no native retrieval owner after release and eight real frames")
	print("THREADED_DEPENDENCY_SCRIPT_PROBE_TRACE ", JSON.stringify({
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scene_id": scene_id, "selected_dependency": int(selected_dependency),
		"requested_path": requested_path, "requested_type": "Script", "use_sub_threads": false,
		"request_error": request_error, "native_status_before": status_before,
		"completion_status": status, "native_status_after_get": status_after_get,
		"final_native_status": final_status, "cache_before": cache_before,
		"cache_after_request": cache_after_request, "cache_after_get": cache_after_get,
		"final_cached": final_cached, "obtained_is_instantiable_script": obtained_is_instantiable_script,
		"request_elapsed_usec": request_elapsed_usec, "completion_elapsed_usec": completion_elapsed_usec,
		"get_elapsed_usec": get_elapsed_usec, "elapsed_usec": Time.get_ticks_usec() - started,
		"expected_checks": expected_checks, "recorded_checks": proof.records.size(), "late_acquisition": late_acquisition,
		"main_thread_asset_warm": main_thread_asset_warm,
		"scope": "native Script request/get only; no selected Script instance or world; exit warning assessment uses preserved stderr"
	}))
	var written := proof.write_receipt(scene_id, expected_checks, failures.size())
	print("THREADED_DEPENDENCY_SCRIPT_PROBE_", "PASS" if written and failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
