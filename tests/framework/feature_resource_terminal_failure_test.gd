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
	var imported := ConfigFile.new()
	check(imported.load(path + ".import") == OK, "primary image has its existing importer mapping")
	var cache_path: String = imported.get_value("remap", "path", "")
	var permitted := cache_path.begins_with("res://.godot/imported/Items_00014.png-") and cache_path.ends_with(".ctex")
	check(permitted and not ResourceLoader.has_cached(path), "fault targets only this worktree's uncached imported artifact")
	if permitted:
		var original := FileAccess.get_file_as_bytes(cache_path)
		check(not original.is_empty(), "original imported bytes are captured before fault injection")
		var file := FileAccess.open(cache_path, FileAccess.WRITE)
		check(file != null, "test can write its selected disposable imported artifact")
		if file != null:
			file.store_buffer("OWNED_TERMINAL_FAILURE".to_utf8_buffer())
			file.close()
			var box := {"finished":false,"success":true}
			_capture(box)
			var service: Node = ContentLayers._feature_resource_service
			for index in range(180):
				if service.metrics().request_calls > 0: break
				await get_tree().process_frame
			get_tree().paused = true
			check(service.metrics().request_calls == 1 and service.metrics().get_calls == 0, "formal service owns one started engine request before terminal retrieval")
			var deadline := Time.get_ticks_msec() + 3000
			while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			var failed_status := ResourceLoader.load_threaded_get_status(path)
			check(failed_status == ResourceLoader.THREAD_LOAD_FAILED, "real engine worker reaches THREAD_LOAD_FAILED on corrupt imported bytes")
			get_tree().paused = false
			for index in range(180):
				if box.finished and service.pending_count() == 0: break
				await get_tree().process_frame
			check(box.finished and not box.success, "terminal engine failure ends the original waiting producer with rejection")
			check(ContentLayers.feature_load_errors == ["feature_resource_load_failed:" + path], "formal publication propagates the resource-specific business failure")
			check(is_same(old.catalog, ContentLayers.feature_configuration().catalog) and is_same(bundle, PlayerState.feature_bundle()) and stats == PlayerState.computed_stats,
				"load failure preserves old catalog actual bundle and computed stats")
			check(service.metrics().get_calls == 1 and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
				"terminal failure retrieves once and releases its engine user token")
			check(service.pending_count() == 0 and not service.is_processing() and Budget.snapshot().open_scopes == 0,
				"failed jobs requests retirement and shared budget scopes all finish")
			file = FileAccess.open(cache_path, FileAccess.WRITE)
			if file != null:
				file.store_buffer(original)
				file.close()
			check(FileAccess.get_file_as_bytes(cache_path) == original, "test restores exact original imported bytes before a fresh lawful attempt")
			check(await ContentLayers.reload_feature_catalog_async(REGISTRY), "fresh lawful preparation succeeds after terminal failure without a stale task")
			check(ContentLayers.feature_configuration().resource_lease.resource_at(path) is Texture2D, "retry through the unchanged production API owns a usable actual primary texture")
			check(ContentLayers.reload_feature_catalog(), "empty baseline can restore after actual engine failure and recovery")
	if not proof.write_receipt("feature_resource_terminal_failure_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_TERMINAL_FAILURE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
