extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REGISTRY := "res://assets/data/features/validation/resource_ready_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _capture(box: Dictionary) -> void:
	box.success = await ContentLayers.reload_feature_catalog_async(REGISTRY)
	box.finished = true

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	var old := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	var path: String = GameData.get_item_art_path("hc.item.910007", "inventoryIcon")
	check(not ResourceLoader.has_cached(path), "cancellation case begins with the actual primary texture uncached")
	var box := {"finished":false,"success":true}
	_capture(box)
	var service: Node = ContentLayers._feature_resource_service
	check(not box.finished and ContentLayers._feature_publication_in_progress and service.pending_count() == 1, "real asynchronous publication owns one pending resource job")
	for index in range(120):
		if service.metrics().request_calls == 1: break
		await get_tree().process_frame
	get_tree().paused = true
	check(service.metrics().request_calls == 1 and service.metrics().get_calls == 0, "cancellation occurs after this service starts its engine request and before retrieval")
	var status := ResourceLoader.load_threaded_get_status(path)
	check(status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED], "the owned engine request still has a live retrieval right regardless of worker speed")
	ContentLayers.cancel_feature_resource_preparation()
	check(box.finished and not box.success and not ContentLayers._feature_publication_in_progress, "explicit cancellation terminates the original waiting publisher immediately")
	check(service.metrics().jobs == 1, "cancellation keeps ownership of the already started engine job until terminal cleanup")
	check(is_same(ContentLayers.feature_configuration().catalog, old.catalog) and is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats, "cancellation never publishes partial directory or player results")
	get_tree().paused = false
	for index in range(180):
		if service.pending_count() == 0: break
		await get_tree().process_frame
	check(service.pending_count() == 0, "cancelled engine job and acquired resource retire through ordinary processing")
	check(service.metrics().request_calls == 1 and service.metrics().get_calls == 1, "the cancelled owner releases exactly its one engine retrieval token")
	check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "terminal cleanup leaves no abandoned threaded retrieval right")
	check(not box.success and is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats, "late worker completion cannot turn cancellation into a successful publication")
	check(not service.is_processing() and Budget.snapshot().open_scopes == 0, "cancelled preparation returns to idle with all budget scopes closed")
	check(ContentLayers.reload_feature_catalog(), "ordinary empty publication remains available after cancellation")
	if not proof.write_receipt("feature_resource_started_cancel_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_STARTED_CANCEL_%s checks=%d observed_status=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, status, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
