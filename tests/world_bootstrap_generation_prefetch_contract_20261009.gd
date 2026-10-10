extends Node

const Coordinator := preload("res://scripts/world_bootstrap_coordinator.gd")

const SOURCE_GAME_ROOT := "res://scripts/game_root.gd"
const SOURCE_COORDINATOR := "res://scripts/world_bootstrap_coordinator.gd"
const OWNED_SCRIPT := "res://scripts/world_bootstrap_coordinator.gd"
var _behavior_coordinator: Coordinator
var _replacement_callback_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_source := FileAccess.get_file_as_string(SOURCE_GAME_ROOT)
	var coordinator_source := FileAccess.get_file_as_string(SOURCE_COORDINATOR)
	assert(not game_source.is_empty() and not coordinator_source.is_empty())
	var claim_path := "res://scripts/world_bootstrap_coordinator.gd"
	var first_claim := ResourceLoader.load_threaded_request(claim_path, "Script", false)
	var second_claim := ResourceLoader.load_threaded_request(claim_path, "Script", false)
	assert(first_claim == OK and second_claim == OK, "same path claims must be accepted")
	var claim_deadline := Time.get_ticks_msec() + 5000
	var claim_status := ResourceLoader.load_threaded_get_status(claim_path)
	while claim_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < claim_deadline:
		await get_tree().process_frame
		claim_status = ResourceLoader.load_threaded_get_status(claim_path)
	assert(
		claim_status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED],
		"same path claims must reach a terminal status before get",
	)
	var first_resource: Resource = ResourceLoader.load_threaded_get(claim_path)
	var second_resource: Resource = ResourceLoader.load_threaded_get(claim_path)
	assert(first_resource != null and second_resource != null, "each accepted claim needs one get")

	var coordinator := Coordinator.new()
	coordinator.begin_initial_world(910001)
	var first_generation: int = coordinator.generation
	assert(coordinator.is_generation_current(first_generation))
	coordinator.revoke_current_generation()
	assert(
		not coordinator.is_generation_current(first_generation),
		"revoked generation must reject a suspended coroutine",
	)
	coordinator.begin_map_transition(910004)
	var second_generation: int = coordinator.generation
	assert(second_generation != first_generation)
	assert(coordinator.is_generation_current(second_generation))
	_behavior_coordinator = coordinator
	_replacement_callback_count = 0
	coordinator.submit_map_descriptors([{"id": 1}, {"id": 2}])
	await coordinator.process_map_queue(
		Callable(self, "_replace_generation_from_handler"), 12, 3.0
	)
	assert(_replacement_callback_count == 1)
	assert(
		coordinator.built_map_item_count == 0,
		"a handler that replaces generation cannot commit the old slice",
	)
	assert(not coordinator.is_generation_current(second_generation))
	_behavior_coordinator = null
	coordinator.finish(false, "contract_failure")
	assert(
		not coordinator.is_generation_current(second_generation),
		"failed finish must revoke the failed generation",
	)
	coordinator.begin_map_transition(910005)
	second_generation = coordinator.generation
	assert(coordinator.is_generation_current(second_generation))

	# Headless mode uses the production manifest but serializes the actual
	# ResourceLoader load; this verifies the accepted path is consumed by the
	# same coordinator owner before a later generation starts.
	coordinator.register_resource(OWNED_SCRIPT, "script", true, "contract")
	assert(coordinator.request_threaded_prefetch() == 1)
	assert(coordinator.poll_threaded_prefetch())
	assert(coordinator.resource_manifest[OWNED_SCRIPT]["status"] == "ready")
	assert(coordinator.get_build_resource(OWNED_SCRIPT, "contract") != null)
	assert(coordinator.resource_manifest[OWNED_SCRIPT]["status"] == "ready")
	coordinator.poll_retired_threaded_prefetch()

	# Use two real accepted claims, while constructing only the coordinator's
	# application receipt so the existing ContentLayers owner can take over the
	# unresolved request without issuing another ResourceLoader request.
	assert(ContentLayers.has_method("retire_threaded_resource_claims"))
	var retired_path := "res://scripts/world_bootstrap_coordinator.gd"
	var retired_first := ResourceLoader.load_threaded_request(retired_path, "Script", false)
	var retired_second := ResourceLoader.load_threaded_request(retired_path, "Script", false)
	assert(retired_first == OK and retired_second == OK)
	var handoff_before: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	coordinator.resource_manifest[retired_path] = {
		"path": retired_path,
		"status": "requested",
		"required": true,
		"claim_count": 1,
	}
	assert(coordinator.retire_threaded_resource_claims())
	assert(not coordinator.resource_manifest.has(retired_path), "retiring owner relinquished its receipt")
	var handoff_now: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	assert(int(handoff_now.transferred) == int(handoff_before.transferred) + 1, "persistent owner actually received one claim")
	var handoff_deadline := Time.get_ticks_msec() + 3000
	while int(ContentLayers.threaded_resource_claim_diagnostics().get("get", 0)) == int(handoff_before.get("get", 0)) and Time.get_ticks_msec() < handoff_deadline:
		await get_tree().process_frame
	var handoff_after: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	assert(int(handoff_after.get("get", 0)) == int(handoff_before.get("get", 0)) + 1, "persistent owner consumed exactly its one claim")
	assert(int(handoff_after.pending) == int(handoff_before.pending), "retired claim reached terminal cleanup")
	assert(ResourceLoader.load_threaded_get_status(retired_path) == ResourceLoader.THREAD_LOAD_LOADED, "foreign owner still holds the second claim")
	assert(ResourceLoader.load_threaded_get(retired_path) != null, "foreign owner can consume its own claim")
	assert(ResourceLoader.load_threaded_get_status(retired_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "both accepted claims are closed")

	print("WORLD_BOOTSTRAP_GENERATION_PREFETCH_CONTRACT_PASS")
	get_tree().quit()


func _replace_generation_from_handler(_descriptor: Dictionary) -> Dictionary:
	_replacement_callback_count += 1
	_behavior_coordinator.begin_map_transition(910006)
	return {"ok": true}
