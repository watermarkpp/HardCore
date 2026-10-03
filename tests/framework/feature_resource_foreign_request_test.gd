extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	var path: String = GameData.get_item_art_path("hc.item.910007", "inventoryIcon")
	check(not ResourceLoader.has_cached(path), "foreign producer starts with actual primary path uncached")
	# IGNORE is an official engine mode, used here to keep the pending user
	# retrieval distinguishable from a cache hit. No fake resource or loader.
	check(ResourceLoader.load_threaded_request(path, "Texture2D", false, ResourceLoader.CACHE_MODE_IGNORE) == OK, "external producer owns one real engine threaded request")
	var deadline := Time.get_ticks_msec() + 3000
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED and not ResourceLoader.has_cached(path), "actual external request is loaded but its separate retrieval remains outstanding")
	check(await ContentLayers.reload_feature_catalog_async("res://assets/data/features/validation/resource_ready_registry.json"), "feature preparation joins the same real engine resource")
	var ready: RefCounted = ContentLayers.feature_configuration().resource_lease
	check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED, "feature consumer never spends the foreign producer retrieval right")
	var external: Resource = null
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		external = ResourceLoader.load_threaded_get(path)
	check(external is Texture2D and is_same(external, ready.resource_at(path)), "both consumers retrieve the shared actual resource through their own engine request")
	check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "all owned retrieval rights finish without a leaked engine request")
	check(ContentLayers.reload_feature_catalog(), "fixture restores the ordinary empty configuration")
	if not proof.write_receipt("feature_resource_foreign_request_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_FOREIGN_REQUEST_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
