extends Node

const Bootstrap := preload("res://scripts/world_bootstrap_coordinator.gd")
const Cache := preload("res://scripts/ui_item_texture_cache.gd")
const TEXTURE := "res://assets/art/maps/bich/bich_ground_tiles.png"
const OTHER_TEXTURE := "res://assets/art/maps/bich/bich_props.png"
const MISSING := "res://assets/missing_headless_prefetch_fixture.png"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	PlayerState.test_mode = true
	var bootstrap := Bootstrap.new()
	bootstrap.begin_initial_world(910001)
	bootstrap.register_resource(TEXTURE, "texture", true, "compat-test")
	bootstrap.register_resource(OTHER_TEXTURE, "texture", true, "compat-test")
	bootstrap.register_resource(MISSING, "texture", true, "compat-test")
	assert(bootstrap.request_threaded_prefetch() == 2)
	assert(bootstrap.poll_threaded_prefetch(), "Completed failures must not remain pending")
	assert(bootstrap.has_failed_required_resource(), "Missing required resources must fail the world gate")
	assert(bootstrap.resource_manifest[MISSING].status == "load_failed")
	assert(bootstrap.diagnostic.prefetch_failure_count == 1)
	assert(bootstrap.diagnostic.headless_serial_prefetch)
	assert(bootstrap.get_build_resource(TEXTURE, "map") is Texture2D)
	assert(bootstrap.get_build_resource(OTHER_TEXTURE, "map") is Texture2D)
	assert(bootstrap.unexpected_sync_load_count == 0)
	bootstrap.begin_map_transition(910004)
	assert(bootstrap.get_prefetched_resource(TEXTURE) == null, "New generations release prior resources")
	bootstrap.register_resource(TEXTURE, "texture", true, "compat-test")
	assert(bootstrap.request_threaded_prefetch() == 1)
	assert(not bootstrap.has_failed_required_resource())
	Cache.clear_for_test()
	assert(Cache.request_threaded_paths([TEXTURE, OTHER_TEXTURE, MISSING]) == 2)
	assert(Cache.threaded_pending_count() == 0)
	assert(Cache.headless_prefetch_diagnostics().failure_count == 1)
	assert(Cache.headless_prefetch_diagnostics().load_count == 3)
	assert(Cache.texture_at_path(TEXTURE) is Texture2D)
	assert(Cache.texture_at_path(MISSING) == null)
	assert(Cache.request_threaded_paths([TEXTURE, MISSING]) == 0)
	assert(Cache.headless_prefetch_diagnostics().load_count == 3, "Failed prefetch must not retry via fallback")
	assert(Cache.sync_miss_count() == 0)
	# Explicitly exercise the unchanged async branch via the test-only switch.
	# This is one cached resource, not a claim that the engine race is repaired.
	PlayerState.test_mode = false
	Cache.clear_for_test()
	Cache._test_force_threaded_prefetch = true
	assert(Cache.request_threaded_paths([TEXTURE]) == 1)
	assert(Cache.threaded_pending_count() == 1)
	assert(Cache.headless_prefetch_diagnostics().load_count == 0)
	var deadline := Time.get_ticks_msec() + 10000
	while Cache.threaded_pending_count() > 0 and Time.get_ticks_msec() < deadline:
		Cache.poll_threaded_paths()
		await get_tree().process_frame
	assert(Cache.threaded_pending_count() == 0)
	assert(Cache.texture_at_path(TEXTURE) is Texture2D)
	PlayerState.test_mode = true
	Cache.clear_for_test()
	print("HEADLESS_PREFETCH_COMPATIBILITY_PASS manifest_fail_closed=true production_async_preserved=true")
	get_tree().quit()
